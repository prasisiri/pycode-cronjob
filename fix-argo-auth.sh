#!/bin/bash

echo "========== FIXING ARGO WORKFLOWS AUTHENTICATION ISSUES =========="

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

echo "✅ Connected to OpenShift and found argo namespace"

# Step 1: Create a ConfigMap for Argo configuration
echo "Creating ConfigMap with authentication settings..."
cat <<EOF | oc apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: workflow-controller-configmap
  namespace: argo
data:
  config: |
    executorImage: argoproj/argoexec:latest
    executor:
      resources:
        requests:
          cpu: 100m
          memory: 64Mi
        limits:
          cpu: 500m
          memory: 512Mi
    workflowDefaults:
      spec:
        serviceAccountName: argo
    containerRuntimeExecutor: emissary
    metricsConfig:
      enabled: true
      path: /metrics
      port: 9090
EOF

# Step 2: Configure authentication settings
echo "Configuring authentication settings..."
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

# Step 3: Set up service account for server auth
echo "Setting up service account for authentication..."
cat <<EOF | oc apply -f -
apiVersion: v1
kind: ServiceAccount
metadata:
  name: argo-admin
  namespace: argo
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: argo-admin
subjects:
- kind: ServiceAccount
  name: argo-admin
  namespace: argo
roleRef:
  kind: ClusterRole
  name: admin
  apiGroup: rbac.authorization.k8s.io
EOF

# Step 4: Create an admin user secret for local development
echo "Creating admin user credentials for local use..."
cat <<EOF | oc apply -f -
apiVersion: v1
kind: Secret
metadata:
  name: argo-admin-token
  namespace: argo
  annotations:
    kubernetes.io/service-account.name: argo-admin
type: kubernetes.io/service-account-token
EOF

# Step 5: Patch the argo-server deployment to disable authentication (for local PoC only)
echo "Patching argo-server deployment to disable strict authentication for local PoC..."
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

# Step 6: Restart the argo-server deployment
echo "Restarting argo-server deployment..."
oc rollout restart deployment argo-server -n argo

echo "Waiting for deployment to complete..."
oc rollout status deployment/argo-server -n argo --timeout=60s

# Step 7: Configure route to pass through auth tokens
echo "Updating route configuration for authentication..."
oc delete route argo-server -n argo --ignore-not-found

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
    termination: edge
  to:
    kind: Service
    name: argo-server
    weight: 100
EOF

# Step 8: Check status
echo -e "\nFinal status:"
echo "-----------------"
oc get pods -n argo

ROUTE=$(oc get route -n argo argo-server -o jsonpath='{.spec.host}' 2>/dev/null)
if [ -n "$ROUTE" ]; then
    echo -e "\nArgo UI should be available at: https://$ROUTE"
    echo "It may take a few minutes for the route to become active."
    echo "For local PoC, authentication should now be disabled."
    echo "Try accessing it in your browser now."
fi

echo -e "\nIf you're still experiencing authentication issues, try these additional steps:"
echo ""
echo "1. For local development only, you can use port-forwarding which often bypasses auth issues:"
echo "   oc port-forward svc/argo-server 2746:2746 -n argo"
echo "   # Then access at http://localhost:2746"
echo ""
echo "2. For a complete reset, try uninstalling and reinstalling with a custom config:"
echo "   oc delete namespace argo"
echo "   oc new-project argo"
echo "   curl -sL https://raw.githubusercontent.com/argoproj/argo-workflows/v3.4.8/manifests/quick-start/base/manifests.yaml > argo-install.yaml"
echo "   # Edit argo-install.yaml to disable auth before applying"
echo "   oc apply -f argo-install.yaml -n argo"
echo ""
echo "3. Set the server argument to disable auth:"
echo "   oc patch deployment argo-server -n argo --type=json -p '[{\"op\":\"replace\",\"path\":\"/spec/template/spec/containers/0/args\",\"value\":[\"server\",\"--auth-mode=server\",\"--secure=false\",\"--access-control-allow-origin=*\"]}]'" 