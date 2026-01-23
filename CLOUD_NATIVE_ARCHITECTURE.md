# Cloud Native Architecture - VIDX Infrastructure

## System Overview Diagram

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                          USERS / CLIENT LAYER                               │
│                        (Web Browsers / Mobile Apps)                          │
└────────────────────────────────┬────────────────────────────────────────────┘
                                 │ HTTPS
                    ┌────────────▼────────────┐
                    │   AWS CloudFront / ALB   │
                    │    (Load Balancing)      │
                    └────────────┬────────────┘
        ┌───────────────────────┴───────────────────────┐
        │                                               │
        ▼                                               ▼
┌──────────────────────┐                    ┌──────────────────────┐
│  FRONTEND LAYER      │                    │  API GATEWAY / ALB   │
│  ─────────────────   │                    │  ─────────────────── │
│  • React (TypeScript)│                    │  Route requests to   │
│  • Nginx             │                    │  backend services    │
│  • S3 + CloudFront   │                    └──────────┬───────────┘
│                      │                               │
└──────────────────────┘                               ▼
                            ┌──────────────────────────────────────┐
                            │    KUBERNETES CLUSTER (EKS)          │
                            │  ────────────────────────────────    │
                            │                                      │
                    ┌───────┼──────────┬──────────┬──────────┐    │
                    │       │          │          │          │    │
                    ▼       ▼          ▼          ▼          ▼    │
                ┌────────┐┌────────┐┌────────┐┌────────┐┌──────┐ │
                │Backend ││Celery  ││Worker  ││Worker  ││Worker│ │
                │Service ││Worker  ││Pods    ││Pods    ││Pods  │ │
                │(FastAPI)│        │└────────┘└────────┘└──────┘ │
                └────┬───┘└────────┘                             │
                     │        │                                  │
                     └────┬───┴──────────────────────────────────┘
                          │
            ┌─────────────┬┴──────────┬──────────────┐
            │             │           │              │
            ▼             ▼           ▼              ▼
      ┌─────────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐
      │  RabbitMQ   │ │ MongoDB  │ │ElastiCache│ │  Redis   │
      │  (Message   │ │(Document │ │ (Session) │ │ (State   │
      │   Broker)   │ │  Store)  │ │           │ │ Manager) │
      └─────────────┘ └──────────┘ └──────────┘ └──────────┘
            │
            ▼
      ┌──────────────────────┐
      │  AWS Batch / Fargate  │
      │  ─────────────────    │
      │  • Long-running jobs  │
      │  • Video processing   │
      │  • Heavy computation  │
      └──────────────────────┘
            │
            ▼
      ┌──────────────────────┐
      │   AWS S3 + ECR       │
      │  ─────────────────   │
      │  • Media storage     │
      │  • Container images  │
      │  • Artifacts         │
      └──────────────────────┘
```

---

## Detailed Component Architecture

### 1. **Frontend Layer** (Client-Facing)
```
┌─────────────────────────────────────────┐
│         Browser / Client App             │
└────────────────┬────────────────────────┘
                 │ HTTPS Requests
                 ▼
        ┌────────────────────┐
        │ CloudFront CDN     │
        │ (Global Cache)     │
        └────────┬───────────┘
                 │
            ┌────┴────┐
            ▼         ▼
        ┌──────┐  ┌─────────┐
        │ S3   │  │ ALB/NLB │
        │ (SPA)│  │(Dynamic)│
        └──────┘  └────┬────┘
                       │
                       ▼
        ┌──────────────────────┐
        │   React SPA          │
        │ • TypeScript         │
        │ • Tailwind CSS       │
        │ • Real-time updates  │
        │ • WebSocket support  │
        └──────────────────────┘
