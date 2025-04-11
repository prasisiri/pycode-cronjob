# Argo Workflows Architecture Diagram

The following diagram illustrates the typical workflow architecture for the sales analysis project using Argo Workflows.

```mermaid
graph TD
    %% Define the main workflow steps
    subgraph "Data Extraction Phase" 
        A[Extract Sales Data] --> |raw_sales.csv| D
        B[Extract Customer Data] --> |customer_data.csv| D
        C[Extract Product Data] --> |product_data.csv| D
    end
    
    subgraph "Data Processing Phase"
        D[Transform & Merge Data] --> |transformed_data.csv| E
        D --> |transformed_data.csv| F
        D --> |transformed_data.csv| G
    end
    
    subgraph "Analysis Phase"
        E[Sales Analysis] --> |sales_report.csv| H
        F[Customer Analysis] --> |customer_report.csv| I
        G[Product Analysis] --> |product_report.csv| J
    end
    
    subgraph "Upload Phase"
        H --> K[Upload to SFTP]
        I --> K
        J --> K
        
        H --> L[Upload to S3]
        I --> L
        J --> L
        
        H --> M[Upload to HTTP Endpoint]
        I --> M
        J --> M
    end
    
    subgraph "Notification Phase"
        K --> N[Send Email Notification]
        L --> N
        M --> N
        N --> O[Mark Workflow Complete]
    end
    
    %% Define node styles by phase
    classDef extraction fill:#34a853,stroke:#fff,stroke-width:1px,color:#fff,rounded
    classDef processing fill:#4285f4,stroke:#fff,stroke-width:1px,color:#fff,rounded
    classDef analysis fill:#fbbc05,stroke:#fff,stroke-width:1px,color:#fff,rounded
    classDef upload fill:#ea4335,stroke:#fff,stroke-width:1px,color:#fff,rounded
    classDef notification fill:#7839d4,stroke:#fff,stroke-width:1px,color:#fff,rounded
    
    %% Apply styles
    class A,B,C extraction
    class D processing
    class E,F,G analysis
    class H,I,J,K,L,M upload
    class N,O notification
```

## Key Features Highlighted

1. **Parallel Execution**: Extract jobs and analysis jobs run in parallel
2. **Dependencies**: Transform job depends on all extract jobs
3. **Data Flow**: Shows how data moves between workflow steps
4. **Multiple Upload Options**: SFTP, S3, and HTTP endpoints
5. **Notifications**: Final completion notification

## Implementation Details

Each box represents a container running a Python script that performs a specific function:

- **Extract Steps**: Pull data from various sources
- **Transform Step**: Clean, merge, and prepare data for analysis
- **Analysis Steps**: Perform business logic on prepared data
- **Upload Steps**: Transfer results to different storage systems
- **Notification Step**: Alert users when the workflow completes

The workflow definition in Argo allows these steps to be managed as a single entity, with automatic retry logic, dependency tracking, and artifact passing between steps. 