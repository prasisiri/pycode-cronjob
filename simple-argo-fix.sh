#!/bin/bash

echo "========== SIMPLIFIED ARGO WORKFLOWS FIX FOR LOCAL POC =========="

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
    echo "Creating argo namespace..."
    oc new-project argo
else
    echo "✅ Found argo namespace"
fi

# Basic SCC for PoC
echo "Adding basic SCC permissions (anyuid only)..."
oc adm policy add-scc-to-user anyuid -z argo -n argo
oc adm policy add-scc-to-user anyuid -z argo-server -n argo
oc adm policy add-scc-to-user anyuid -z default -n argo

# Basic admin roles
echo "Adding basic admin permissions..."
oc adm policy add-role-to-user admin system:serviceaccount:argo:argo
oc adm policy add-role-to-user admin system:serviceaccount:argo:argo-server

# Simplified argo-server deployment patch - just set runAsUser: 0
echo "Patching argo-server deployment with minimal changes..."
cat <<EOF | oc apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: argo-server
  namespace: argo
spec:
  template:
    spec:
      securityContext:
        runAsNonRoot: false
        runAsUser: 0
EOF

echo "✅ Patched argo-server deployment"

# Restart argo-server pods to apply changes
echo "Restarting argo-server pods..."
oc delete pod -n argo -l app=argo-server

echo "Waiting for pods to restart..."
sleep 5

# Check if argo-server pods are running now
TIMEOUT=30
COUNT=0
while [ $COUNT -lt $TIMEOUT ]; do
    if oc get pods -n argo -l app=argo-server | grep -q "Running"; then
        echo "✅ argo-server pod is now running!"
        break
    fi
    echo "Waiting for argo-server pod to start... (${COUNT}s/${TIMEOUT}s)"
    sleep 5
    COUNT=$((COUNT+5))
done

if [ $COUNT -ge $TIMEOUT ]; then
    echo "❌ Timeout waiting for argo-server pod to start"
    echo "Please check the pod status and logs:"
    oc get pods -n argo -l app=argo-server
    POD=$(oc get pods -n argo -l app=argo-server -o name | head -n1)
    if [ -n "$POD" ]; then
        echo "Pod events:"
        oc describe -n argo $POD
    fi
fi

# Re-create the route if needed
echo "Checking argo-server route..."
if ! oc get route -n argo argo-server &> /dev/null; then
    echo "Creating route for argo-server..."
    oc -n argo expose service argo-server
    echo "✅ Created route for argo-server"
else
    echo "✅ argo-server route already exists"
fi

# Final check
echo -e "\nFinal status:"
echo "-----------------"
oc get pods -n argo -l app=argo-server
ROUTE=$(oc get route -n argo argo-server -o jsonpath='{.spec.host}' 2>/dev/null)
if [ -n "$ROUTE" ]; then
    echo -e "\nArgo UI should be available at: https://$ROUTE"
    echo "It may take a few minutes for the route to become active."
fi

echo -e "\nIf you're still having issues, try the following:"
echo "1. Delete and recreate the argo namespace:"
echo "   oc delete project argo"
echo "   oc new-project argo"
echo "   # Then reinstall Argo Workflows"
echo ""
echo "2. For persistent issues, consider using Minikube or Kind instead of OpenShift for your PoC" 