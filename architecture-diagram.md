# Sales Analysis CronJob Architecture

## System Architecture with Argo Workflows

```mermaid
graph TD
    subgraph "OpenShift Cluster"
        AW[Argo Workflows Controller]
        CW[CronWorkflow: sales-analysis-cron]
        SA[ServiceAccount: workflow]
        S[Secret: upload-config]
        PVC[PVC: workdir]
    end
    
    subgraph "Workflow Execution"
        CW --> |schedules| WF[Workflow Instance]
        WF --> |uses| SA
        WF --> |mounts| PVC
        WF --> |accesses| S
        AW --> |manages| WF
    end
    
    subgraph "Data Lifecycle"
        %% Extraction Jobs (parallel)
        WF --> ES[Extract Sales Data]
        WF --> EC[Extract Customer Data]
        WF --> EP[Extract Product Data]
        
        %% Generated Raw Data
        ES --> |generates| SalesCSV[raw_sales.csv]
        EC --> |generates| CustCSV[customer_data.csv]
        EP --> |generates| ProdCSV[product_data.csv]
        
        %% Transform Job (depends on all extractions)
        SalesCSV --> TD[Transform Data]
        CustCSV --> TD
        ProdCSV --> TD
        TD --> |generates| TransformedCSV[transformed_data.csv]
        
        %% Analysis Jobs (parallel, depend on transform)
        TransformedCSV --> AS[Sales Analysis]
        TransformedCSV --> AC[Customer Analysis]
        TransformedCSV --> AP[Product Analysis]
        
        %% Analysis Reports
        AS --> |generates| SalesReport[sales_report.csv]
        AC --> |generates| CustReport[customer_report.csv]
        AP --> |generates| ProdReport[product_report.csv]
        
        %% Upload Jobs (depend on respective analysis)
        SalesReport --> US[Upload Sales Report]
        CustReport --> UC[Upload Customer Report]
        ProdReport --> UP[Upload Product Report]
        
        %% Final Notification (depends on all uploads)
        US --> N[Notification]
        UC --> N
        UP --> N
    end
    
    %% External Integration
    subgraph "External Destinations"
        SFTP[SFTP Server]
        S3[S3 Storage]
        HTTP[HTTP Endpoint]
        EMAIL[Email Notification]
    end
    
    US --> |uploads to| SFTP
    UC --> |uploads to| SFTP
    UP --> |uploads to| SFTP
    N --> |sends email to| EMAIL
    
    classDef cluster fill:#326ce5,stroke:#fff,stroke-width:1px,color:#fff
    classDef workflow fill:#1a73e8,stroke:#fff,stroke-width:1px,color:#fff
    classDef extract fill:#34a853,stroke:#fff,stroke-width:1px,color:#fff
    classDef transform fill:#4285f4,stroke:#fff,stroke-width:1px,color:#fff
    classDef analyze fill:#fbbc05,stroke:#fff,stroke-width:1px,color:#fff
    classDef upload fill:#ea4335,stroke:#fff,stroke-width:1px,color:#fff
    classDef notify fill:#7839d4,stroke:#fff,stroke-width:1px,color:#fff
    classDef data fill:#cccccc,stroke:#000,stroke-width:1px,color:#000
    classDef external fill:#0f9d58,stroke:#fff,stroke-width:1px,color:#fff
    
    class AW,CW,SA,S,PVC cluster
    class WF workflow
    class ES,EC,EP extract
    class TD transform
    class AS,AC,AP analyze
    class US,UC,UP upload
    class N notify
    class SalesCSV,CustCSV,ProdCSV,TransformedCSV,SalesReport,CustReport,ProdReport data
    class SFTP,S3,HTTP,EMAIL external
```

## Workflow Execution Sequence

```mermaid
sequenceDiagram
    participant Scheduler as OpenShift Scheduler
    participant CronJob as CronWorkflow
    participant Workflow as Workflow Instance
    participant Extract as Extract Jobs
    participant Transform as Transform Job
    participant Analyze as Analysis Jobs
    participant Upload as Upload Jobs
    participant SFTP as SFTP Server
    participant Notify as Notification
    
    Note over Scheduler,Notify: Daily Scheduled Execution
    
    Scheduler->>CronJob: Trigger at scheduled time (daily at midnight)
    CronJob->>Workflow: Create workflow instance
    
    Note over Workflow,SFTP: Parallel Data Extraction
    
    par Parallel Extraction
        Workflow->>Extract: Extract Sales Data
        Extract-->>Workflow: raw_sales.csv
        
        Workflow->>Extract: Extract Customer Data
        Extract-->>Workflow: customer_data.csv
        
        Workflow->>Extract: Extract Product Data
        Extract-->>Workflow: product_data.csv
    end
    
    Note over Workflow,SFTP: Data Transformation (Dependent on All Extractions)
    
    Workflow->>Transform: Transform and Merge Data
    Transform-->>Workflow: transformed_data.csv
    
    Note over Workflow,SFTP: Parallel Analysis (All Dependent on Transform)
    
    par Parallel Analysis
        Workflow->>Analyze: Sales Analysis
        Analyze-->>Workflow: sales_report.csv
        
        Workflow->>Analyze: Customer Analysis
        Analyze-->>Workflow: customer_report.csv
        
        Workflow->>Analyze: Product Analysis
        Analyze-->>Workflow: product_report.csv
    end
    
    Note over Workflow,SFTP: Upload Reports
    
    par Parallel Upload
        Workflow->>Upload: Upload Sales Report
        Upload->>SFTP: Push sales_report.csv
        SFTP-->>Upload: Upload Success
        
        Workflow->>Upload: Upload Customer Report
        Upload->>SFTP: Push customer_report.csv
        SFTP-->>Upload: Upload Success
        
        Workflow->>Upload: Upload Product Report
        Upload->>SFTP: Push product_report.csv
        SFTP-->>Upload: Upload Success
    end
    
    Note over Workflow,SFTP: Notification (If Email Provided)
    
    Workflow->>Notify: Send Completion Notification
    Notify-->>Workflow: Notification Sent
    Workflow-->>CronJob: Workflow Completed
```

