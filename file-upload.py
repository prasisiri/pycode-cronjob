#!/usr/bin/env python3

import os
import sys
import argparse
import configparser
import logging
from pathlib import Path

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger('file_upload')

def upload_via_sftp(file_path, config):
    """Upload file using SFTP"""
    try:
        import paramiko
        
        host = config.get('sftp', 'host')
        port = config.getint('sftp', 'port', fallback=22)
        username = config.get('sftp', 'username')
        password = config.get('sftp', 'password', fallback=None)
        key_path = config.get('sftp', 'key_path', fallback=None)
        remote_path = config.get('sftp', 'remote_path')
        
        logger.info(f"Uploading {file_path} to {host}:{remote_path} via SFTP")
        
        transport = paramiko.Transport((host, port))
        
        if key_path:
            private_key = paramiko.RSAKey.from_private_key_file(key_path)
            transport.connect(username=username, pkey=private_key)
        else:
            transport.connect(username=username, password=password)
            
        sftp = paramiko.SFTPClient.from_transport(transport)
        
        # Create remote directory if it doesn't exist
        remote_dir = os.path.dirname(remote_path)
        try:
            sftp.stat(remote_dir)
        except FileNotFoundError:
            sftp.mkdir(remote_dir)
        
        # Upload the file
        sftp.put(file_path, os.path.join(remote_path, os.path.basename(file_path)))
        
        sftp.close()
        transport.close()
        logger.info("SFTP upload completed successfully")
        return True
    except ImportError:
        logger.error("paramiko library not installed. Install with 'pip install paramiko'")
        return False
    except Exception as e:
        logger.error(f"SFTP upload failed: {str(e)}")
        return False

def upload_via_s3(file_path, config):
    """Upload file to S3 compatible storage"""
    try:
        import boto3
        from botocore.exceptions import ClientError
        
        endpoint_url = config.get('s3', 'endpoint_url', fallback=None)
        access_key = config.get('s3', 's3_access_key')
        secret_key = config.get('s3', 's3_secret_key')
        bucket = config.get('s3', 'bucket')
        region = config.get('s3', 'region', fallback='us-east-1')
        object_name = config.get('s3', 'object_name', fallback=os.path.basename(file_path))
        
        logger.info(f"Uploading {file_path} to S3 bucket {bucket}")
        
        s3_client = boto3.client(
            's3',
            endpoint_url=endpoint_url,
            aws_access_key_id=access_key,
            aws_secret_access_key=secret_key,
            region_name=region
        )
        
        try:
            s3_client.upload_file(file_path, bucket, object_name)
            logger.info(f"S3 upload completed successfully to {bucket}/{object_name}")
            return True
        except ClientError as e:
            logger.error(f"S3 upload failed: {str(e)}")
            return False
            
    except ImportError:
        logger.error("boto3 library not installed. Install with 'pip install boto3'")
        return False
    except Exception as e:
        logger.error(f"S3 upload failed: {str(e)}")
        return False

def upload_via_http(file_path, config):
    """Upload file to HTTP/REST endpoint"""
    try:
        import requests
        
        url = config.get('http', 'url')
        method = config.get('http', 'method', fallback='POST')
        username = config.get('http', 'username', fallback=None)
        password = config.get('http', 'password', fallback=None)
        token = config.get('http', 'token', fallback=None)
        
        auth = None
        headers = {}
        
        if username and password:
            auth = (username, password)
        
        if token:
            headers['Authorization'] = f'Bearer {token}'
            
        logger.info(f"Uploading {file_path} to {url} via HTTP {method}")
        
        with open(file_path, 'rb') as file:
            files = {'file': (os.path.basename(file_path), file)}
            
            if method.upper() == 'POST':
                response = requests.post(url, files=files, auth=auth, headers=headers)
            elif method.upper() == 'PUT':
                response = requests.put(url, files=files, auth=auth, headers=headers)
            else:
                logger.error(f"Unsupported HTTP method: {method}")
                return False
                
        if response.status_code in (200, 201, 202):
            logger.info(f"HTTP upload completed successfully with status code {response.status_code}")
            return True
        else:
            logger.error(f"HTTP upload failed with status code {response.status_code}: {response.text}")
            return False
            
    except ImportError:
        logger.error("requests library not installed. Install with 'pip install requests'")
        return False
    except Exception as e:
        logger.error(f"HTTP upload failed: {str(e)}")
        return False

def main():
    parser = argparse.ArgumentParser(description='Upload generated files to a file server')
    parser.add_argument('--file', '-f', required=True, help='Path to the file to upload')
    parser.add_argument('--config', '-c', required=True, help='Path to the configuration file')
    parser.add_argument('--method', '-m', choices=['sftp', 's3', 'http'], required=True, 
                        help='Upload method to use')
    
    args = parser.parse_args()
    
    file_path = args.file
    config_path = args.config
    method = args.method
    
    # Check if file exists
    if not os.path.isfile(file_path):
        logger.error(f"File not found: {file_path}")
        sys.exit(1)
        
    # Load configuration
    config = configparser.ConfigParser()
    try:
        config.read(config_path)
    except Exception as e:
        logger.error(f"Failed to read configuration file: {str(e)}")
        sys.exit(1)
        
    # Upload file using selected method
    success = False
    
    if method == 'sftp':
        success = upload_via_sftp(file_path, config)
    elif method == 's3':
        success = upload_via_s3(file_path, config)
    elif method == 'http':
        success = upload_via_http(file_path, config)
        
    if success:
        logger.info(f"File {file_path} uploaded successfully using {method}")
        sys.exit(0)
    else:
        logger.error(f"Failed to upload file {file_path} using {method}")
        sys.exit(1)

if __name__ == '__main__':
    main() 