```

**Key Technologies:**
- **React 18+** with TypeScript
- **Tailwind CSS** for styling
- **Nginx** as reverse proxy
- **AWS S3** for static asset storage
- **CloudFront** for CDN and caching

---

### 2. **API & Service Layer** (Backend Services)

```
┌──────────────────────────────────────────────────────────┐
│         Application Load Balancer (ALB)                  │
└────────────────┬─────────────────────────────────────────┘
                 │
        ┌────────┴────────┐
        │                 │
        ▼                 ▼
    ┌──────────┐    ┌──────────┐
    │ Backend  │    │ Backend  │
    │ Service  │    │ Service  │
    │ Pod 1    │    │ Pod N    │
    └────┬─────┘    └────┬─────┘
         │               │
    ┌────▼───────────────▼────┐
    │  FastAPI Application     │
    │  ──────────────────────  │
    │  • REST endpoints        │
    │  • WebSocket support     │
    │  • Request validation    │
    │  • Error handling        │
    └────┬───────────────┬─────┘
         │               │
    ┌────▼────┐      ┌───▼──────┐
    │  Auth   │      │   Video  │
    │ Routes  │      │ Processing│
    │         │      │  Routes  │
    └────┬────┘      └───┬──────┘
         │                │
    ┌────┴────────────────┴────┐
    │  Service Layer (Business │
    │         Logic)           │
    └────┬───────────┬────┬────┘
         │           │    │
   ┌─────▼┐    ┌────▼┐ ┌─▼──────┐
   │Task  │    │User │ │Video   │
   │Service│   │Mgmt │ │Service │
   └──────┘    └─────┘ └────────┘
```

**Key Technologies:**
- **FastAPI** - Modern Python web framework
- **Python 3.11+** - Language runtime
- **Kubernetes** - Container orchestration
- **Docker** - Containerization
- **Horizontal Pod Autoscaler (HPA)** - Auto-scaling based on CPU/memory

---

### 3. **Message Queue & Async Processing Layer**

```
┌───────────────────────────────────────┐
│    Backend Service / API Layer        │
└───────────────┬───────────────────────┘
                │ Publishes Jobs
                ▼
        ┌──────────────────┐
        │   RabbitMQ       │
        │  Message Broker  │
        │  ──────────────  │
        │  • Queues        │
        │  • Exchanges     │
        │  • Dead Letter   │
        └────────┬─────────┘
                 │
        ┌────────┴────────┐
        │                 │
        ▼                 ▼
    ┌─────────┐      ┌──────────┐
    │ Celery  │      │Celery    │
    │ Worker  │      │Worker    │
    │ Pod 1   │      │Pod N     │
    └────┬────┘      └────┬─────┘
         │                │
    ┌────▼────────────────▼────┐
    │  Local Process Executor   │
    │  or AWS Batch Executor    │
    └────┬───────────────┬──────┘
         │               │
         ▼               ▼
    ┌─────────┐      ┌─────────────┐
    │ Local   │      │ AWS Batch   │
    │ Jobs    │      │ Jobs        │
    │ (simple)│      │ (complex)   │
    └─────────┘      └─────────────┘
```

**Key Technologies:**
- **RabbitMQ** - Message broker with durability
- **Celery** - Distributed task queue
- **Redis** - State management (TaskStateManager)
- **AWS Batch** - Long-running job execution

---

### 4. **Data Layer**

```
┌─────────────────────────────────────────────┐
│      Data Persistence & Caching Layer       │
└─────────────────────────────────────────────┘
         │              │            │
         ▼              ▼            ▼
    ┌──────────┐ ┌──────────┐ ┌────────────┐
    │ MongoDB  │ │ElastiCache│ │ Redis      │
    │          │ │(Session  │ │ (Task      │
    │Document  │ │ Cache)   │ │ State)     │
    │Database  │ └──────────┘ └────────────┘
    │          │
    │ • Users  │
    │ • Jobs   │
    │ • Videos │
    │ • Logs   │
    └──────────┘

    ┌──────────────────────────────┐
    │  AWS S3 (Object Storage)     │
    │  ──────────────────────────  │
    │  • Input videos              │
    │  • Output files              │
    │  • Temp artifacts            │
    │  • Backup storage            │
    └──────────────────────────────┘
```

**Key Technologies:**
- **MongoDB Atlas** - NoSQL document database (Production)
- **MongoDB Community** - Local development
- **Redis** - In-memory cache + task state manager
- **ElastiCache** - AWS managed Redis for sessions
- **AWS S3** - Scalable object storage

---

### 5. **Batch Processing Layer** (Long-running jobs)

```
┌─────────────────────────────────────┐
│   Celery Worker / RabbitMQ Queue    │
└────────────┬────────────────────────┘
             │
             ▼
    ┌────────────────────┐
    │   Task Executor    │
    │   (Pluggable)      │
    └────┬───────────┬───┘
         │           │
         ▼           ▼
    ┌──────────┐  ┌─────────────────┐
    │ Local    │  │ AWS Batch       │
    │Process   │  │ Job Definition  │
    │Executor  │  │ + Job Queue     │
    └──────────┘  └────────┬────────┘
                           │
                    ┌──────▼──────┐
                    │ Compute      │
                    │ Environment  │
                    │ (EC2/Fargate)│
                    └──────┬───────┘
                           │
                    ┌──────▼────────────┐
                    │ Video Processing  │
                    │ • FFmpeg          │
                    │ • GL Transitions  │
                    │ • Frame extraction│
                    │ • Encoding        │
                    └───────┬───────────┘
                            │
                            ▼
                    ┌──────────────┐
                    │  AWS S3      │
                    │  (Output)    │
                    └──────────────┘