## Job Dependencies Graph

```mermaid
flowchart TD
    subgraph "DAG Task Dependencies"
        direction LR
        extract_sales(Extract Sales Data)
        extract_customers(Extract Customer Data)
        extract_products(Extract Product Data)
        
        transform(Transform Data)
        
        analyze_sales(Sales Analysis)
        analyze_customers(Customer Analysis)
        analyze_products(Product Analysis)
        
        upload_sales(Upload Sales Report)
        upload_customers(Upload Customer Report)
        upload_products(Upload Product Report)
        
        notification(Send Notification)
        
        %% Dependency connections
        extract_sales --> transform
        extract_customers --> transform
        extract_products --> transform
        
        transform --> analyze_sales
        transform --> analyze_customers
        transform --> analyze_products
        
        analyze_sales --> upload_sales
        analyze_customers --> upload_customers
        analyze_products --> upload_products
        
        upload_sales --> notification
        upload_customers --> notification
        upload_products --> notification
    end
    
    classDef extract fill:#34a853,stroke:#fff,stroke-width:1px,color:#fff
    classDef transform fill:#4285f4,stroke:#fff,stroke-width:1px,color:#fff
    classDef analyze fill:#fbbc05,stroke:#fff,stroke-width:1px,color:#fff
    classDef upload fill:#ea4335,stroke:#fff,stroke-width:1px,color:#fff
    classDef notify fill:#7839d4,stroke:#fff,stroke-width:1px,color:#fff
    
    class extract_sales,extract_customers,extract_products extract
    class transform transform
    class analyze_sales,analyze_customers,analyze_products analyze
    class upload_sales,upload_customers,upload_products upload
    class notification notify
```

## Process Sequence

```mermaid
sequenceDiagram
    participant OS as OpenShift Scheduler
    participant CJ as CronJob
    participant Pod as Sales Analysis Pod
    participant GH as GitHub
    participant SFTP as SFTP Server
    participant Vol as Local Volume
    
    Note over OS,Vol: Scheduled Execution
    OS->>CJ: Trigger according to schedule
    CJ->>Pod: Create new pod
    
    Note over Pod,Vol: File Generation
    Pod->>GH: Clone repository
    GH-->>Pod: Return sales_analysis.py
    Pod->>Pod: Execute Python script
    Pod->>Pod: Generate sales_report.csv
    
    Note over Pod,Vol: File Upload
    Pod->>SFTP: Connect via SFTP
    SFTP-->>Pod: Authentication successful
    Pod->>SFTP: Upload sales_report.csv
    SFTP->>Vol: Save file to ~/sftp_test_volume
    SFTP-->>Pod: Upload complete
    Pod->>OS: Job complete
```

## Network Connectivity

```mermaid
graph LR
    subgraph "OpenShift Cluster"
        POD[Pod]
    end
    
    subgraph "Host Machine"
        SFTP[SFTP Server]
        VOLUME[~/sftp_test_volume]
    end
    
    POD -->|Connect to HOST_IP:2222| SFTP
    SFTP -->|Save files to| VOLUME
    
    classDef openshift fill:#326ce5,stroke:#fff,stroke-width:1px,color:#fff
    classDef local fill:#34a853,stroke:#fff,stroke-width:1px,color:#fff
    
    class POD openshift
    class SFTP,VOLUME local
```

## Troubleshooting Process

```mermaid
flowchart TD
    A[Start] --> B{Is CronJob running?}
    B -->|Yes| C{Is sales_report.csv generated?}
    B -->|No| B1[Check CronJob logs and events]
    
    C -->|Yes| D{Can OpenShift pod reach SFTP server?}
    C -->|No| C1[Check Python script execution]
    
    D -->|Yes| E{Are SFTP credentials correct?}
    D -->|No| D1[Network connectivity issue]
    
    E -->|Yes| F{Is remote path writable?}
    E -->|No| E1[Update SFTP credentials in Secret]
    
    F -->|Yes| G[Check local volume permissions]
    F -->|No| F1[Fix remote path permissions]
    
    D1 --> H[Run fix-openshift-sftp.sh]
    E1 --> H
    F1 --> H
    G --> H
    
    H --> I[Test with debug-openshift-job.sh]
    
    classDef start fill:#4285f4,stroke:#fff,stroke-width:1px,color:#fff
    classDef process fill:#34a853,stroke:#fff,stroke-width:1px,color:#fff
    classDef issue fill:#ea4335,stroke:#fff,stroke-width:1px,color:#fff
    classDef solution fill:#fbbc05,stroke:#fff,stroke-width:1px,color:#fff
    
    class A start
    class B,C,D,E,F process
    class B1,C1,D1,E1,F1,G issue
    class H,I solution
``` 