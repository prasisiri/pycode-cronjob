# Sales Analysis CronJob

This project sets up a Kubernetes CronJob that runs a Python script from GitHub for sales analysis.

## Overview

The CronJob pulls a Docker image that contains the Python script from [GitHub](https://github.com/prasisiri/python-rules/blob/main/sales_analysis.py). The script is pulled during the image build process, ensuring you always have the latest version.

The generated report file (`sales_report.csv`) can be automatically uploaded to a file server using SFTP, S3, or HTTP.

## Setup for Kubernetes

### 1. Build the Docker image

Edit `build.sh` to set your Docker registry information:

```bash
REGISTRY="your-registry"  # e.g., docker.io/username
IMAGE_NAME="sales-analysis"
TAG="latest"
```

Make the script executable and run it:

```bash
chmod +x build.sh
./build.sh
```

### 2. Configure File Upload

Edit the `upload-config.ini` file to set your file server credentials:

```ini
[sftp]
host = your-file-server.com
username = your-username
password = your-password
remote_path = /path/to/upload/directory
```

Create a Kubernetes Secret with the configuration:

```bash
chmod +x create-upload-secret.sh
./create-upload-secret.sh
```

### 3. Configure the CronJob

Edit `sales-analysis-cronjob.yaml` to set your image reference:

```yaml
image: your-registry/sales-analysis:latest
```

Choose your preferred upload method by changing the environment variable:
```yaml
env:
- name: UPLOAD_METHOD
  value: "sftp"  # Options: sftp, s3, http
```

Also modify the schedule as needed. The default is set to run once a day at midnight (`0 0 * * *`).

### 4. Deploy the CronJob

Apply the CronJob to your Kubernetes cluster:

```bash
kubectl apply -f sales-analysis-cronjob.yaml
```

### 5. Monitor the CronJob

Check the status of your CronJob:

```bash
kubectl get cronjobs
kubectl get jobs
kubectl get pods
```

View logs from a specific job run:

```bash
kubectl logs job/sales-analysis-cronjob-<timestamp>
```

## Setup for OpenShift

This project has been configured to run on OpenShift with the necessary security settings.

### 1. Login to OpenShift

Make sure you have the OpenShift CLI (`oc`) installed and log in to your cluster:

```bash
oc login <cluster-url> -u <username> -p <password>
```

Or use a token:

```bash
oc login --token=<token> --server=<cluster-url>
```

### 2. Configure File Upload

Edit the `upload-config.ini` file and create the Secret:

```bash
chmod +x create-upload-secret.sh
./create-upload-secret.sh
```

### 3. Deploy using the script

We've provided a script that will:
- Create a project (if it doesn't exist)
- Build and push the image to OpenShift's internal registry
- Deploy the CronJob

Simply run:

```bash
chmod +x deploy-to-openshift.sh
./deploy-to-openshift.sh
```

### 4. Monitor in OpenShift

You can monitor the CronJob using the OpenShift Web Console or CLI:

```bash
oc get cronjobs
oc get jobs
oc get pods
```

View logs from a specific job run:

```bash
oc logs job/sales-analysis-cronjob-<timestamp>
```

## Customizing the Schedule

The default schedule is set to run once a day at midnight. You can customize this in the `sales-analysis-cronjob.yaml` file by changing the `schedule` field. OpenShift uses the standard cron format:

- `0 0 * * *` - Run at midnight every day
- `0 */6 * * *` - Run every 6 hours
- `0 0 * * 0` - Run at midnight every Sunday

## Supported File Upload Methods

The solution supports three methods for uploading the generated report:

1. **SFTP**: Secure File Transfer Protocol
   - Set `UPLOAD_METHOD=sftp` in the CronJob
   - Configure the [sftp] section in upload-config.ini

2. **S3**: Amazon S3 or S3-compatible storage
   - Set `UPLOAD_METHOD=s3` in the CronJob
   - Configure the [s3] section in upload-config.ini
   - Works with AWS S3, MinIO, and other S3-compatible storage

3. **HTTP**: Upload to a web server via HTTP POST or PUT
   - Set `UPLOAD_METHOD=http` in the CronJob
   - Configure the [http] section in upload-config.ini
   - Supports basic auth and token-based authentication 