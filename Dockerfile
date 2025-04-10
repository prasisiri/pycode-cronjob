FROM python:3.9-slim

RUN apt-get update && apt-get install -y git

WORKDIR /app

# Install required Python libraries for file upload
RUN pip install paramiko boto3 requests

# Clone the repository to get the latest version of the script
RUN git clone https://github.com/prasisiri/python-rules.git /app/repo

# Copy our file upload script and configuration
COPY file-upload.py /app/
COPY upload-config.ini /app/

# Create a wrapper script to run the Python script and then upload the file
RUN echo '#!/bin/bash\n\
cd /app/repo\n\
python sales_analysis.py\n\
if [ -f "sales_report.csv" ]; then\n\
  echo "Uploading sales_report.csv to file server..."\n\
  python /app/file-upload.py --file sales_report.csv --config /app/upload-config.ini --method ${UPLOAD_METHOD:-sftp}\n\
  exit_code=$?\n\
  if [ $exit_code -ne 0 ]; then\n\
    echo "File upload failed with exit code $exit_code"\n\
  else\n\
    echo "File upload completed successfully"\n\
  fi\n\
else\n\
  echo "File sales_report.csv not found"\n\
fi' > /app/run.sh && chmod +x /app/run.sh

# Set the working directory to where the script is located
WORKDIR /app/repo

# Set permissions for OpenShift arbitrary user ID
RUN chmod -R 755 /app && \
    chgrp -R 0 /app && \
    chmod -R g=u /app

# Run as a non-root user for security
USER 1001

# Set the entrypoint to our wrapper script
ENTRYPOINT ["/app/run.sh"] 