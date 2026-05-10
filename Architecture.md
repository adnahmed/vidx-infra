# VIDX Infrastructure Architecture

> Cloud-native video rendering infrastructure for async media processing.

## 1. Background

I built `vidx-infra` around a simple production problem:

> Video rendering is too heavy, slow, and bursty to run inside the API request cycle.

A user-facing API should stay responsive while rendering work runs separately. The infrastructure separates:

- request handling
- file storage
- job metadata
- queue-based dispatch
- worker execution
- long-running batch compute
- status updates
- deployment and scaling

Core idea:

> The API is the control plane.  
> Workers and batch jobs are the execution plane.  
> Object storage is the source of truth for large media artifacts.

---

## 2. System Overview

```mermaid
flowchart TD
    U[Users / Browser] --> CF[CloudFront / ALB]

    CF --> FE[React Frontend]
    CF --> API[FastAPI Backend]

    API --> S3IN[S3 Input Media]
    API --> DB[(MongoDB Job Metadata)]
    API --> MQ[RabbitMQ Job Queue]
    API --> WS[WebSocket Status Updates]

    MQ --> CW[Celery Workers]
    CW --> REDIS[(Redis / ElastiCache State)]
    CW --> EXEC{Task Executor}

    EXEC --> LOCAL[Local Process Executor]
    EXEC --> BATCH[AWS Batch / Fargate]

    LOCAL --> FFMPEG[FFmpeg + GL Transitions]
    BATCH --> FFMPEG

    FFMPEG --> S3OUT[S3 Output Artifacts]
    FFMPEG --> DB
    DB --> WS
    WS --> FE

    ECR[ECR Container Images] --> API
    ECR --> CW
    ECR --> BATCH
```

At a high level, the system accepts a video job through the API, stores media in S3, records job state in MongoDB, dispatches work through RabbitMQ, processes video through workers or AWS Batch, writes outputs back to S3, and notifies the UI through real-time status updates.

---

## 3. Video Processing Flow

```mermaid
sequenceDiagram
    participant User
    participant API as FastAPI API
    participant S3 as AWS S3
    participant DB as MongoDB
    participant MQ as RabbitMQ
    participant Worker as Celery Worker
    participant Redis
    participant Batch as Local Executor / AWS Batch
    participant UI as WebSocket/UI

    User->>API: Request upload
    API->>User: Return presigned S3 URL
    User->>S3: Upload raw video
    API->>DB: Create job record: PENDING
    API->>MQ: Publish video_processing_job
    MQ->>Worker: Deliver job message
    Worker->>Redis: Store processing state
    Worker->>S3: Download input video
    Worker->>Batch: Run FFmpeg + GL Transitions
    Batch->>S3: Upload rendered output
    Worker->>DB: Update COMPLETED / FAILED
    Worker->>UI: Send job status update
```

The important design choice is that the API does not directly render video. It validates requests, creates jobs, and dispatches work. Rendering happens asynchronously in workers or batch compute.

---

## 4. Main Components

| Component | Role |
|---|---|
| React Frontend | User interface, upload flow, job status, result download |
| CloudFront / ALB | CDN, routing, load balancing, TLS entry point |
| FastAPI Backend | REST API, auth, validation, job creation, WebSocket updates |
| MongoDB | Job metadata, status, file locations, processing results |
| RabbitMQ | Durable job dispatch between API and workers |
| Celery Workers | Async task execution and orchestration of video jobs |
| Redis / ElastiCache | Task state, cache, sessions, worker coordination |
| AWS Batch / Fargate | Long-running video processing compute |
| FFmpeg + GL Transitions | Media rendering, transitions, encoding, frame processing |
| S3 | Raw uploads, rendered outputs, temporary artifacts, backups |
| ECR | Container images for API, workers, frontend, and batch jobs |
| Terraform | Repeatable AWS infrastructure provisioning |
| Kubernetes / EKS | Container orchestration, scaling, service deployment |

