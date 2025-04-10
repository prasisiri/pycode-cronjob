#!/bin/bash

# Login to OpenShift
# oc login <cluster-url> -u <username> -p <password>
# Alternatively, you can get a token from the OpenShift web console and use:
# oc login --token=<token> --server=<cluster-url>

# Select or create the project
PROJECT_NAME="sales-analysis"
oc get project $PROJECT_NAME > /dev/null 2>&1
if [ $? -ne 0 ]; then
  echo "Creating project $PROJECT_NAME"
  oc new-project $PROJECT_NAME
else
  echo "Using existing project $PROJECT_NAME"
  oc project $PROJECT_NAME
fi

# Build and push the image using OpenShift's built-in container registry
REGISTRY=$(oc get route default-route -n openshift-image-registry --template='{{ .spec.host }}')
IMAGE_NAME="sales-analysis"
TAG="latest"

# If using OpenShift's internal registry
if [ ! -z "$REGISTRY" ]; then
  echo "Using OpenShift registry: $REGISTRY"
  
  # Login to the registry
  docker login -u $(oc whoami) -p $(oc whoami -t) $REGISTRY
  
  # Build and push
  docker build -t $REGISTRY/$PROJECT_NAME/$IMAGE_NAME:$TAG .
  docker push $REGISTRY/$PROJECT_NAME/$IMAGE_NAME:$TAG
  
  # Update the CronJob YAML with the internal registry image
  sed -i "s|image:.*|image: $REGISTRY/$PROJECT_NAME/$IMAGE_NAME:$TAG|" sales-analysis-cronjob.yaml
else
  echo "Unable to determine OpenShift registry. Make sure you're logged in and the registry is exposed."
  echo "Continuing with the existing image reference in the YAML file."
fi

# Apply the CronJob
oc apply -f sales-analysis-cronjob.yaml

echo "CronJob deployed to OpenShift project $PROJECT_NAME"
echo "To verify, run: oc get cronjobs" 