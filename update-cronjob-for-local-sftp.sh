#!/bin/bash

# Check if we're using OpenShift or regular Kubernetes
if command -v oc &> /dev/null; then
  CMD="oc"
  echo "Using OpenShift CLI (oc)"
else
  CMD="kubectl"
  echo "Using Kubernetes CLI (kubectl)"
fi

# Determine which SFTP server to use
echo "Which SFTP server are you using?"
echo "1) macOS built-in SSH/SFTP server"
echo "2) Docker SFTP server"
read -p "Choose option (1 or 2): " CHOICE

# Create a temporary config file for testing
CONFIG_FILE="local_upload_config.ini"

if [ "$CHOICE" == "1" ]; then
    # Use macOS built-in SFTP
    LOCAL_USER=$(whoami)
    LOCAL_IP=$(ipconfig getifaddr en0 || ipconfig getifaddr en1)
    LOCAL_IP=${LOCAL_IP:-"127.0.0.1"}
    
    read -p "Enter your macOS user password: " USER_PASSWORD
    
    # Create config
    cat > $CONFIG_FILE << EOL
[sftp]
host = $LOCAL_IP
port = 22
username = $LOCAL_USER
password = $USER_PASSWORD
remote_path = $HOME/sftp_test_dir

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

elif [ "$CHOICE" == "2" ]; then
    # Use Docker SFTP
    # Create config
    cat > $CONFIG_FILE << EOL
[sftp]
host = host.docker.internal
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

else
    echo "Invalid choice. Exiting."
    exit 1
fi

echo "Created config file: $CONFIG_FILE"

# Create or update the upload-config secret
echo "Creating/updating upload-config secret..."
$CMD create secret generic upload-config --from-file=upload-config.ini=$CONFIG_FILE --dry-run=client -o yaml | $CMD apply -f -

# Verify the secret was updated
if [ $? -eq 0 ]; then
    echo "Secret 'upload-config' created/updated successfully"
    
    # Set your email address to be notified when uploads happen
    read -p "Enter your email address for notifications (or leave empty for no notifications): " EMAIL
    
    if [ ! -z "$EMAIL" ]; then
        # Update the CronJob to include email notifications
        # Use sed to modify the YAML file in place
        sed -i.bak -e '/env:/a\
            - name: NOTIFICATION_EMAIL\
              value: "'"$EMAIL"'"' sales-analysis-cronjob.yaml
        
        echo "Updated CronJob with notification email"
    fi
    
    # Apply the updated CronJob
    echo "Applying updated CronJob..."
    $CMD apply -f sales-analysis-cronjob.yaml
    
    echo "Local SFTP configuration complete. Your CronJob will now upload to your local SFTP server."
    echo "To monitor logs, use: $CMD logs job/sales-analysis-cronjob-<timestamp>"
else
    echo "Failed to create/update secret 'upload-config'"
    exit 1
fi 