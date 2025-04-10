#!/bin/bash

# Create a test directory for SFTP uploads
mkdir -p ~/sftp_test_dir

echo "Setting up local SFTP server..."

# Enable Remote Login (SSH) if not already enabled
if ! sudo systemsetup -getremotelogin | grep -q "On"; then
    echo "Enabling Remote Login (SSH)..."
    sudo systemsetup -setremotelogin on
else
    echo "Remote Login is already enabled."
fi

# Display the connection information
LOCAL_USER=$(whoami)
LOCAL_IP=$(ipconfig getifaddr en0 || ipconfig getifaddr en1)
LOCAL_IP=${LOCAL_IP:-"127.0.0.1"}

echo ""
echo "===== LOCAL SFTP SERVER INFORMATION ====="
echo "SFTP Server is ready on: $LOCAL_IP"
echo "Username: $LOCAL_USER"
echo "Upload directory: $HOME/sftp_test_dir"
echo ""
echo "Update your upload-config.ini with:"
echo "[sftp]"
echo "host = $LOCAL_IP"
echo "port = 22"
echo "username = $LOCAL_USER"
echo "password = YOUR_MAC_PASSWORD"
echo "remote_path = $HOME/sftp_test_dir"
echo ""
echo "To test the SFTP connection, try: sftp $LOCAL_USER@$LOCAL_IP"
echo "=============================================" 