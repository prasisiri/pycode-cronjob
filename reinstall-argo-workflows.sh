#!/bin/bash

echo "========== REINSTALLING ARGO WORKFLOWS FOR LOCAL POC =========="

# Check if oc is available and user is logged in
if ! command -v oc &> /dev/null; then
    echo "❌ Error: OpenShift CLI (oc) is not installed or not in PATH"
    exit 1
fi

if ! oc whoami &> /dev/null; then
    echo "❌ Error: Not logged into OpenShift. Please login first using 'oc login'"
    exit 1
fi

# Step 1: Remove existing Argo installation if present
echo "Removing any existing Argo Workflows installation..."
oc delete namespace argo --ignore-not-found
sleep 5

# Step 2: Create a fresh namespace
echo "Creating fresh argo namespace..."
oc new-project argo

# Add network policy label for OpenShift
oc label namespace argo network.openshift.io/policy-group=ingress --overwrite

# Step 3: Download the correct Argo Workflows manifest
echo "Downloading Argo Workflows manifest (v3.4.8)..."
ARGO_VERSION="v3.4.8"
curl -sLo argo-install.yaml "https://github.com/argoproj/argo-workflows/releases/download/${ARGO_VERSION}/install.yaml"

if [ ! -s argo-install.yaml ]; then
    echo "❌ Failed to download Argo Workflows manifest"
    exit 1
fi

echo "✅ Downloaded Argo Workflows manifest ($(wc -l < argo-install.yaml) lines)"

# Step 4: Modify the installation YAML for OpenShift compatibility
echo "Modifying installation YAML for OpenShift compatibility..."
# Make a backup of the original file
cp argo-install.yaml argo-install.yaml.original

# Replace the security context in all deployments
sed -i.bak '/securityContext:/,/runAsNonRoot/c\
        securityContext:\
          runAsNonRoot: false\
          runAsUser: 0' argo-install.yaml

# Set hostNetwork to true
sed -i.bak '/hostNetwork/c\
        hostNetwork: true' argo-install.yaml

# Add hostNetwork if not present
sed -i.bak '/dnsPolicy:/i\
        hostNetwork: true' argo-install.yaml

# Disable auth by modifying the args
sed -i.bak '/args:/,/server/c\
        args:\
        - server\
        - --auth-mode=server\
        - --secure=false' argo-install.yaml

# Step 5: Apply the modified installation
echo "Applying modified Argo Workflows installation..."
oc apply -f argo-install.yaml -n argo

# Step 6: Add necessary permissions
echo "Adding necessary permissions..."
oc adm policy add-scc-to-user privileged -z argo -n argo
oc adm policy add-scc-to-user privileged -z argo-server -n argo
oc adm policy add-scc-to-user privileged -z default -n argo

oc adm policy add-role-to-user admin system:serviceaccount:argo:argo
oc adm policy add-role-to-user admin system:serviceaccount:argo:argo-server

# Step 7: Create ConfigMap for workflow controller
echo "Creating workflow controller ConfigMap..."
cat <<EOF | oc apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: workflow-controller-configmap
  namespace: argo
data:
  config: |
    executorImage: argoproj/argoexec:${ARGO_VERSION}
    containerRuntimeExecutor: emissary
    workflowDefaults:
      spec:
        serviceAccountName: argo
EOF

# Step 8: Create a route for the Argo server
echo "Creating route for Argo server..."
oc expose service argo-server --port=2746 -n argo

# Step 9: Update the Argo server deployment with environment variables for auth
echo "Adding environment variables to disable auth..."
cat <<EOF | oc apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: argo-server
  namespace: argo
spec:
  template:
    spec:
      containers:
      - name: argo-server
        env:
        - name: ARGO_SECURE
          value: "false"
        - name: ARGO_INSECURE_SKIP_VERIFY
          value: "true"
        - name: ARGO_SERVER_DISABLE_AUTH
          value: "true"
EOF

# Step 10: Restart the Argo server to apply changes
echo "Restarting deployments..."
oc rollout restart deployment argo-server -n argo
oc rollout restart deployment workflow-controller -n argo

echo "Waiting for deployments to become ready..."
oc rollout status deployment argo-server -n argo --timeout=120s
oc rollout status deployment workflow-controller -n argo --timeout=120s

# Step 11: Final status
echo -e "\nFinal status:"
echo "-----------------"
oc get pods -n argo

ROUTE=$(oc get route -n argo argo-server -o jsonpath='{.spec.host}' 2>/dev/null)
if [ -n "$ROUTE" ]; then
    echo -e "\nArgo UI should be available at: https://$ROUTE"
    echo "It may take a few minutes for the route to become active."
fi

echo -e "\nIf you're still experiencing issues, try port-forwarding as a last resort:"
echo "oc port-forward svc/argo-server 2746:2746 -n argo"
echo "Then access Argo UI at: http://localhost:2746" 