```

**Key Technologies:**
- **AWS Batch** - Managed batch computing
- **FFmpeg** - Video processing
- **GL Transitions** - Visual effects
- **Fargate** - Serverless containers
- **EC2** - Traditional compute

---

### 6. **Container Registry & Artifacts**

```
┌──────────────────────┐
│     AWS ECR          │
│  (Elastic Container  │
│    Registry)         │
└──────────┬───────────┘
           │
       ┌───┴────┬────────┬──────────┐
       │        │        │          │
       ▼        ▼        ▼          ▼
   ┌──────┐┌──────┐┌──────┐┌──────────┐
   │ API  ││Worker││Batch ││Frontend  │
   │Image ││Image ││Image ││Image     │
   └──────┘└──────┘└──────┘└──────────┘
       │        │        │          │
       └────────┴────────┴──────────┘
              │
              ▼
    ┌──────────────────┐
    │  Kubernetes      │
    │  Cluster (EKS)   │
    │  Pull & Run      │
    │  Containers      │
    └──────────────────┘
```

---

## Deployment Topology

### Production Environment (AWS)
```
┌─────────────────────────────────────────────────────────────┐
│                    AWS Region (e.g., us-east-1)             │
│                                                              │
│  ┌────────────────────────────────────────────────────────┐ │
│  │              VPC (Virtual Private Cloud)               │ │
│  │                                                         │ │
│  │  ┌──────────────┐         ┌──────────────┐           │ │
│  │  │ Public Subnet│         │ Private      │           │ │
│  │  │ (Frontend)   │         │ Subnet       │           │ │
│  │  │              │         │ (Backend)    │           │ │
│  │  │ • CloudFront │         │              │           │ │
│  │  │ • S3 (SPA)   │         │ • EKS Cluster│           │ │
│  │  │ • ALB        │         │ • RDS/MongoDB│           │ │
│  │  └──────────────┘         │ • ElastiCache│           │ │
│  │                           │ • RabbitMQ   │           │ │
│  │                           └──────────────┘           │ │
│  │                                                      │ │
│  │  ┌─────────────────────────────────────────────┐   │ │
│  │  │        AWS Batch (Compute Environment)      │   │ │
│  │  │  • Long-running video processing jobs      │   │ │
│  │  │  • Auto-scaling EC2 instances              │   │ │
│  │  └─────────────────────────────────────────────┘   │ │
│  │                                                      │ │
│  │  ┌─────────────────────────────────────────────┐   │ │
│  │  │         AWS Storage (Multi-region)          │   │ │
│  │  │  • S3: Media, assets, backups              │   │ │
│  │  │  • ECR: Container images                   │   │ │
│  │  └─────────────────────────────────────────────┘   │ │
│  │                                                      │ │
│  └──────────────────────────────────────────────────────┘ │
│                                                              │
│  ┌─────────────────────────────────────────────────────┐   │
│  │        CloudWatch (Monitoring & Logging)            │   │
│  │  • Metrics                                          │   │
│  │  • Logs                                             │   │
│  │  • Alarms                                           │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

---

## Local Development Environment

```
┌─────────────────────────────────────────────────────┐
│         Developer Machine (Docker Desktop)          │
│                                                     │
│  ┌─────────────────────────────────────────────┐   │
│  │      docker-compose.yml Stack               │   │
│  │                                             │   │
│  │  ┌─────────────┐  ┌──────────────┐        │   │
│  │  │ Backend     │  │ Frontend     │        │   │
│  │  │ (FastAPI)   │  │ (React/Nginx)│        │   │
│  │  └──────┬──────┘  └──────────────┘        │   │
│  │         │                                  │   │
│  │  ┌──────┴──────┬───────────┬──────────┐   │   │
│  │  │             │           │          │   │   │
│  │  ▼             ▼           ▼          ▼   │   │
│  │ MongoDB   RabbitMQ      Celery      Redis │   │
│  │ (no auth) (guest)      Worker             │   │
│  │                                           │   │
│  └─────────────────────────────────────────┘   │
│                                                     │
│  ┌─────────────────────────────────────────────┐   │
│  │   LocalStack (AWS Service Emulation)        │   │
│  │                                             │   │
│  │  • S3 emulation                            │   │
│  │  • Batch emulation                         │   │
│  │  • IAM/STS                                 │   │
│  │  • CloudWatch logs                         │   │
│  │                                             │   │
│  └─────────────────────────────────────────────┘   │
│                                                     │
└─────────────────────────────────────────────────────┘
```

