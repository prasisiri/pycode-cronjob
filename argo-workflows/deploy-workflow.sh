#!/bin/bash

# Check if oc is available and user is logged in
if ! command -v oc &> /dev/null; then
    echo "Error: OpenShift CLI (oc) is not installed or not in PATH"
    exit 1
fi

if ! oc whoami &> /dev/null; then
    echo "Error: Not logged into OpenShift. Please login first using 'oc login'"
    exit 1
fi

# Verify if Argo is installed
if ! oc get namespace argo &> /dev/null; then
    echo "Setting up Argo Workflows in OpenShift..."
    
    # Create the argo namespace
    oc new-project argo
    
    # Install Argo Workflows
    echo "Getting latest Argo Workflows version..."
    ARGO_VERSION=$(curl --silent "https://api.github.com/repos/argoproj/argo-workflows/releases/latest" | grep '"tag_name"' | sed -E 's/.*"([^"]+)".*/\1/')
    if [ -z "$ARGO_VERSION" ]; then
        echo "Could not determine latest version, using v3.5.4 as default"
        ARGO_VERSION="v3.5.4"
    fi
    echo "Installing Argo Workflows version $ARGO_VERSION..."
    
    # Install Argo Workflows using the versioned installation manifest
    oc apply -n argo -f https://github.com/argoproj/argo-workflows/releases/download/$ARGO_VERSION/install.yaml
    
    if [ $? -ne 0 ]; then
        echo "Failed to install Argo Workflows using dynamic version."
        echo "Falling back to fixed version v3.5.4..."
        oc apply -n argo -f https://github.com/argoproj/argo-workflows/releases/download/v3.5.4/install.yaml
        
        if [ $? -ne 0 ]; then
            echo "Installation failed. Please check your connection and try again."
            exit 1
        fi
    fi
    
    # Set up permissions
    echo "Setting up permissions..."
    oc adm policy add-role-to-user admin system:serviceaccount:argo:argo
    oc adm policy add-role-to-user admin system:serviceaccount:argo:argo-server
    
    # Add required security context constraints for OpenShift
    echo "Adding security context constraints..."
    oc adm policy add-scc-to-user anyuid -z argo -n argo
    oc adm policy add-scc-to-user anyuid -z argo-server -n argo
    oc adm policy add-scc-to-user anyuid -z default -n argo
    
    # Expose the Argo Server UI
    echo "Exposing Argo Server UI..."
    oc -n argo expose deployment argo-server --port=2746 --type=LoadBalancer
    oc -n argo expose service argo-server
    
    echo "Argo Workflows installed successfully"
else
    echo "Argo Workflows is already installed"
fi

# Create project for our workflow
PROJECT_NAME="sales-analysis"
if ! oc get project $PROJECT_NAME &> /dev/null; then
    echo "Creating project $PROJECT_NAME..."
    oc new-project $PROJECT_NAME
else
    echo "Using existing project $PROJECT_NAME"
    oc project $PROJECT_NAME
fi

# Create the SFTP upload configuration
echo "Creating upload configuration secret..."
UPLOAD_CONFIG=$(cat << EOL
[sftp]
host = localhost
port = 2222
username = sftpuser
password = password
remote_path = /upload

[s3]
endpoint_url = https://s3.amazonaws.com
s3_access_key = YOUR_ACCESS_KEY
s3_secret_key = YOUR_SECRET_KEY
bucket = sales-reports
region = us-east-1

[http]
url = https://api.example.com/upload
method = POST
username = user
password = password
EOL
)

# Create the secret
echo "$UPLOAD_CONFIG" > temp-upload-config.ini
oc create secret generic upload-config --from-file=upload-config.ini=temp-upload-config.ini
if [ $? -ne 0 ]; then
    echo "Warning: Failed to create secret. Trying to replace it..."
    oc replace --force -f - <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: upload-config
data:
  upload-config.ini: $(cat temp-upload-config.ini | base64 | tr -d '\n')
EOF
fi
rm temp-upload-config.ini

# Create ServiceAccount with proper permissions for Argo to run workflows
echo "Setting up ServiceAccount for workflow execution..."
oc create sa workflow || true
oc adm policy add-role-to-user edit -z workflow || true
oc adm policy add-scc-to-user anyuid -z workflow || true

# Install workflow template
echo "Installing workflow template..."
oc apply -f workflow-templates/sales-analysis-template.yaml

# Install complete workflow
echo "Installing data analysis workflow..."
oc apply -f workflows/data-analysis-workflow.yaml

# Create the CronWorkflow
echo "Installing CronWorkflow..."
oc apply -f cronworkflows/sales-analysis-cron.yaml

echo ""
echo "========================================================"
echo "Argo Workflows and templates deployed successfully!"
echo ""
echo "You can access the Argo UI at:"
echo "https://$(oc -n argo get route argo-server -o jsonpath='{.spec.host}')"
echo ""
echo "To run a workflow manually:"
echo "oc -n $PROJECT_NAME create -f workflows/data-analysis-workflow.yaml"
echo ""
echo "To view workflows:"
echo "oc get workflows"
echo ""
echo "To view running workflows in the UI, go to:"
echo "https://$(oc -n argo get route argo-server -o jsonpath='{.spec.host}')/workflows/$PROJECT_NAME"
echo "========================================================" 