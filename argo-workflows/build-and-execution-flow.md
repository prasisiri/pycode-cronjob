# Docker Build and Argo Workflow Execution Flow

This diagram illustrates how Python scripts are pulled from GitHub, packaged into a Docker image, and then executed as part of an Argo Workflow.

```mermaid
flowchart TD
    %% GitHub Repository Section
    subgraph github["GitHub Repository"]
        sales["sales_analysis.py"]
        extract["extract_data.py"]
        transform["transform_data.py"]
        analyze["analyze_data.py"]
        upload["file_upload.py"]
        notify["send_notification.py"]
    end

    %% Docker Build Process
    subgraph docker_build["Docker Build Process"]
        dockerfile["Dockerfile"]
        build_script["build.sh"]
        build_process["Docker Build"]
        image["Container Image"]
    end

    %% Argo Workflow Execution
    subgraph argo["Argo Workflow Execution"]
        workflow_def["Workflow YAML Definition"]
        
        subgraph steps["Workflow Steps"]
            step_extract["Extract Step Container"]
            step_transform["Transform Step Container"]
            step_analyze["Analysis Step Container"]
            step_upload["Upload Step Container"]
            step_notify["Notification Step Container"]
        end
        
        subgraph artifacts["Workflow Artifacts"]
            art_extract["raw_data.csv"]
            art_transform["transformed_data.csv"] 
            art_analysis["analysis_report.csv"]
        end
    end

    %% Flow from GitHub to Docker
    sales --> dockerfile
    extract --> dockerfile
    transform --> dockerfile
    analyze --> dockerfile
    upload --> dockerfile
    notify --> dockerfile

    dockerfile --> build_script
    build_script --> build_process
    build_process --> image

    %% Flow from Docker to Argo
    image --> workflow_def
    workflow_def --> step_extract
    workflow_def --> step_transform
    workflow_def --> step_analyze
    workflow_def --> step_upload
    workflow_def --> step_notify

    %% Data flow in execution
    step_extract --> art_extract
    art_extract --> step_transform
    step_transform --> art_transform
    art_transform --> step_analyze
    step_analyze --> art_analysis
    art_analysis --> step_upload
    step_upload --> step_notify

    %% Define node styles
    classDef github fill:#f5f5f5,stroke:#333,stroke-width:1px
    classDef docker fill:#2496ed,stroke:#fff,stroke-width:1px,color:#fff
    classDef argo fill:#e96d76,stroke:#fff,stroke-width:1px,color:#fff
    classDef script fill:#2e7d32,stroke:#fff,stroke-width:1px,color:#fff
    classDef artifact fill:#ffd54f,stroke:#333,stroke-width:1px
    classDef container fill:#673ab7,stroke:#fff,stroke-width:1px,color:#fff
    
    %% Apply styles to node groups
    class sales,extract,transform,analyze,upload,notify script
    class dockerfile,build_script,build_process,image docker
    class workflow_def,steps argo
    class step_extract,step_transform,step_analyze,step_upload,step_notify container
    class art_extract,art_transform,art_analysis artifact
    class github github
```

## Dynamic Script Loading Method

We can load Python scripts from GitHub in two ways:

### 1. Build-time Script Inclusion

```Dockerfile
FROM python:3.9-slim

WORKDIR /app

# Install git and dependencies
RUN apt-get update && apt-get install -y \
    git \
    && rm -rf /var/lib/apt/lists/*

# Install Python requirements
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Clone the repository to get the latest scripts
RUN git clone https://github.com/yourusername/sales-analysis.git /app/scripts

# Set the entrypoint
ENTRYPOINT ["python", "/app/scripts/main.py"]
```

### 2. Runtime Script Fetching

```Dockerfile
FROM python:3.9-slim

WORKDIR /app

# Install git and dependencies
RUN apt-get update && apt-get install -y \
    git \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Install Python requirements
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Add script to fetch latest code at runtime
COPY fetch_scripts.sh /app/
RUN chmod +x /app/fetch_scripts.sh

# This script will fetch the latest code each time the container starts
ENTRYPOINT ["/app/fetch_scripts.sh"]
```

Where `fetch_scripts.sh` contains:

```bash
#!/bin/bash
# Fetch the latest scripts from GitHub
git clone https://github.com/yourusername/sales-analysis.git /app/scripts
# Execute the specified Python script with arguments
python /app/scripts/$1.py "${@:2}"
```

## Argo Workflow YAML Example

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Workflow
metadata:
  name: sales-analysis-workflow
spec:
  entrypoint: sales-analysis
  templates:
  - name: sales-analysis
    dag:
      tasks:
      - name: extract
        template: extract-data
      - name: transform
        template: transform-data
        dependencies: [extract]
      - name: analyze
        template: analyze-data
        dependencies: [transform]
      - name: upload
        template: upload-data
        dependencies: [analyze]
      - name: notify
        template: send-notification
        dependencies: [upload]
        
  - name: extract-data
    container:
      image: sales-analysis:latest
      args: ["extract_data", "--source", "database", "--output", "/tmp/raw_data.csv"]
    outputs:
      artifacts:
      - name: raw-data
        path: /tmp/raw_data.csv
        
  - name: transform-data
    inputs:
      artifacts:
      - name: raw-data
        path: /tmp/raw_data.csv
    container:
      image: sales-analysis:latest
      args: ["transform_data", "--input", "/tmp/raw_data.csv", "--output", "/tmp/transformed_data.csv"]
    outputs:
      artifacts:
      - name: transformed-data
        path: /tmp/transformed_data.csv
        
  # Additional templates for analyze, upload, and notify steps
``` 