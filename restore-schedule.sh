#!/bin/bash

# Check if we're using OpenShift or regular Kubernetes
if command -v oc &> /dev/null; then
  CMD="oc"
  echo "Using OpenShift CLI (oc)"
else
  CMD="kubectl"
  echo "Using Kubernetes CLI (kubectl)"
fi

# Update the schedule back to daily at midnight
echo "Restoring original schedule (daily at midnight)..."
sed -i 's|schedule: "\* \* \* \* \*".*|schedule: "0 0 * * *"  # Run once a day at midnight|' sales-analysis-cronjob.yaml

# Apply the updated CronJob
$CMD apply -f sales-analysis-cronjob.yaml

echo "Schedule restored. The CronJob will now run once a day at midnight."
echo "Current CronJob status:"
$CMD get cronjobs 