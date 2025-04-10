#!/bin/bash

# Activate the virtual environment
source venv/bin/activate

# Run the command with all arguments passed to this script
"$@"

# Deactivate the virtual environment
deactivate
