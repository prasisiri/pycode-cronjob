#!/bin/bash

echo "========== FIXING ARGO SERVER ROUTE (502 BAD GATEWAY) =========="

# Check if oc is available and user is logged in
if ! command -v oc &> /dev/null; then
    echo "❌ Error: OpenShift CLI (oc) is not installed or not in PATH"
    exit 1
fi

if ! oc whoami &> /dev/null; then
    echo "❌ Error: Not logged into OpenShift. Please login first using 'oc login'"
    exit 1
fi

# Check if argo namespace exists
if ! oc get namespace argo &> /dev/null; then
    echo "❌ Error: Argo namespace not found. Please install Argo Workflows first."
    exit 1
fi

# Get the current state of the service and route
echo "Current state of argo-server service:"
oc get service argo-server -n argo -o yaml | grep -E "targetPort|port|protocol"

echo "Current state of argo-server route:"
oc get route argo-server -n argo -o yaml | grep -E "port|targetPort|termination|insecureEdgeTerminationPolicy"

echo "Current state of argo-server deployment:"
oc get deployment argo-server -n argo -o yaml | grep -E "containerPort|protocol|hostPort|command|args" -A 5

# Step 1: Check if the pod is running and get its status
echo "Checking argo-server pod status..."
POD=$(oc get pods -n argo -l app=argo-server -o name | head -1)
if [ -z "$POD" ]; then
    echo "❌ Error: argo-server pod not found"
    exit 1
fi

echo "Pod status:"
oc get $POD -n argo -o jsonpath='{.status.phase}'
echo ""

# Step 2: Fix the service
echo "Patching argo-server service to ensure correct port configuration..."
oc patch service argo-server -n argo --type=json -p '[
  {"op":"replace", "path":"/spec/ports/0/port", "value":2746},
  {"op":"replace", "path":"/spec/ports/0/targetPort", "value":2746}
]'

# Step 3: Delete and recreate the route with proper configuration
echo "Deleting existing route..."
oc delete route argo-server -n argo --ignore-not-found

echo "Creating new route with proper configuration..."
cat <<EOF | oc apply -f -
apiVersion: route.openshift.io/v1
kind: Route
metadata:
  name: argo-server
  namespace: argo
spec:
  port:
    targetPort: 2746
  tls:
    insecureEdgeTerminationPolicy: Redirect
    termination: passthrough
  to:
    kind: Service
    name: argo-server
    weight: 100
EOF

# Step 4: Check and fix the deployment if needed
echo "Checking if deployment has the correct port configuration..."
if ! oc get deployment argo-server -n argo -o yaml | grep -q "containerPort: 2746"; then
    echo "Patching deployment with correct port..."
    oc patch deployment argo-server -n argo --type=json -p '[
      {"op":"replace", "path":"/spec/template/spec/containers/0/ports/0/containerPort", "value":2746}
    ]'
fi

# Step 5: Add proper arguments to the deployment if missing
echo "Ensuring argo-server has the correct command line arguments..."
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
        args:
        - server
        - --auth-mode=server
        - --secure=false
EOF

# Step 6: Restart the deployment
echo "Restarting argo-server deployment..."
oc rollout restart deployment argo-server -n argo

echo "Waiting for deployment to finish rolling out..."
oc rollout status deployment argo-server -n argo --timeout=60s

# Step 7: Verify the configuration
echo -e "\nVerifying final configuration..."

echo "Service:"
oc get service argo-server -n argo

echo "Route:"
oc get route argo-server -n argo

echo "Pod Status:"
oc get pods -n argo -l app=argo-server

ROUTE=$(oc get route -n argo argo-server -o jsonpath='{.spec.host}' 2>/dev/null)
if [ -n "$ROUTE" ]; then
    echo -e "\nArgo UI should be available at: https://$ROUTE"
    echo "It may take a few minutes for the route to become active."
    echo "Try accessing it in your browser now."
fi

echo -e "\nIf you're still experiencing 502 Bad Gateway errors, try these additional steps:"
echo "1. Check the argo-server logs:"
echo "   oc logs -n argo \$(oc get pods -n argo -l app=argo-server -o name | head -1)"
echo ""
echo "2. For insecure local development, try setting up an edge route instead:"
echo "   oc delete route argo-server -n argo"
echo "   oc create route edge argo-server --service=argo-server --port=2746 -n argo"
echo ""
echo "3. You can use port-forwarding as a temporary solution:"
echo "   oc port-forward -n argo \$(oc get pods -n argo -l app=argo-server -o name | head -1) 2746:2746"
echo "   Then access Argo UI at: http://localhost:2746"
echo ""
echo "4. If none of the above work, try uninstalling and reinstalling Argo Workflows:"
echo "   oc delete namespace argo"
echo "   oc new-project argo"
echo "   # Then reinstall Argo Workflows with a custom configuration that works better in OpenShift" 