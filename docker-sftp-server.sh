#!/bin/bash

# Create a directory for SFTP uploads
mkdir -p ~/sftp_test_volume

# Set a username and password for the SFTP server
USERNAME="sftpuser"
PASSWORD="password"  # Change this to a secure password

echo "Starting Docker SFTP server..."

# Run the SFTP server container
docker run -d \
  --name sftp-server \
  -p 2222:22 \
  -v ~/sftp_test_volume:/home/$USERNAME/upload \
  -e SFTP_USERS="$USERNAME:$PASSWORD:1001" \
  atmoz/sftp

# Check if the container started successfully
if [ $? -eq 0 ]; then
  echo ""
  echo "===== DOCKER SFTP SERVER INFORMATION ====="
  echo "SFTP Server is running on: localhost"
  echo "Port: 2222"
  echo "Username: $USERNAME"
  echo "Password: $PASSWORD"
  echo "Upload directory on host: $HOME/sftp_test_volume"
  echo ""
  echo "Update your upload-config.ini with:"
  echo "[sftp]"
  echo "host = localhost"
  echo "port = 2222"
  echo "username = $USERNAME"
  echo "password = $PASSWORD"
  echo "remote_path = /upload"
  echo ""
  echo "To test the SFTP connection, try: sftp -P 2222 $USERNAME@localhost"
  echo "To stop the server: docker stop sftp-server"
  echo "To start again after stopping: docker start sftp-server"
  echo "To remove the server: docker rm -f sftp-server"
  echo "============================================="
else
  echo "Failed to start SFTP server container. Make sure Docker is running."
fi 