---

## Data Flow Diagrams

### Video Processing Flow
```
User Upload
    │
    ▼
┌───────────────┐
│  FastAPI      │ ─── Validate file
│  POST /upload │     Check auth
└───────┬───────┘     Return presigned URL
        │
        ▼
┌─────────────────────┐
│   AWS S3 Upload     │ ─── Store raw video
│  (Direct browser)   │
└─────────┬───────────┘
          │
          ▼
┌───────────────────────────────┐
│  Create Job Record (MongoDB)  │
│  • File location              │
│  • Metadata                   │
│  • Status: PENDING            │
└──────────┬────────────────────┘
           │
           ▼
┌──────────────────────────────────┐
│  Publish to RabbitMQ             │
│  Task: video_processing_job      │
│  Params: {job_id, file_path}     │
└──────────┬─────────────────────────┘
           │
           ▼
┌────────────────────────────────────┐
│  Celery Worker consumes message    │
│  Store job state in Redis          │
│  Status: PROCESSING                │
└──────────┬────────────────────────┘
           │
           ▼
┌──────────────────────────────────────┐
│  LocalProcessExecutor / AWS Batch   │
│  • Download video from S3           │
│  • Run FFmpeg + GL Transitions      │
│  • Upload result to S3              │
└──────────┬─────────────────────────┘
           │
           ▼
┌──────────────────────────────────────┐
│  Update MongoDB Job Record           │
│  • Result location                   │
│  • Status: COMPLETED / FAILED        │
│  • Duration                          │
└──────────┬──────────────────────────┘
           │
           ▼
┌──────────────────────────────────────┐
│  Send Notification (WebSocket)       │
│  Update UI in real-time              │
│  Show download link                  │
└──────────────────────────────────────┘
```

---

## Technology Stack Summary

| Layer | Technology | Purpose |
|-------|-----------|---------|
| **Frontend** | React 18+, TypeScript, Tailwind | User interface |
| **API Gateway** | AWS ALB / Nginx | Request routing, load balancing |
| **Backend** | FastAPI, Python 3.11+ | REST API, business logic |
| **Web Framework** | FastAPI | Modern async web framework |
| **Container Orchestration** | Kubernetes (EKS) | Pod management, scaling |
| **Message Queue** | RabbitMQ | Async task distribution |
| **Task Queue** | Celery | Distributed task processing |
| **Primary Database** | MongoDB | Document storage |
| **Cache Layer** | Redis / ElastiCache | Session, state management |
| **Batch Processing** | AWS Batch | Long-running jobs |
| **Video Processing** | FFmpeg, GL Transitions | Media transformation |
| **Object Storage** | AWS S3 | File storage |
| **Container Registry** | AWS ECR | Image repository |
| **Monitoring** | CloudWatch, Prometheus | Observability |
| **Infrastructure** | Terraform | IaC for AWS resources |

---

## Scaling & High Availability

```
┌─────────────────────────────────────────────────────┐
│         Multi-Pod / Multi-Zone Architecture         │
│                                                     │
│  ┌─────────────────────────────────────────────┐   │
│  │  AWS Region (Multi-AZ)                      │   │
│  │                                             │   │
│  │  Zone A          Zone B          Zone C     │   │
│  │  ┌─────┐        ┌─────┐        ┌─────┐    │   │
│  │  │Pod 1│        │Pod 2│        │Pod 3│    │   │
│  │  └─────┘        └─────┘        └─────┘    │   │
│  │   │              │              │          │   │
│  │   └──────────────┼──────────────┘          │   │
│  │                  │                         │   │
│  │            ┌─────▼─────┐                  │   │
│  │            │   RDS /   │ (Multi-AZ)      │   │
│  │            │  MongoDB  │ Failover        │   │
│  │            └───────────┘                  │   │
│  │                                           │   │
│  │  HPA Config:                             │   │
│  │  • Min replicas: 2                       │   │
│  │  • Max replicas: 10                      │   │
│  │  • Target CPU: 70%                       │   │
│  │  • Target Memory: 80%                    │   │
│  │                                           │   │
│  └─────────────────────────────────────────┘   │
│                                                     │
└─────────────────────────────────────────────────────┘
```

