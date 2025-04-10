#!/bin/bash

# Check if the Docker SFTP container is running
CONTAINER_RUNNING=$(docker ps | grep sftp-server)
if [ -z "$CONTAINER_RUNNING" ]; then
    echo "SFTP server container is not running. Starting it now..."
    ./docker-sftp-server.sh
else
    echo "SFTP server container is already running."
fi

# Create a test file
echo "Creating a test file..."
TEST_FILE="test_file.csv"
echo "id,name,value" > $TEST_FILE
echo "1,Test Item 1,100" >> $TEST_FILE
echo "2,Test Item 2,200" >> $TEST_FILE
echo "3,Test Item 3,300" >> $TEST_FILE

echo "Test file created: $TEST_FILE"

# Create a temporary config file
CONFIG_FILE="docker_sftp_config.ini"
cat > $CONFIG_FILE << EOL
[sftp]
host = localhost
port = 2222
username = sftpuser
password = password
remote_path = /upload
EOL

# Try to connect to the SFTP server using sftp command line tool
echo "Trying to connect to SFTP server using command line tool..."
echo "This will ask for the password. Enter: password"
sftp -P 2222 sftpuser@localhost << EOF
ls
quit
EOF

echo "Now testing with our Python upload script..."

# Determine if we need to use the virtual environment
if [ -d "venv" ]; then
    echo "Using virtual environment for Python dependencies..."
    ./run-in-venv.sh python file-upload.py --file $TEST_FILE --config $CONFIG_FILE --method sftp
else
    echo "No virtual environment found. Trying with system Python..."
    python3 file-upload.py --file $TEST_FILE --config $CONFIG_FILE --method sftp
fi

# Check the upload status
UPLOAD_STATUS=$?
if [ $UPLOAD_STATUS -eq 0 ]; then
    echo "Upload successful!"
    echo "Verifying the uploaded file in the container..."
    
    # Check if the file exists in the Docker container
    FIND_FILE=$(docker exec sftp-server ls -la /home/sftpuser/upload/ | grep $TEST_FILE)
    if [ ! -z "$FIND_FILE" ]; then
        echo "✅ File found in the container: $FIND_FILE"
        echo "✅ SFTP upload test PASSED"
    else
        echo "❌ File not found in the container"
        echo "❌ SFTP upload test FAILED"
    fi
else
    echo "❌ Upload failed with status code $UPLOAD_STATUS"
    echo "Check if the paramiko library is installed in your Python environment."
fi 