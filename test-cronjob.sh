#!/bin/bash

# Check if we're using OpenShift or regular Kubernetes
if command -v oc &> /dev/null; then
  CMD="oc"
  echo "Using OpenShift CLI (oc)"
else
  CMD="kubectl"
  echo "Using Kubernetes CLI (kubectl)"
fi

# Apply the CronJob
echo "Deploying CronJob configured to run every minute..."
$CMD apply -f sales-analysis-cronjob.yaml

echo "Waiting for the CronJob to create a Job (this should happen within 1 minute)..."
echo "You can press Ctrl+C to stop watching when the job starts running"

# Watch the Jobs being created
$CMD get jobs --watch 