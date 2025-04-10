#!/bin/bash

# Check if we're using OpenShift or regular Kubernetes
if command -v oc &> /dev/null; then
  CMD="oc"
  echo "Using OpenShift CLI (oc)"
else
  CMD="kubectl"
  echo "Using Kubernetes CLI (kubectl)"
fi

# Check if the upload-config.ini file exists
if [ ! -f "upload-config.ini" ]; then
  echo "Error: upload-config.ini file not found"
  exit 1
fi

# Create a secret from the configuration file
echo "Creating upload-config secret from upload-config.ini"
$CMD create secret generic upload-config --from-file=upload-config.ini

# Check if the secret was created successfully
if [ $? -eq 0 ]; then
  echo "Secret 'upload-config' created successfully"
else
  echo "Failed to create secret 'upload-config'"
  exit 1
fi

echo "The secret is now available for use in the CronJob"
echo "You can update it later with:"
echo "$CMD create secret generic upload-config --from-file=upload-config.ini --dry-run=client -o yaml | $CMD apply -f -" 