---

## Security Architecture

```
┌──────────────────────────────────────────────────────┐
│          Security Layers                             │
│                                                      │
│  Layer 1: Network                                   │
│  ├─ VPC isolation                                   │
│  ├─ Security Groups                                │
│  ├─ Network Policies (K8s)                         │
│  └─ NLB/ALB with TLS                              │
│                                                      │
│  Layer 2: Authentication                            │
│  ├─ JWT tokens                                      │
│  ├─ OAuth2/OIDC (optional)                         │
│  └─ API key validation                             │
│                                                      │
│  Layer 3: Authorization                             │
│  ├─ RBAC (K8s)                                     │
│  ├─ RBAC (Application level)                       │
│  └─ Resource-based access control                  │
│                                                      │
│  Layer 4: Data                                      │
│  ├─ Encryption at rest (S3, RDS)                  │
│  ├─ Encryption in transit (TLS)                   │
│  ├─ Database user credentials (secrets)           │
│  └─ IAM roles for service accounts                │
│                                                      │
│  Layer 5: Container                                │
│  ├─ Container image scanning                       │
│  ├─ Pod security standards                        │
│  ├─ Resource limits                               │
│  └─ Read-only root filesystem                     │
│                                                      │
└──────────────────────────────────────────────────────┘
```

---

## Integration Points

```
┌─────────────────────────────────────────────────────┐
│  External Services Integration (Future)             │
│                                                     │
│  VIDX System ──────────┬─────────────────────────┐  │
│                        │                         │  │
│                        ▼                         ▼  │
│                   Webhooks              Notification │
│                   for updates           Services    │
│                   (Slack, Discord,      (SendGrid,  │
│                    Teams)                SMS)       │
│                                                     │
│                      │                             │
│                      ├─ Analytics → Google Analytics│
│                      ├─ Errors → Sentry / DataDog   │
│                      └─ Logs → ELK Stack (optional) │
│                                                     │
└─────────────────────────────────────────────────────┘
```

---

## Environment Promotion Path

```
┌─────────────────────────────────────────────────────┐
│     Development → Staging → Production              │
│                                                     │
│  DEV (LocalStack)                                   │
│  ├─ Local Docker Compose stack                      │
│  ├─ SQLite/MongoDB local                           │
│  └─ Mocked AWS services                            │
│      │                                              │
│      ▼                                              │
│  STAGING (AWS Account A)                           │
│  ├─ EKS cluster                                    │
│  ├─ RDS MongoDB                                    │
│  ├─ S3 for media                                   │
│  └─ Full AWS services (except Batch)               │
│      │                                              │
│      ▼                                              │
│  PROD (AWS Account B)                              │
│  ├─ Multi-AZ EKS cluster                           │
│  ├─ MongoDB Atlas (managed)                        │
│  ├─ ElastiCache for Redis                          │
│  ├─ AWS Batch for processing                       │
│  ├─ CloudFront + S3 for assets                     │
│  └─ Full observability stack                       │
│                                                     │
└─────────────────────────────────────────────────────┘
```

---

## Key Architectural Decisions

| Decision | Why | Trade-off |
|----------|-----|-----------|
| **FastAPI** | Async support, auto-docs, validation | Learning curve for team |
| **Kubernetes** | Scalability, declarative, self-healing | Operational complexity |
| **RabbitMQ + Celery** | Distributed tasks, durable, proven | Memory overhead |
| **MongoDB** | Flexible schema, easy scaling | Requires discipline on queries |
| **AWS Batch** | Cost-effective, auto-scaling, managed | Batch-specific (not real-time) |
| **Redis State Manager** | Persistent across restarts | Extra Redis instance cost |
| **S3 for storage** | Scalable, cheap, durable | Network latency vs local storage |
| **LocalStack for dev** | Near-production parity | Doesn't match AWS 100% |

---

## Next Steps for Enhancement

1. ✅ **State Management** - Redis-backed TaskStateManager
2. ✅ **Security** - Network policies, resource limits, pod security
3. 🔄 **Observability** - Prometheus, Grafana, distributed tracing
4. 🔄 **Cost Optimization** - Reserved instances, Savings Plans
5. 🔄 **Disaster Recovery** - Multi-region backup, failover
6. 🔄 **CI/CD Pipeline** - GitHub Actions → EKS deployment

