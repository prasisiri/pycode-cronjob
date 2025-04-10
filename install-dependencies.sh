#!/bin/bash

echo "Installing Python dependencies for SFTP file upload..."

# Check which Python is available
if command -v python3 &> /dev/null; then
    PYTHON_CMD="python3"
    PIP_CMD="pip3"
elif command -v python &> /dev/null; then
    PYTHON_CMD="python"
    PIP_CMD="pip"
else
    echo "Error: Python is not installed. Please install Python 3.x first."
    exit 1
fi

echo "Using Python: $($PYTHON_CMD --version)"

# Install pip if not available
if ! command -v $PIP_CMD &> /dev/null; then
    echo "Installing pip..."
    curl https://bootstrap.pypa.io/get-pip.py -o get-pip.py
    $PYTHON_CMD get-pip.py --user
    rm get-pip.py
fi

echo "Installing required packages..."

# Install required packages
$PIP_CMD install --user paramiko boto3 requests

# Check if installation was successful
if [ $? -eq 0 ]; then
    echo ""
    echo "==================================="
    echo "Dependencies installed successfully!"
    echo "You can now run the upload script with:"
    echo "./test-local-upload.sh"
    echo "==================================="
else
    echo ""
    echo "ERROR: Failed to install dependencies."
    echo "Try installing them manually with:"
    echo "$PIP_CMD install --user paramiko boto3 requests"
    exit 1
fi 