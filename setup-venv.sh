#!/bin/bash

# Find Python 3
if command -v python3 &> /dev/null; then
    PYTHON_CMD="python3"
else
    echo "Error: Python 3 is not installed. Please install Python 3.x first."
    exit 1
fi

echo "Setting up a Python virtual environment for SFTP file upload..."

# Create a virtual environment
$PYTHON_CMD -m venv venv

# Activate the virtual environment
source venv/bin/activate

echo "Virtual environment created and activated."
echo "Using Python: $(python --version)"

# Install required packages in the virtual environment
echo "Installing required packages..."
pip install paramiko boto3 requests

# Check if installation was successful
if [ $? -eq 0 ]; then
    echo ""
    echo "==================================="
    echo "Dependencies installed successfully in virtual environment!"
    echo ""
    echo "To use this environment:"
    echo "1. Activate it with:  source venv/bin/activate"
    echo "2. Run the test:      ./test-local-upload.sh"
    echo ""
    echo "The environment is currently activated for this session."
    echo "==================================="
else
    echo ""
    echo "ERROR: Failed to install dependencies."
    echo "Try installing them manually with:"
    echo "source venv/bin/activate"
    echo "pip install paramiko boto3 requests"
    exit 1
fi

# Create a wrapper script to activate the venv
cat > run-in-venv.sh << 'EOF'
#!/bin/bash

# Activate the virtual environment
source venv/bin/activate

# Run the command with all arguments passed to this script
"$@"

# Deactivate the virtual environment
deactivate
EOF

chmod +x run-in-venv.sh

echo ""
echo "Created wrapper script: run-in-venv.sh"
echo "You can use it to run any command in the virtual environment:"
echo "./run-in-venv.sh test-local-upload.sh" 