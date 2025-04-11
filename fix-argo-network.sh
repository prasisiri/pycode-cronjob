#!/bin/bash

echo "========== FIXING ARGO WORKFLOWS NETWORKING ISSUES =========="

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
    echo "❌ Error: Argo namespace not found."
    exit 1
fi

echo "✅ Connected to OpenShift and found argo namespace"

# Step 1: Patch NetworkAttachmentDefinition to fix CNI issues
echo "Checking for NetworkAttachmentDefinition..."
if oc get networkattachmentdefinition -n argo multus-cni-network &> /dev/null; then
    echo "✅ NetworkAttachmentDefinition exists. Patching it..."
    oc patch networkattachmentdefinition multus-cni-network -n argo --type=merge -p '{"metadata":{"annotations":{"k8s.v1.cni.cncf.io/resourceName": ""}}}' || true
else
    echo "⚠️ No NetworkAttachmentDefinition found. Creating one..."
    cat <<EOF | oc apply -f -
apiVersion: "k8s.cni.cncf.io/v1"
kind: NetworkAttachmentDefinition
metadata:
  name: multus-cni-network
  namespace: argo
  annotations:
    k8s.v1.cni.cncf.io/resourceName: ""
spec:
  config: '{
    "cniVersion": "0.3.1",
    "name": "multus-cni-network",
    "type": "macvlan",
    "master": "eth0",
    "mode": "bridge",
    "ipam": {
      "type": "host-local",
      "subnet": "192.168.1.0/24",
      "rangeStart": "192.168.1.200",
      "rangeEnd": "192.168.1.216",
      "routes": [
        { "dst": "0.0.0.0/0" }
      ],
      "gateway": "192.168.1.1"
    }
  }'
EOF
fi

# Step 2: Add additional SCCs to fix permission issues
echo "Adding additional Security Context Constraints..."
oc adm policy add-scc-to-user privileged -z argo -n argo || true
oc adm policy add-scc-to-user privileged -z argo-server -n argo || true
oc adm policy add-scc-to-user privileged -z default -n argo || true
oc adm policy add-role-to-user cluster-admin -z argo-server -n argo || true
oc adm policy add-role-to-user cluster-admin -z argo -n argo || true

# Add network-admin role (for Multus authorization)
echo "Adding network-admin role to service accounts..."
oc adm policy add-cluster-role-to-user network-admin -z argo-server -n argo || true
oc adm policy add-cluster-role-to-user network-admin -z argo -n argo || true
oc adm policy add-cluster-role-to-user network-admin -z default -n argo || true

echo "✅ Added privileged SCCs and network roles to argo service accounts"

# Step 3: Patch argo-server deployment to use host network and avoid Multus
echo "Patching argo-server deployment to bypass Multus CNI issues..."
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
        k8s.v1.cni.cncf.io/networks-status: ""
    spec:
      hostNetwork: true
      dnsPolicy: ClusterFirstWithHostNet
      securityContext:
        runAsNonRoot: false
        runAsUser: 0
EOF

echo "✅ Patched argo-server deployment"

# Step 4: Disable Multus for this namespace if possible
echo "Trying to disable Multus for argo namespace..."
oc annotate namespace argo k8s.v1.cni.cncf.io/networks="" --overwrite || true
oc label namespace argo network-policy=argo --overwrite || true

# Step 5: Restart argo-server pods to apply changes
echo "Restarting argo-server pods..."
oc delete pod -n argo -l app=argo-server

echo "Waiting for pods to restart..."
sleep 5

# Step 6: Check if argo-server pods are running now
TIMEOUT=60
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

# Step 7: Create NetworkPolicy to allow required communication
echo "Creating NetworkPolicy for Argo..."
cat <<EOF | oc apply -f -
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-argo-server
  namespace: argo
spec:
  podSelector:
    matchLabels:
      app: argo-server
  ingress:
  - {}
  egress:
  - {}
  policyTypes:
  - Ingress
  - Egress
EOF

echo "✅ Created NetworkPolicy for argo-server"

# Step 8: Re-create the route if needed
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

echo -e "\nNOTE: If you're still experiencing issues, try these additional steps:"
echo "1. Check if the cluster is using a different CNI plugin by running:"
echo "   oc get network.config/cluster -o yaml"
echo ""
echo "2. For OpenShift 4.x, you might need to use a specific network policy:"
echo "   oc label namespace argo 'network.openshift.io/policy-group=ingress'"
echo ""
echo "3. As a last resort, you can completely disable the Multus CNI for your argo pods:"
echo "   oc patch network.operator.openshift.io cluster --type=merge -p '{\"spec\":{\"disableMultiNetwork\":true}}'"
echo "   (Note: This affects the entire cluster, so use with caution)"
echo ""
echo "4. If this script doesn't resolve your issue, you may need to reinstall Argo with:"
echo "   oc delete namespace argo"
echo "   oc new-project argo"
echo "   # Then run your installation script again" 