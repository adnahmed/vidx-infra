# VIDX Cloud-Native Infrastructure

Production-grade Cloud-Native architecture for VIDX deployed on AWS EKS with comprehensive Terraform IaC, Kubernetes orchestration, and CI/CD automation.

## 📋 Table of Contents

- [Quick Start](#quick-start)
- [Architecture](#architecture)
- [Project Structure](#project-structure)
- [Prerequisites](#prerequisites)
- [Deployment](#deployment)
- [CI/CD Pipeline](#cicd-pipeline)
- [Documentation](#documentation)
- [Features](#features)
- [Cost Optimization](#cost-optimization)
- [Support](#support)

## 🚀 Quick Start

### 1. Prerequisites

```bash
# Install required tools
brew install terraform aws-cli kubectl helm git docker  # macOS
# or
apt-get install terraform awscli kubectl helm git docker  # Linux

# Verify installations
terraform version    # >= 1.5.0
aws --version       # >= 2.0.0
kubectl version --client
helm version
```

### 2. Configure AWS

```bash
aws configure
# Enter your AWS credentials and region (us-east-1 recommended)
```

### 3. Deploy Infrastructure

```bash
# Clone repository
git clone <repository-url>
cd vidx-infra

# Make setup scripts executable
chmod +x deployment-setup.sh setup-localstack.sh

# Run automated setup
./deployment-setup.sh
```

### 4. Verify Deployment

```bash
# Check cluster status
kubectl get nodes
kubectl get pods -n vidx-prod
kubectl get svc -n vidx-prod
```

## 🏗️ Architecture

### High-Level Overview

```
┌─────────────────────────────────────────┐
│         Route 53 (DNS Management)       │
└────────────────┬────────────────────────┘
                 │
┌────────────────▼────────────────────────┐
│      ALB (Application Load Balancer)    │
│  • Terminates SSL/TLS                   │
│  • Route-based traffic shaping          │
│  • Rate limiting                        │
└────────────────┬────────────────────────┘
                 │
┌────────────────▼────────────────────────┐
│       EKS Cluster (Kubernetes)          │
│  • Managed Control Plane                │
│  • Auto-scaling Node Groups             │
│  • OIDC Provider for IAM Integration    │
│                                          │
│  ┌──────────────────────────────────┐  │
│  │    vidx-prod Namespace           │  │
│  │  • vidx-backend (FastAPI)        │  │
│  │  • vidx-worker (Celery)          │  │
│  │  • vidx-frontend (React/Nginx)   │  │
│  │  • MongoDB (StatefulSet)         │  │
│  │  • RabbitMQ (StatefulSet)        │  │
│  └──────────────────────────────────┘  │
└────────────────┬────────────────────────┘
                 │
        ┌────────┼────────┐
        │        │        │
┌───────▼──┐ ┌───▼──┐ ┌──▼─────────┐
│    S3    │ │ ECR  │ │   RDS/     │
│ (Videos) │ │(Imgs)│ │  Neptune   │
└──────────┘ └──────┘ └────────────┘
```

### Key Components

| Component | Type | Purpose |
|-----------|------|---------|
| **vidx-backend** | FastAPI Deployment | REST API, video processing coordination |
| **vidx-worker** | Celery Deployment | Async video processing tasks |
| **vidx-frontend** | Nginx Deployment | React SPA, static content serving |
| **MongoDB** | StatefulSet | Primary data store |
| **RabbitMQ** | StatefulSet | Message queue for async tasks |
| **ALB** | AWS ELB | Traffic distribution, SSL termination |
| **ECR** | Docker Registry | Container image storage |
| **S3** | Object Storage | Video and asset storage |

## 📁 Project Structure

```
vidx-infra/
├── kubernetes/
│   ├── namespace.yaml                 # Namespace and RBAC
│   ├── mongodb-*.yaml                 # MongoDB StatefulSet
│   ├── rabbitmq-*.yaml                # RabbitMQ StatefulSet
│   ├── backend-*.yaml                 # Backend Deployment & HPA
│   ├── worker-*.yaml                  # Worker Deployment & HPA
│   ├── frontend-*.yaml                # Frontend Deployment & HPA
│   ├── rbac.yaml                      # Role-based access control
│   ├── pdb.yaml                       # Pod disruption budgets
│   ├── ingress.yaml                   # Ingress configuration
│   └── kustomization.yaml             # Kustomize overlay
│
├── terraform/
│   ├── provider.tf                    # AWS provider configuration
│   ├── variables.tf                   # Input variables
│   ├── vpc.tf                         # VPC, subnets, security groups
│   ├── eks.tf                         # EKS cluster and node groups
│   ├── s3_ecr.tf                      # S3 buckets and ECR repos
│   ├── outputs.tf                     # Output values
│   ├── main.tf                        # Main module definition
│   ├── terraform.dev.tfvars           # Development environment variables
│   ├── terraform.prod.tfvars          # Production environment variables
│   └── terraform.localstack.tfvars    # LocalStack testing variables
│
├── .github/
│   └── workflows/
│       ├── deploy.yml                 # CI/CD deployment pipeline
│       └── terraform.yml              # Infrastructure automation
│
├── backend/
│   ├── Dockerfile                     # Optimized multi-stage build
│   ├── docker-entrypoint.sh          # Container entrypoint
│   ├── pyproject.toml                # Python dependencies
│   └── ...
│
├── frontend/
│   ├── Dockerfile                     # Optimized multi-stage build
│   ├── nginx.conf                     # Nginx configuration
│   ├── package.json                  # Node dependencies
│   └── ...
│
├── deployment-setup.sh                # Automated deployment script
├── setup-localstack.sh                # LocalStack setup for testing
│
├── CLOUD_NATIVE_DEPLOYMENT.md         # Comprehensive deployment guide
├── DOCKER_OPTIMIZATION.md             # Docker optimization details
├── KUBERNETES_REFERENCE.md            # Kubectl command reference
└── README.md                          # This file
```

## 📋 Prerequisites

### AWS Account Requirements

- ✅ AWS Account with billing enabled
- ✅ IAM permissions for:
  - EKS cluster creation
  - VPC and subnet management
  - ECR repository management
  - S3 bucket operations
  - IAM role management

### Local Requirements

- ✅ Terraform >= 1.5.0
- ✅ AWS CLI v2
- ✅ kubectl >= 1.24
- ✅ Helm 3+
- ✅ Docker (for building images)
- ✅ Git
- ✅ Bash 4.0+

### Minimum Compute Resources

- ✅ 8GB RAM
- ✅ 20GB Free Disk Space
- ✅ Stable internet connection

## 🚀 Deployment

### Step 1: Initialize Infrastructure

```bash
cd terraform

# Initialize Terraform
terraform init

# Validate configuration
terraform validate

# Format check
terraform fmt -check -recursive
```

### Step 2: Plan Infrastructure

```bash
# For development
terraform plan -var-file=terraform.dev.tfvars -out=tfplan

# For production
terraform plan -var-file=terraform.prod.tfvars -out=tfplan

# Review the plan
terraform show tfplan
```

### Step 3: Apply Infrastructure

```bash
terraform apply tfplan
```

### Step 4: Configure kubectl

```bash
# Get cluster endpoint and credentials
aws eks update-kubeconfig \
  --name vidx-eks-cluster \
  --region us-east-1

# Verify connection
kubectl cluster-info
kubectl get nodes
```

### Step 5: Deploy Applications

```bash
cd ../k8s

# Apply all manifests with Kustomize
kustomize build . | kubectl apply -f -

# Or apply manually
kubectl apply -f namespace.yaml
kubectl apply -f mongodb-*.yaml
kubectl apply -f rabbitmq-*.yaml
kubectl apply -f backend-*.yaml
kubectl apply -f worker-*.yaml
kubectl apply -f frontend-*.yaml
kubectl apply -f ingress.yaml
```

### Step 6: Update Configuration

```bash
# Update backend secrets (API keys, database credentials)
kubectl edit secret vidx-backend-secret -n vidx-prod

# Update MongoDB credentials
kubectl edit secret mongodb-credentials -n vidx-prod

# Update RabbitMQ credentials
kubectl edit secret rabbitmq-credentials -n vidx-prod
```

### Step 7: Verify Deployment

```bash
# Check all resources
kubectl get all -n vidx-prod

# Check pod status
kubectl get pods -n vidx-prod -w

# Check service endpoints
kubectl get svc -n vidx-prod
kubectl get endpoints -n vidx-prod

# Check ingress
kubectl get ingress -n vidx-prod
```

## 🔄 CI/CD Pipeline

### GitHub Actions Workflows

#### Deploy Workflow (`.github/workflows/deploy.yml`)

Triggers on push to `main` or `develop`:

1. **Code Quality Checks** (PRs only)
   - Python linting (Ruff)
   - Code formatting (Black)
   - Type checking (MyPy)
   - Unit tests (Pytest)

2. **Build Backend Image**
   - Multi-stage Docker build
   - Push to ECR
   - Image scanning (Trivy)

3. **Build Frontend Image**
   - React build with optimizations
   - Push to ECR
   - Image scanning

4. **Deploy to EKS**
   - Update deployments with new images
   - Rolling update strategy
   - Health checks
   - Automatic rollback on failure

#### Terraform Workflow (`.github/workflows/terraform.yml`)

Triggers on Terraform file changes:

1. **Plan**
   - Terraform format check
   - Plan creation
   - Comments on PRs

2. **Apply**
   - Infrastructure provisioning
   - Output generation

### Secrets Required

Set in GitHub repository settings:

```
AWS_ACCESS_KEY_ID          # IAM access key
AWS_SECRET_ACCESS_KEY      # IAM secret key
SLACK_WEBHOOK_URL          # (Optional) Slack notifications
```

## 📊 Features

### High Availability

- ✅ Multi-AZ deployment (3 availability zones)
- ✅ Auto-scaling node groups (2-10 nodes)
- ✅ Pod disruption budgets (PDB)
- ✅ Rolling updates with zero downtime
- ✅ Health checks (liveness, readiness, startup)

### Auto-Scaling

- ✅ **Backend HPA**: 2-10 replicas (CPU 70%, Memory 80%)
- ✅ **Worker HPA**: 2-20 replicas (CPU 60%, Memory 75%)
- ✅ **Frontend HPA**: 2-8 replicas (CPU 80%, Memory 85%)
- ✅ Cluster autoscaling for nodes

### Security

- ✅ Non-root container users
- ✅ Network segmentation with security groups
- ✅ RBAC with minimal permissions
- ✅ Secret management (Kubernetes Secrets)
- ✅ Image scanning in ECR
- ✅ VPC with private subnets for nodes
- ✅ NAT gateways for private network egress

### Monitoring & Logging

- ✅ CloudWatch logs integration
- ✅ Pod resource monitoring
- ✅ HPA metrics tracking
- ✅ Event logging
- ✅ Health check logs

### Disaster Recovery

- ✅ Automated backups for MongoDB
- ✅ S3 versioning for video storage
- ✅ Persistent volumes for stateful services
- ✅ Lifecycle policies for old data

## 💰 Cost Optimization

### Strategies Implemented

1. **Spot Instances** (Development)
   - Up to 70% savings
   - Configurable for production

2. **Graviton2 Processors** (t3/t4 instances)
   - Better price/performance ratio
   - Can be enabled in variables

3. **Lifecycle Policies**
   - Archive old videos to Glacier (90 days)
   - Delete expired content (365 days)
   - Remove incomplete uploads (7 days)

4. **Image Optimization**
   - Multi-stage builds reduce image size
   - Faster pulls = lower egress costs

5. **Efficient Scheduling**
   - Pod anti-affinity for better resource usage
   - Resource requests/limits prevent overprovisioning

### Monthly Cost Estimate

| Component | Dev Cost | Prod Cost |
|-----------|----------|-----------|
| EKS Control Plane | $73 | $73 |
| EC2 (t3.large SPOT) | $30 | - |
| EC2 (t3.xlarge ON_DEMAND) | - | $100 |
| RDS/MongoDB | $30 | $50 |
| S3 Storage | $5 | $50 |
| Data Transfer | $5 | $100 |
| **Total** | **~$143** | **~$373** |

## 📚 Documentation

### Main Guides

1. **[CLOUD_NATIVE_DEPLOYMENT.md](./CLOUD_NATIVE_DEPLOYMENT.md)**
   - Complete deployment guide
   - Architecture overview
   - Step-by-step instructions
   - Troubleshooting

2. **[DOCKER_OPTIMIZATION.md](./DOCKER_OPTIMIZATION.md)**
   - Dockerfile optimization techniques
   - Image size comparison
   - Build performance tips

3. **[KUBERNETES_REFERENCE.md](./KUBERNETES_REFERENCE.md)**
   - kubectl command reference
   - Debugging commands
   - Port forwarding
   - Backup/restore procedures

4. **[backend/README.md](./backend/README.md)**
   - Backend application documentation

5. **[frontend/README.md](./frontend/README.md)**
   - Frontend application documentation

## 🔧 Common Tasks

### View Application Logs

```bash
# Backend logs
kubectl logs -f deployment/vidx-backend -n vidx-prod

# Worker logs
kubectl logs -f deployment/vidx-worker -n vidx-prod

# Frontend logs
kubectl logs -f deployment/vidx-frontend -n vidx-prod
```

### Update Application Configuration

```bash
# Edit environment variables
kubectl edit configmap vidx-backend-config -n vidx-prod

# Edit secrets
kubectl edit secret vidx-backend-secret -n vidx-prod

# Rollout restart to apply changes
kubectl rollout restart deployment/vidx-backend -n vidx-prod
```

### Scale Applications

```bash
# Manual scaling
kubectl scale deployment vidx-backend --replicas=5 -n vidx-prod

# View HPA status
kubectl get hpa -n vidx-prod -w
```

### Database Access

```bash
# Port forward to MongoDB
kubectl port-forward svc/mongodb 27017:27017 -n vidx-prod

# Port forward to RabbitMQ management
kubectl port-forward svc/rabbitmq 15672:15672 -n vidx-prod
# Access: http://localhost:15672 (user: vidx, password: vidx)
```

## 🧪 Local Development with LocalStack

For local testing without AWS costs:

```bash
# Start LocalStack
./setup-localstack.sh

# Deploy with LocalStack
cd terraform
terraform apply -var-file=terraform.localstack.tfvars

# Stop LocalStack
docker-compose -f docker-compose.localstack.yml down
```

## 🐛 Troubleshooting

### Pod Not Starting

```bash
kubectl describe pod <pod-name> -n vidx-prod
kubectl logs <pod-name> -n vidx-prod
kubectl get events -n vidx-prod --sort-by='.lastTimestamp'
```

### Slow Application

```bash
# Check resource usage
kubectl top pods -n vidx-prod
kubectl top nodes

# Check HPA status
kubectl describe hpa vidx-backend-hpa -n vidx-prod
```

### Database Connection Issues

```bash
# Test connection
kubectl run -it --rm debug --image=mongo --restart=Never -n vidx-prod -- \
  mongosh mongodb://vidx:vidx@mongodb:27017/vidx

# Check service
kubectl get svc mongodb -n vidx-prod
kubectl get endpoints mongodb -n vidx-prod
```

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit changes (`git commit -m 'Add amazing feature'`)
4. Push to branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## 📝 License

This project is licensed under the MIT License - see LICENSE file for details.

## 📞 Support

For issues and questions:

1. Check the [documentation](./CLOUD_NATIVE_DEPLOYMENT.md)
2. Review [troubleshooting section](#troubleshooting)
3. Check existing [GitHub Issues](../../issues)
4. Create a new issue with detailed information

## 🔗 Useful Resources

- [AWS EKS Documentation](https://docs.aws.amazon.com/eks/)
- [Kubernetes Official Docs](https://kubernetes.io/docs/)
- [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest)
- [Docker Best Practices](https://docs.docker.com/develop/dev-best-practices/)

---

**Last Updated**: January 17, 2026  
**Maintainer**: Your Team  
**Version**: 1.0.0
