#!/bin/bash

# Check if oc is available
if ! command -v oc &> /dev/null; then
    echo "Error: OpenShift CLI (oc) not found. Please install it first."
    exit 1
fi

# Check if logged in to OpenShift
if ! oc whoami &> /dev/null; then
    echo "Error: Not logged in to OpenShift. Please log in first."
    exit 1
fi

echo "=== Creating a test job for debugging ==="
JOB_NAME="debug-sales-analysis-$(date +%s)"
oc create job --from=cronjob/sales-analysis-cronjob $JOB_NAME

echo "Waiting for job pod to start..."
sleep 5

# Get the pod name
POD_NAME=$(oc get pods | grep $JOB_NAME | awk '{print $1}')
if [ -z "$POD_NAME" ]; then
    echo "Error: Could not find pod for job $JOB_NAME"
    echo "Checking all pods:"
    oc get pods
    exit 1
fi

echo "Job pod name: $POD_NAME"

# Wait for the pod to be running
echo "Waiting for pod to be ready..."
POD_STATUS=""
MAX_WAIT=30
COUNTER=0
while [ "$POD_STATUS" != "Running" ] && [ $COUNTER -lt $MAX_WAIT ]; do
    POD_STATUS=$(oc get pod $POD_NAME -o jsonpath='{.status.phase}')
    echo "Pod status: $POD_STATUS"
    sleep 2
    COUNTER=$((COUNTER+1))
done

if [ "$POD_STATUS" != "Running" ]; then
    echo "Pod didn't reach Running state in time. Current status: $POD_STATUS"
    echo "Checking pod events:"
    oc describe pod $POD_NAME
fi

echo ""
echo "=== Checking if sales_report.csv is generated ==="
# Check if the file exists in the pod
if oc exec $POD_NAME -- test -f /app/repo/sales_report.csv 2>/dev/null; then
    echo "✅ sales_report.csv exists in the pod"
    # Get file size
    FILE_SIZE=$(oc exec $POD_NAME -- ls -la /app/repo/sales_report.csv | awk '{print $5}')
    echo "File size: $FILE_SIZE bytes"
    # Get a sample of the file content
    echo "First few lines of the file:"
    oc exec $POD_NAME -- head -n 3 /app/repo/sales_report.csv
else
    echo "❌ sales_report.csv was NOT found in the pod"
    echo "Checking contents of the directory:"
    oc exec $POD_NAME -- ls -la /app/repo/
fi

echo ""
echo "=== Checking network connectivity to SFTP server ==="
# Get the SFTP host from the secret
SFTP_CONFIG=$(oc get secret upload-config -o jsonpath='{.data.upload-config\.ini}' | base64 --decode)
SFTP_HOST=$(echo "$SFTP_CONFIG" | grep -A 5 '[sftp]' | grep 'host' | cut -d'=' -f2 | tr -d ' ')
SFTP_PORT=$(echo "$SFTP_CONFIG" | grep -A 5 '[sftp]' | grep 'port' | cut -d'=' -f2 | tr -d ' ')

echo "SFTP server configured as: $SFTP_HOST:$SFTP_PORT"

# Test connectivity from the pod to the SFTP server
echo "Testing connectivity from pod to SFTP server..."
if oc exec $POD_NAME -- bash -c "nc -zv $SFTP_HOST $SFTP_PORT -w 5" 2>/dev/null; then
    echo "✅ Pod can connect to SFTP server"
else
    echo "❌ Pod CANNOT connect to SFTP server"
    echo "This is likely a network connectivity issue. Make sure your OpenShift cluster can reach your local machine."
fi

echo ""
echo "=== Pod logs ==="
oc logs $POD_NAME

echo ""
echo "=== Checking SFTP volume on local machine ==="
VOLUME_DIR=~/sftp_test_volume
if [ -d "$VOLUME_DIR" ]; then
    echo "SFTP volume directory exists: $VOLUME_DIR"
    echo "Files in SFTP volume:"
    ls -la $VOLUME_DIR
else
    echo "SFTP volume directory not found: $VOLUME_DIR"
fi

echo ""
echo "=== Debug Summary ==="
if oc exec $POD_NAME -- test -f /app/repo/sales_report.csv 2>/dev/null; then
    echo "1. The sales_report.csv file IS generated in the pod"
else
    echo "1. The sales_report.csv file is NOT generated in the pod - Check the Python script"
fi

if ls -la $VOLUME_DIR | grep -q "sales_report.csv"; then
    echo "2. The file WAS uploaded to the SFTP server"
else
    echo "2. The file was NOT uploaded to the SFTP server"
    
    if oc exec $POD_NAME -- bash -c "nc -zv $SFTP_HOST $SFTP_PORT -w 5" 2>/dev/null; then
        echo "   - The pod CAN connect to the SFTP server"
        echo "   - The issue may be with the upload script or SFTP credentials"
    else
        echo "   - The pod CANNOT connect to the SFTP server"
        echo "   - This is a network connectivity issue between OpenShift and your local machine"
    fi
fi

echo ""
echo "Next steps:"
echo "1. If the file isn't generated, check the Python script in the GitHub repository"
echo "2. If the file is generated but not uploaded, check the SFTP credentials and path"
echo "3. If there's a network connectivity issue, make sure your OpenShift cluster can reach your local machine"
echo "   - If your OpenShift cluster is remote or in the cloud, it likely can't reach your local machine"
echo "   - Consider using an externally accessible SFTP server instead" 