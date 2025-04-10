#!/bin/bash

# Replace these variables with your own values
REGISTRY="prasisiri"
IMAGE_NAME="sales-analysis"
TAG="latest"

# Build the Docker image
docker build -t $REGISTRY/$IMAGE_NAME:$TAG .

# Push the Docker image to your registry
docker push $REGISTRY/$IMAGE_NAME:$TAG

echo "Image built and pushed: $REGISTRY/$IMAGE_NAME:$TAG"
echo "Update sales-analysis-cronjob.yaml with this image reference before applying" 