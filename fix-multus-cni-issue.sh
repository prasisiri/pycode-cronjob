#!/bin/bash

echo "========== FIXING MULTUS CNI NETWORKING ISSUE =========="

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

# Method 1: Try to disable Multus for the argo namespace
echo "Method 1: Disabling Multus for the argo namespace..."
oc annotate namespace argo k8s.v1.cni.cncf.io/networks="" --overwrite
oc annotate namespace argo k8s.v1.cni.cncf.io/networks-status="" --overwrite

# Method 2: Modify the argo-server deployment to use the default network only
echo "Method 2: Updating argo-server deployment to use hostNetwork..."
oc patch deployment argo-server -n argo --type=json -p '[
  {"op":"add", "path":"/spec/template/spec/hostNetwork", "value":true},
  {"op":"add", "path":"/spec/template/spec/dnsPolicy", "value":"ClusterFirstWithHostNet"}
]'

# Method 3: Create a minimalistic NetworkAttachmentDefinition
echo "Method 3: Creating a basic NetworkAttachmentDefinition..."
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
    "plugins": [
      {
        "type": "bridge",
        "bridge": "cni0",
        "isGateway": true,
        "ipMasq": true,
        "ipam": {
          "type": "host-local",
          "subnet": "10.88.0.0/16",
          "routes": [
            { "dst": "0.0.0.0/0" }
          ]
        }
      }
    ]
  }'
EOF

# Method 4: Provide necessary permissions specifically for Multus
echo "Method 4: Adding specific network permissions..."
oc adm policy add-cluster-role-to-user system:openshift:scc:privileged -z argo-server -n argo
oc adm policy add-cluster-role-to-user system:openshift:scc:privileged -z argo -n argo
oc adm policy add-cluster-role-to-user system:netadmin -z argo-server -n argo
oc adm policy add-cluster-role-to-user system:netadmin -z argo -n argo

# Method 5: Add annotation to argo-server deployment
echo "Method 5: Adding network annotations to argo-server deployment..."
oc patch deployment argo-server -n argo --type=merge -p '{
  "spec": {
    "template": {
      "metadata": {
        "annotations": {
          "k8s.v1.cni.cncf.io/networks": ""
        }
      }
    }
  }
}'

# Method 6: Create a specific cluster network policy
echo "Method 6: Creating permissive NetworkPolicy..."
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

# Restart argo-server pods
echo "Restarting argo-server pods..."
oc delete pod -n argo -l app=argo-server

echo "Waiting for pods to restart..."
sleep 10

# Check if argo-server pods are running now
echo "Checking argo-server pods status..."
oc get pods -n argo -l app=argo-server

echo -e "\nIf the issue persists, you might need to try a different OpenShift networking approach:"
echo "1. Contact your cluster administrator to check if there are restrictions on Multus CNI usage."
echo "2. Consider installing Argo Workflows without the CNI plugin by editing the installation YAML."
echo "3. For local development, consider using Kind or Minikube instead of OpenShift."
echo ""
echo "You can check the pod events with: oc describe pod -n argo \$(oc get pods -n argo -l app=argo-server -o name | head -1)" 