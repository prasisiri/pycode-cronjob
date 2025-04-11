# Repository-Based Python Scripts in Kubernetes/Argo

This project has been enhanced to pull all Python scripts directly from the GitHub repository at https://github.com/prasisiri/python-rules during container startup. This approach provides several key benefits:

1. **Dynamic script updates**: Any changes to scripts in the repository will be automatically picked up on the next run
2. **Centralized script management**: All scripts are maintained in a single repository
3. **Version control**: Scripts are versioned with Git, allowing for rollbacks if needed
4. **Code reuse**: Scripts can reference other scripts/modules in the repository

## How It Works

The system is designed to work with both Kubernetes CronJobs and Argo Workflows:

### Docker Container Design

The Docker container automatically:

1. Clones the GitHub repository at startup
2. Pulls the latest changes from the repository 
3. Runs the specified Python script
4. Uploads any output files to a configured destination (SFTP, S3, HTTP)

### Environment Variables

The container behavior can be controlled with these environment variables:

| Variable | Description | Default Value |
|----------|-------------|---------------|
| `SCRIPT_NAME` | Name of the Python script to run | `sales_analysis.py` |
| `OUTPUT_FILE` | Name of the output file to generate | `sales_report.csv` |
| `UPLOAD_METHOD` | Upload method to use | `sftp` |
| `INPUT_FILE` | Input file path (if needed) | - |
| `SALES_FILE` | Sales data file (if needed) | - |
| `CUSTOMERS_FILE` | Customer data file (if needed) | - |
| `PRODUCTS_FILE` | Product data file (if needed) | - |
| `RUN_DATE` | Date parameter (if needed) | - |

### Required Scripts in Repository

For the full workflow, the repository should contain these scripts:

1. **Data Extraction Scripts**:
   - `extract_sales.py`: Extracts sales data
   - `extract_customers.py`: Extracts customer data 
   - `extract_products.py`: Extracts product data

2. **Data Transformation Script**:
   - `transform_data.py`: Transforms and merges data

3. **Analysis Scripts**:
   - `sales_analysis.py`: Analyzes sales data
   - `customer_analysis.py`: Analyzes customer data
   - `product_analysis.py`: Analyzes product data

4. **File Upload Script** (optional):
   - `file-upload.py`: Uploads files to external destinations

## Kubernetes CronJob Usage

To run a script as a Kubernetes CronJob:

```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: sales-analysis-cronjob
spec:
  schedule: "0 0 * * *"
  jobTemplate:
    spec:
      template:
        spec:
          containers:
          - name: sales-analysis
            image: prasisiri/sales-analysis:latest
            env:
            - name: SCRIPT_NAME
              value: "sales_analysis.py"
            - name: OUTPUT_FILE
              value: "sales_report.csv"
            - name: UPLOAD_METHOD
              value: "sftp"
          restartPolicy: OnFailure
```

## Argo Workflow Usage

For Argo Workflows, you can run different scripts in a sequence with dependencies:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Workflow
metadata:
  generateName: data-analysis-
spec:
  entrypoint: main
  templates:
  - name: main
    dag:
      tasks:
      - name: extract-data
        template: run-script
        arguments:
          parameters:
          - name: script-name
            value: "extract_sales.py"
          - name: output-file
            value: "/mnt/workdir/raw_sales.csv"
      
      - name: transform-data
        template: run-script
        dependencies: [extract-data]
        arguments:
          parameters:
          - name: script-name
            value: "transform_data.py"
          - name: output-file
            value: "/mnt/workdir/transformed_data.csv"
  
  - name: run-script
    inputs:
      parameters:
      - name: script-name
      - name: output-file
    container:
      image: prasisiri/sales-analysis:latest
      env:
      - name: SCRIPT_NAME
        value: "{{inputs.parameters.script-name}}"
      - name: OUTPUT_FILE
        value: "{{inputs.parameters.output-file}}"
```

## Script Development Guidelines

When developing scripts for this system:

1. Use environment variables for configuration when possible
2. Write output files to the path specified in the `OUTPUT_FILE` environment variable
3. Read input files from the paths specified in the appropriate environment variables
4. Use relative imports for shared code within the repository
5. Return a non-zero exit code in case of errors

## Local Testing

You can test scripts locally with:

```bash
# Clone the repository
git clone https://github.com/prasisiri/python-rules.git
cd python-rules

# Run a script directly
python sales_analysis.py

# Or simulate the container environment
SCRIPT_NAME=sales_analysis.py OUTPUT_FILE=sales_report.csv python sales_analysis.py
``` 