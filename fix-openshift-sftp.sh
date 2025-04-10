#!/bin/bash

echo "This script will fix common issues with SFTP uploads from OpenShift"

# Check if the Docker SFTP container is running
CONTAINER_RUNNING=$(docker ps | grep sftp-server)
if [ -z "$CONTAINER_RUNNING" ]; then
    echo "SFTP server container is not running. Starting it now..."
    ./docker-sftp-server.sh
else
    echo "SFTP server container is already running."
fi

# Fix 1: Make sure the SFTP server is using a properly routable IP address
echo "Checking your host's IP address..."
HOST_IP=$(ifconfig | grep -E "([0-9]{1,3}\.){3}[0-9]{1,3}" | grep -v 127.0.0.1 | awk '{ print $2 }' | cut -f2 -d: | head -n1)
if [ -z "$HOST_IP" ]; then
    echo "Could not determine your host IP. Please enter it manually:"
    read -p "Host IP (one that OpenShift can reach): " HOST_IP
fi

echo "Using host IP: $HOST_IP"

# Fix 2: Make sure the SFTP container is exposing port 2222 properly
echo "Checking SFTP container port configuration..."
CONTAINER_ID=$(docker ps -q -f name=sftp-server)
if [ -z "$CONTAINER_ID" ]; then
    echo "Error: SFTP server container not found."
    exit 1
fi

PORT_MAPPING=$(docker port $CONTAINER_ID)
if [[ ! $PORT_MAPPING == *"0.0.0.0:2222"* ]]; then
    echo "SFTP container needs to be reconfigured for better external access."
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
else
    echo "SFTP container port configuration looks good."
fi

# Fix 3: Create a test file to verify the SFTP server works locally
echo "Creating a test file in SFTP volume..."
TEST_FILE=~/sftp_test_volume/test_file_$(date +%s).txt
echo "This is a test file to verify SFTP is working" > $TEST_FILE
if [ -f "$TEST_FILE" ]; then
    echo "✅ Test file created successfully at: $TEST_FILE"
else
    echo "❌ Failed to create test file in SFTP volume."
    echo "Check permissions on ~/sftp_test_volume directory."
fi

# Fix 4: Update the OpenShift configuration with the proper host address
echo "Updating OpenShift configuration to use the correct IP address..."

# Check if oc is available and user is logged in
if ! command -v oc &> /dev/null; then
    echo "OpenShift CLI not found. Skipping OpenShift configuration updates."
    echo "Please update your upload-config secret manually with host=$HOST_IP"
else
    if ! oc whoami &> /dev/null; then
        echo "Not logged in to OpenShift. Skipping OpenShift configuration updates."
        echo "Please update your upload-config secret manually with host=$HOST_IP"
    else
        # Create a new config file with the updated host
        UPDATED_CONFIG="updated-upload-config.ini"
        cat > $UPDATED_CONFIG << EOL
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
        
        # Update the OpenShift secret
        echo "Updating OpenShift secret with new configuration..."
        oc create secret generic upload-config --from-file=upload-config.ini=$UPDATED_CONFIG --dry-run=client -o yaml | oc apply -f -
        
        if [ $? -eq 0 ]; then
            echo "✅ OpenShift secret updated successfully."
            rm $UPDATED_CONFIG
        else
            echo "❌ Failed to update OpenShift secret."
            echo "You may need to update it manually."
        fi
    fi
fi

# Fix 5: Verify SFTP access from the local machine
echo "Verifying SFTP access from local machine..."
echo "Connecting to SFTP server at $HOST_IP:2222..."
sftp -o "BatchMode=no" -o "StrictHostKeyChecking=no" -P 2222 sftpuser@$HOST_IP << EOF
pwd
ls -la
quit
EOF

if [ $? -eq 0 ]; then
    echo "✅ SFTP connection successful from local machine."
else
    echo "❌ SFTP connection failed from local machine."
    echo "Check if the SFTP server is running and accessible."
fi

echo ""
echo "==== SUMMARY ===="
echo "SFTP Server IP: $HOST_IP"
echo "SFTP Server Port: 2222"
echo "SFTP Username: sftpuser"
echo "SFTP Password: password"
echo "SFTP Upload Path: /upload"
echo ""
echo "If you're still having issues with uploads from OpenShift:"
echo "1. Make sure your OpenShift cluster can reach $HOST_IP:2222"
echo "   - For local clusters (Minishift, CRC), this should work"
echo "   - For remote clusters, your local machine may not be reachable"
echo ""
echo "2. Test connectivity from OpenShift to your SFTP server:"
echo "   - Run: ./debug-openshift-job.sh"
echo ""
echo "3. If connectivity is the issue, consider:"
echo "   - Setting up port forwarding on your router"
echo "   - Using a cloud-based SFTP server that both can access"
echo "   - Using a VPN to connect your local network to OpenShift" 