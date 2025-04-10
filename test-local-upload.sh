#!/bin/bash

# Create a test file
echo "Creating a test file..."
TEST_FILE="test_file.csv"
echo "id,name,value" > $TEST_FILE
echo "1,Test Item 1,100" >> $TEST_FILE
echo "2,Test Item 2,200" >> $TEST_FILE
echo "3,Test Item 3,300" >> $TEST_FILE

echo "Test file created: $TEST_FILE"

# Determine which SFTP server to use
echo "Which SFTP server do you want to use?"
echo "1) macOS built-in SSH/SFTP server"
echo "2) Docker SFTP server"
read -p "Choose option (1 or 2): " CHOICE

# Create a temporary config file for testing
CONFIG_FILE="test_upload_config.ini"

if [ "$CHOICE" == "1" ]; then
    # Use macOS built-in SFTP
    LOCAL_USER=$(whoami)
    LOCAL_IP=$(ipconfig getifaddr en0 || ipconfig getifaddr en1)
    LOCAL_IP=${LOCAL_IP:-"127.0.0.1"}
    
    read -p "Enter your macOS user password: " USER_PASSWORD
    
    # Create test config
    cat > $CONFIG_FILE << EOL
[sftp]
host = $LOCAL_IP
port = 22
username = $LOCAL_USER
password = $USER_PASSWORD
remote_path = $HOME/sftp_test_dir
EOL

elif [ "$CHOICE" == "2" ]; then
    # Use Docker SFTP
    # Create test config
    cat > $CONFIG_FILE << EOL
[sftp]
host = localhost
port = 2222
username = sftpuser
password = password
remote_path = /upload
EOL

else
    echo "Invalid choice. Exiting."
    exit 1
fi

echo "Created temporary config file: $CONFIG_FILE"

# Check which Python is available
PYTHON_CMD="python3"
if ! command -v $PYTHON_CMD &> /dev/null; then
    PYTHON_CMD="python"
    if ! command -v $PYTHON_CMD &> /dev/null; then
        echo "Error: Neither python3 nor python is available. Please install Python."
        exit 1
    fi
fi

echo "Using Python command: $PYTHON_CMD"

# Test upload using our Python script
echo "Testing upload to SFTP server..."
$PYTHON_CMD file-upload.py --file $TEST_FILE --config $CONFIG_FILE --method sftp

# Check if upload was successful
if [ $? -eq 0 ]; then
    echo "Upload successful!"
    echo "You can check the uploaded file in the destination directory."
else
    echo "Upload failed. Check the error message above."
fi

# Ask if the temp config should be kept
read -p "Do you want to keep the temporary config file? (y/n): " KEEP_CONFIG
if [ "$KEEP_CONFIG" != "y" ]; then
    rm $CONFIG_FILE
    echo "Temporary config file removed."
fi 