---

## 5. API as Control Plane

The FastAPI backend acts as the control plane for the system.

It is responsible for:

- validating upload and render requests
- checking authentication and authorization
- creating job records
- generating presigned S3 upload URLs
- publishing jobs to RabbitMQ
- exposing job status APIs
- sending WebSocket updates to the UI

The API should remain lightweight. It coordinates work, but it does not perform the expensive rendering itself.

Why it matters:

- API latency stays predictable
- large uploads do not turn the API into a file proxy
- worker failures do not directly crash request handling
- API pods and worker pods can scale independently

---

## 6. Queue and Worker Execution

```mermaid
flowchart LR
    API[FastAPI Backend] --> MQ[RabbitMQ]
    MQ --> W1[Celery Worker]
    MQ --> W2[Celery Worker]
    MQ --> W3[Celery Worker]

    W1 --> R[(Redis State)]
    W2 --> R
    W3 --> R

    W1 --> S3[S3 Media]
    W2 --> S3
    W3 --> S3

    W1 --> DB[(MongoDB)]
    W2 --> DB
    W3 --> DB
```

RabbitMQ and Celery create a clear boundary between request handling and background work.

The queue provides:

- async job dispatch
- worker concurrency
- retry behavior
- backpressure during bursts
- isolation between API traffic and rendering load

For this workload, the goal is task execution rather than event streaming. A job enters the queue, a worker claims it, processes it, and writes the result.

---

## 7. Batch Processing Layer

Some video jobs can run inside worker containers. Heavier jobs should run in separate batch compute.

```mermaid
flowchart TD
    W[Celery Worker] --> E{Executor}
    E --> L[Local Process Executor]
    E --> B[AWS Batch Job]

    L --> F[FFmpeg + GL Transitions]
    B --> F

    F --> O[S3 Rendered Output]
    F --> M[(MongoDB Status)]
```

AWS Batch is used for long-running or heavier rendering jobs so they do not starve the Kubernetes service layer.

This makes the architecture more flexible:

- simple jobs can run locally through workers
- heavy jobs can run through managed batch compute
- compute can scale separately from API pods
- future GPU or EC2-based workloads can be isolated from the main service tier

---

## 8. Storage and Artifacts

Large media files are not stored inside the API process or worker memory longer than necessary.

```mermaid
flowchart LR
    Raw[Raw Video Upload] --> S3A[S3 Input Bucket]
    S3A --> Worker[Worker / Batch Job]
    Worker --> S3B[S3 Output Bucket]
    Worker --> Temp[Temporary Artifacts]
    Worker --> Logs[Processing Logs]
    S3B --> Download[Download URL / UI]
```

S3 is used for:

- raw input videos
- rendered output files
- temporary artifacts
- backup storage
- durable handoff between API, workers, and batch jobs

This keeps large binary objects out of the database and out of the request cycle.

---

## 9. Local Development

The local environment mirrors the production shape without requiring real AWS resources for every development task.

```mermaid
flowchart TD
    DEV[Developer Machine] --> DC[Docker Compose]

    DC --> API[FastAPI Backend]
    DC --> FE[React / Nginx Frontend]
    DC --> DB[(MongoDB)]
    DC --> MQ[RabbitMQ]
    DC --> W[Celery Worker]
    DC --> R[(Redis)]
    DC --> LS[LocalStack]

    LS --> S3[S3 Emulation]
    LS --> BATCH[Batch Emulation]
    LS --> IAM[IAM / STS]
    LS --> LOGS[CloudWatch Logs]
```

Local Docker and LocalStack make it possible to test the full workflow shape locally:

- API request handling
- frontend routing
- job creation
- queue dispatch
- worker processing
- Redis state
- S3-like storage
- AWS-like service integration

---

## 10. Scaling and Reliability

The system is designed around independent scaling paths.

