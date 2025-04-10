#!/bin/bash

# Check if the Docker SFTP container is running
CONTAINER_RUNNING=$(docker ps | grep sftp-server)
if [ -z "$CONTAINER_RUNNING" ]; then
    echo "SFTP server container is not running. Starting it now..."
    ./docker-sftp-server.sh
else
    echo "SFTP server container is already running."
fi

# Get the host IP address that would be accessible from OpenShift
HOST_IP=$(ifconfig | grep -E "([0-9]{1,3}\.){3}[0-9]{1,3}" | grep -v 127.0.0.1 | awk '{ print $2 }' | cut -f2 -d: | head -n1)
if [ -z "$HOST_IP" ]; then
    echo "Could not determine your host IP. Please enter it manually:"
    read -p "Host IP: " HOST_IP
fi

echo "Using host IP: $HOST_IP"

# Make sure the Docker SFTP server is accessible from external hosts
CONTAINER_ID=$(docker ps -q -f name=sftp-server)
if [ -z "$CONTAINER_ID" ]; then
    echo "Error: SFTP server container not found."
    exit 1
fi

# Recreate the container with host networking if needed
echo "Checking if the SFTP container needs to be reconfigured for external access..."
PORT_MAPPING=$(docker port $CONTAINER_ID)
if [[ ! $PORT_MAPPING == *"0.0.0.0:2222"* ]]; then
    echo "SFTP container needs to be reconfigured for external access."
    echo "Stopping current container..."
    docker stop sftp-server
    docker rm sftp-server
    
    echo "Creating new SFTP container with proper port binding..."
    docker run -d \
      --name sftp-server \
      -p 0.0.0.0:2222:22 \
      -v ~/sftp_test_volume:/home/sftpuser/upload \
      -e SFTP_USERS="sftpuser:password:1001" \
      atmoz/sftp
      
    if [ $? -ne 0 ]; then
        echo "Failed to create the SFTP container. Exiting."
        exit 1
    fi
    echo "SFTP container recreated with proper port binding."
else
    echo "SFTP container is already properly configured."
fi

# Check if the SFTP server is running
docker ps | grep sftp-server
if [ $? -ne 0 ]; then
    echo "SFTP server container is not running. Exiting."
    exit 1
fi

# Test access to the SFTP server from the host
echo "Testing SFTP server accessibility..."
nc -zv $HOST_IP 2222
if [ $? -ne 0 ]; then
    echo "Warning: SFTP server is not accessible at $HOST_IP:2222."
    echo "Please check your firewall settings and make sure port 2222 is open."
    echo "You may need to use a different IP or configure port forwarding."
    read -p "Do you want to continue anyway? (y/n): " CONTINUE
    if [ "$CONTINUE" != "y" ]; then
        exit 1
    fi
else
    echo "SFTP server is accessible at $HOST_IP:2222."
fi

# Create an OpenShift-specific upload config file
OPENSHIFT_CONFIG="openshift-upload-config.ini"
cat > $OPENSHIFT_CONFIG << EOL
[sftp]
host = $HOST_IP
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

echo "Created OpenShift-specific upload configuration: $OPENSHIFT_CONFIG"

# Check if oc command is available
if ! command -v oc &> /dev/null; then
    echo "OpenShift CLI (oc) is not installed or not in PATH."
    echo "Please install the OpenShift CLI and try again."
    exit 1
fi

# Check if user is logged in to OpenShift
oc whoami &> /dev/null
if [ $? -ne 0 ]; then
    echo "You are not logged in to OpenShift. Please log in first:"
    echo "oc login <cluster-url> -u <username> -p <password>"
    exit 1
fi

# Create a secret with the upload configuration
echo "Creating upload-config secret in OpenShift..."
oc create secret generic upload-config --from-file=upload-config.ini=$OPENSHIFT_CONFIG --dry-run=client -o yaml | oc apply -f -

# Check if the secret was created successfully
if [ $? -eq 0 ]; then
    echo "Secret 'upload-config' created successfully"
    
    # Update the CronJob YAML file to use SFTP
    sed -i.bak -e 's/value: ".*"/value: "sftp"/' sales-analysis-cronjob.yaml
    
    echo "Updated CronJob to use SFTP upload method"
    
    # Apply the CronJob
    oc apply -f sales-analysis-cronjob.yaml
    
    echo "CronJob applied to OpenShift"
    echo ""
    echo "==== SUMMARY ===="
    echo "SFTP Server IP: $HOST_IP"
    echo "SFTP Server Port: 2222"
    echo "SFTP Username: sftpuser"
    echo "SFTP Password: password"
    echo "SFTP Upload Path: /upload"
    echo ""
    echo "To monitor the CronJob, use:"
    echo "oc get cronjobs"
    echo "oc get jobs"
    echo "oc get pods"
    echo ""
    echo "To test the CronJob by creating a manual job:"
    echo "oc create job --from=cronjob/sales-analysis-cronjob test-manual-job"
    echo "oc logs job/test-manual-job"
else
    echo "Failed to create secret 'upload-config'"
    exit 1
fi

# Remind user about network connectivity
echo ""
echo "IMPORTANT: Make sure your OpenShift cluster can reach your local machine at $HOST_IP:2222."
echo "You may need to configure your network, firewall, or use a different approach for production environments."
echo "For production, consider using a proper SFTP server that's accessible from your OpenShift cluster." 