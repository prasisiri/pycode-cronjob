FROM python:3.9-slim

RUN apt-get update && apt-get install -y git

WORKDIR /app

# Install required Python libraries for all scripts
RUN pip install pandas paramiko boto3 requests matplotlib numpy

# Clone the repository to get the latest version of all scripts
RUN git clone https://github.com/prasisiri/python-rules.git /app/repo

# Create a wrapper script that can run any script and upload results
RUN echo '#!/bin/bash\n\
cd /app/repo\n\
\n\
# Default script to run if not specified\n\
SCRIPT_TO_RUN=${SCRIPT_NAME:-sales_analysis.py}\n\
OUTPUT_FILE=${OUTPUT_FILE:-sales_report.csv}\n\
UPLOAD_METHOD=${UPLOAD_METHOD:-sftp}\n\
\n\
echo "Running script: $SCRIPT_TO_RUN"\n\
python $SCRIPT_TO_RUN\n\
\n\
if [ -f "$OUTPUT_FILE" ]; then\n\
  echo "Uploading $OUTPUT_FILE to file server via $UPLOAD_METHOD..."\n\
  # Clone the file upload script if it doesn't exist in the repo\n\
  if [ ! -f "file-upload.py" ]; then\n\
    echo "Using built-in file upload script"\n\
    python /app/repo/file-upload.py --file $OUTPUT_FILE --config /app/repo/upload-config.ini --method $UPLOAD_METHOD\n\
  else\n\
    echo "Using repository file upload script"\n\
    python file-upload.py --file $OUTPUT_FILE --config upload-config.ini --method $UPLOAD_METHOD\n\
  fi\n\
  \n\
  exit_code=$?\n\
  if [ $exit_code -ne 0 ]; then\n\
    echo "File upload failed with exit code $exit_code"\n\
  else\n\
    echo "File upload completed successfully"\n\
  fi\n\
else\n\
  echo "File $OUTPUT_FILE not found"\n\
fi' > /app/run.sh && chmod +x /app/run.sh

# Set the working directory to where the scripts are located
WORKDIR /app/repo

# Create a default upload config if one doesn't exist in the repo
RUN echo '[sftp]\n\
host = localhost\n\
port = 2222\n\
username = sftpuser\n\
password = password\n\
remote_path = /upload\n\
\n\
[s3]\n\
endpoint_url = https://s3.amazonaws.com\n\
s3_access_key = YOUR_ACCESS_KEY\n\
s3_secret_key = YOUR_SECRET_KEY\n\
bucket = sales-reports\n\
region = us-east-1\n\
\n\
[http]\n\
url = https://api.example.com/upload\n\
method = POST\n\
username = user\n\
password = password' > /app/repo/upload-config.ini.default && \
if [ ! -f "/app/repo/upload-config.ini" ]; then cp /app/repo/upload-config.ini.default /app/repo/upload-config.ini; fi

# Pull latest changes when container starts
ENTRYPOINT ["sh", "-c", "cd /app/repo && git pull && /app/run.sh"]

# Set permissions for OpenShift arbitrary user ID
RUN chmod -R 755 /app && \
    chgrp -R 0 /app && \
    chmod -R g=u /app

# Run as a non-root user for security
USER 1001 