| Layer | Scaling Strategy |
|---|---|
| Frontend | CloudFront caching and static hosting |
| API | Multiple FastAPI pods behind ALB, HPA based on CPU/memory |
| Workers | Scale worker replicas based on processing load or queue depth |
| Batch | Separate compute environment for long-running jobs |
| Storage | S3 for durable media and artifacts |
| Metadata | MongoDB for job state and queryable metadata |
| State | Redis / ElastiCache for fast task state and coordination |

Reliability concerns:

- job state is persisted outside worker memory
- media artifacts are stored in S3
- failed jobs can update status instead of disappearing
- queue-backed processing provides backpressure
- workers can be restarted without losing the whole system state
- API and processing workloads are isolated from each other

---

## 11. Security Model

Security is layered across infrastructure, application, and runtime boundaries.

```mermaid
flowchart TD
    N[Network Layer] --> A[Authentication]
    A --> Z[Authorization]
    Z --> D[Data Protection]
    D --> C[Container Security]

    N --> N1[VPC Isolation]
    N --> N2[Security Groups]
    N --> N3[Kubernetes Network Policies]
    N --> N4[TLS at ALB/NLB]

    A --> A1[JWT / API Keys]
    A --> A2[Optional OAuth2/OIDC]

    Z --> Z1[Kubernetes RBAC]
    Z --> Z2[Application RBAC]

    D --> D1[Encryption at Rest]
    D --> D2[Encryption in Transit]
    D --> D3[Secrets]
    D --> D4[IAM Roles for Service Accounts]

    C --> C1[Image Scanning]
    C --> C2[Pod Security Standards]
    C --> C3[Resource Limits]
    C --> C4[Read-only Root Filesystem]
```

The goal is not one security control, but multiple boundaries:

- network isolation
- authenticated API access
- scoped authorization
- encrypted data paths
- managed secrets
- least-privilege cloud access
- container runtime hardening

---

## 12. Key Design Decisions

| Decision | Why |
|---|---|
| Separate API from video processing | Keeps request handling responsive and isolates heavy jobs |
| Use presigned S3 uploads | Avoids routing large file uploads through API pods |
| Use RabbitMQ + Celery | Fits durable background task execution with retries and workers |
| Use MongoDB for job metadata | Stores flexible job records, file locations, status, and results |
| Use Redis for task state | Fast shared state for workers and job progress |
| Use AWS Batch for heavy jobs | Moves long-running compute outside the Kubernetes service layer |
| Use S3 for media artifacts | Durable object storage for large files and outputs |
| Use Terraform | Makes AWS infrastructure repeatable, reviewable, and environment-aware |
| Use Docker / LocalStack locally | Lets developers test the architecture shape without real cloud resources |
| Use EKS and HPA | Supports container orchestration and independent service scaling |

---

## 13. Repo Walkthrough

Recommended interview path:

```mermaid
flowchart LR
    A[README] --> B[Architecture.md]
    B --> C[CLOUD_NATIVE_ARCHITECTURE.md]
    C --> D[Docker Compose]
    D --> E[Kubernetes Manifests]
    E --> F[Terraform Modules]
    F --> G[CI/CD]
    G --> H[Commit History]
```

What to show:

1. Start with the architecture problem: video rendering is heavy and should be async.
2. Show the high-level system diagram.
3. Walk through the upload-to-render flow.
4. Explain why API, queue, workers, S3, and Batch are separated.
5. Show Terraform/Kubernetes pieces as deployment proof.
6. End with commit history and explain how the project moved from local services to cloud-native hardening.

---

## 14. Interview Summary

VIDX Infra shows the platform side of the project:

- cloud-native deployment
- async background processing
- task queues and workers
- object storage for media artifacts
- long-running batch compute
- Kubernetes scaling
- Terraform-managed infrastructure
- local development parity
- production security boundaries

The main architecture principle is simple:

> Keep the API responsive, keep media durable, process jobs asynchronously, and scale the rendering layer separately from the user-facing service layer.
