#!/bin/bash

echo "========== FIXING ARGO WORKFLOWS CNI ISSUES (ALL PODS) =========="

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

# Step 1: Disable Multus for the entire namespace
echo "Disabling Multus for the entire argo namespace..."
oc annotate namespace argo k8s.v1.cni.cncf.io/networks="" --overwrite
oc annotate namespace argo k8s.v1.cni.cncf.io/networks-status="" --overwrite

# Step 2: Fix security context constraints for all service accounts
echo "Adding security permissions to all relevant service accounts..."
oc adm policy add-scc-to-user privileged -z argo -n argo
oc adm policy add-scc-to-user privileged -z argo-server -n argo
oc adm policy add-scc-to-user privileged -z workflow-controller -n argo
oc adm policy add-scc-to-user privileged -z default -n argo

# Add network-admin roles
echo "Adding network admin roles to all service accounts..."
oc adm policy add-cluster-role-to-user system:netadmin -z argo -n argo
oc adm policy add-cluster-role-to-user system:netadmin -z argo-server -n argo
oc adm policy add-cluster-role-to-user system:netadmin -z workflow-controller -n argo
oc adm policy add-cluster-role-to-user system:netadmin -z default -n argo

# Step 3: Update all deployments to use hostNetwork
echo "Updating all Argo deployments to use hostNetwork..."

# Update argo-server
echo "Updating argo-server deployment..."
cat <<EOF | oc apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: argo-server
  namespace: argo
  annotations:
    k8s.v1.cni.cncf.io/networks-status: ""
spec:
  template:
    metadata:
      annotations:
        k8s.v1.cni.cncf.io/networks: ""
    spec:
      hostNetwork: true
      dnsPolicy: ClusterFirstWithHostNet
      securityContext:
        runAsNonRoot: false
        runAsUser: 0
EOF

# Update workflow-controller
echo "Updating workflow-controller deployment..."
cat <<EOF | oc apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: workflow-controller
  namespace: argo
  annotations:
    k8s.v1.cni.cncf.io/networks-status: ""
spec:
  template:
    metadata:
      annotations:
        k8s.v1.cni.cncf.io/networks: ""
    spec:
      hostNetwork: true
      dnsPolicy: ClusterFirstWithHostNet
      securityContext:
        runAsNonRoot: false
        runAsUser: 0
EOF

# Step 4: Make sure service configurations are correct
echo "Ensuring argo-server service has the correct configuration..."
oc patch service argo-server -n argo --type=json -p '[
  {"op":"replace", "path":"/spec/ports/0/port", "value":2746},
  {"op":"replace", "path":"/spec/ports/0/targetPort", "value":2746}
]'

# Step 5: Fix routing configuration
echo "Fixing argo-server route configuration..."
oc delete route argo-server -n argo --ignore-not-found

# Create a route with edge termination (better for local development)
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

# Step 6: Create a permissive NetworkPolicy for the namespace
echo "Creating permissive NetworkPolicy..."
cat <<EOF | oc apply -f -
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-all-argo
  namespace: argo
spec:
  podSelector: {}
  ingress:
  - {}
  egress:
  - {}
  policyTypes:
  - Ingress
  - Egress
EOF

# Step 7: Delete all pods to force recreation with new settings
echo "Deleting all existing pods to apply changes..."
oc delete pods --all -n argo

echo "Waiting for pods to restart..."
sleep 10

echo "Current pod status:"
oc get pods -n argo

# Step 8: Configure the Argo server with the right arguments
echo "Configuring argo-server with correct arguments..."
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

# Step 9: Wait for deployments to be ready
echo "Waiting for deployments to become ready..."
oc rollout status deployment/argo-server -n argo --timeout=120s
oc rollout status deployment/workflow-controller -n argo --timeout=120s

# Final check
echo -e "\nFinal status:"
echo "-----------------"
oc get pods -n argo

ROUTE=$(oc get route -n argo argo-server -o jsonpath='{.spec.host}' 2>/dev/null)
if [ -n "$ROUTE" ]; then
    echo -e "\nArgo UI should be available at: https://$ROUTE"
    echo "It may take a few minutes for the route to become active."
    echo "Try accessing it in your browser now."
fi

echo -e "\nIf you're still experiencing issues, try this alternative approach:"
echo "1. Completely uninstall Argo Workflows:"
echo "   oc delete namespace argo"
echo ""
echo "2. Create a new namespace with a custom label that might help with networking:"
echo "   oc new-project argo"
echo "   oc label namespace argo network.openshift.io/policy-group=ingress"
echo "   oc label namespace argo pod-security.kubernetes.io/enforce=privileged"
echo ""
echo "3. Install a version of Argo Workflows that's more compatible with OpenShift:"
echo "   curl -sL https://raw.githubusercontent.com/argoproj/argo-workflows/v3.4.8/manifests/install.yaml > argo-install.yaml"
echo "   # Edit the argo-install.yaml to add hostNetwork: true to all deployments"
echo "   oc apply -f argo-install.yaml -n argo"
echo ""
echo "4. For local testing only, you can also try port-forwarding as a workaround:"
echo "   oc port-forward svc/argo-server 2746:2746 -n argo"
echo "   # Then access at http://localhost:2746" 