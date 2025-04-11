#!/bin/bash

# Configuration variables
REGISTRY="prasisiri"
IMAGE_NAME="sales-analysis"
TAG="latest"
GITHUB_REPO="https://github.com/prasisiri/python-rules.git"

echo "Building Docker image that pulls scripts from $GITHUB_REPO"

# Check if any Python scripts need to be included in the build
if [ -f "file-upload.py" ]; then
  echo "Found file-upload.py in build directory, will include in image"
  COPY_FILES="--build-arg COPY_FILE_UPLOAD=true"
else
  echo "No local scripts to include, all scripts will be pulled from GitHub"
  COPY_FILES=""
fi

# Build the Docker image
echo "Building image: $REGISTRY/$IMAGE_NAME:$TAG"
docker build $COPY_FILES -t $REGISTRY/$IMAGE_NAME:$TAG .

# Check if build was successful
if [ $? -ne 0 ]; then
  echo "Error: Docker build failed"
  exit 1
fi

# Ask if the image should be pushed
read -p "Push the image to Docker registry $REGISTRY? (y/n): " PUSH_IMAGE

if [ "$PUSH_IMAGE" = "y" ] || [ "$PUSH_IMAGE" = "Y" ]; then
  echo "Pushing image to registry..."
  docker push $REGISTRY/$IMAGE_NAME:$TAG
  
  if [ $? -ne 0 ]; then
    echo "Error: Failed to push image to registry"
    exit 1
  fi
  
  echo "Image successfully pushed: $REGISTRY/$IMAGE_NAME:$TAG"
else
  echo "Image build complete but not pushed to registry"
fi

# Update guidance
echo ""
echo "=== Next Steps ==="
echo "1. The image is configured to pull Python scripts from: $GITHUB_REPO"
echo "2. For Kubernetes CronJobs, update your environment variables:"
echo "   - SCRIPT_NAME: Name of the script to run (default: sales_analysis.py)"
echo "   - OUTPUT_FILE: Name of the output file (default: sales_report.csv)"
echo "3. For Argo Workflows, update your workflow templates to use the new parameters"
echo "   See repository-based-readme.md for detailed usage instructions"
echo ""
echo "Image reference: $REGISTRY/$IMAGE_NAME:$TAG" 