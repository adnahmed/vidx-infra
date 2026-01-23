# VIDX Platform-Agnostic Quick Start Guide

Complete guide to running VIDX locally with LocalStack and deploying to AWS.

## 5-Minute Quick Start (Local Development)

### 1. Start Services

```bash
# Clone the repo
git clone <repo> vidx-infra
cd vidx-infra

# Start all services (LocalStack, MongoDB, RabbitMQ)
bash setup-local-dev.sh start

# This will:
# ✓ Check prerequisites
# ✓ Start LocalStack with S3, SQS, DynamoDB, ECR, etc.
# ✓ Start MongoDB
# ✓ Start RabbitMQ
# ✓ Create .env.local with defaults
# ✓ Verify all services
```

### 2. Install Dependencies

```bash
# Backend
cd backend
poetry install

# Frontend
cd frontend
npm install
```

### 3. Run the Application

```bash
# Terminal 1: Backend API
cd backend
source ../.env.local
poetry run uvicorn vidx.web.application:app --reload

# Terminal 2: Celery Worker
cd backend
source ../.env.local
poetry run start-celery

# Terminal 3: Frontend
cd frontend
npm start
```

### 4. Test the Flow

```bash
# Upload and merge videos
curl -X POST http://localhost:8000/api/video/merge \
  -F "videos=@video1.mp4" \
  -F "videos=@video2.mp4" \
  -F "transition=dissolve"

# Check status
curl http://localhost:8000/api/video/merge/status?task_id=<task_id>

# Download merged video
curl http://localhost:8000/api/video/merge?task_id=<task_id> -o merged.mp4
```

**API running on**: `http://localhost:8000`  
**Frontend running on**: `http://localhost:3000`

---

## Configuration Modes

### Mode 1: Local Storage + RabbitMQ (Default)

Best for: **Development with minimal dependencies**

```bash
# Set in .env.local
QUEUE_TYPE=rabbitmq
STORAGE_TYPE=local
DB_TYPE=mongodb

# Services used:
# - RabbitMQ (localhost:5672)
# - Local /tmp storage
# - MongoDB (localhost:27017)
```

**No additional setup needed.**

### Mode 2: LocalStack SQS + S3 (Recommended)

Best for: **Testing AWS integration locally**

```bash
# Set in .env.local
QUEUE_TYPE=sqs
STORAGE_TYPE=s3
DB_TYPE=mongodb
AWS_ENDPOINT_URL=http://localhost:4566
AWS_S3_BUCKET=vidx-video-storage

# Services used:
# - LocalStack SQS (localhost:4566)
# - LocalStack S3 (localhost:4566)
# - MongoDB (localhost:27017)
```

**Auto-initialized by setup script** (bucket + queue created on startup).

### Mode 3: AWS Production

Best for: **Real AWS deployment**

```bash
# Deploy with Terraform
cd terraform
terraform apply -var-file=terraform.prod.tfvars

# Configure environment (via Kubernetes secret or EC2 IAM role)
QUEUE_TYPE=sqs
STORAGE_TYPE=s3
DB_TYPE=documentdb
AWS_DEFAULT_REGION=us-east-1
AWS_S3_BUCKET=vidx-video-storage-prod-<account-id>

# Services used:
# - AWS SQS
# - AWS S3
# - AWS DocumentDB (managed MongoDB)
# - AWS EKS (Kubernetes)
```

---

## LocalStack Services

All AWS services available in your local environment:

```
http://localhost:4566

Services running:
✓ S3 (object storage)
✓ SQS (message queue)
✓ DynamoDB (NoSQL cache)
✓ Lambda (serverless functions)
✓ ECR (container registry)
✓ EKS (Kubernetes)
✓ EC2 (compute instances)
✓ IAM (identity & access)
✓ CloudFormation (IaC)
✓ SecretsManager (secrets)
✓ KMS (encryption)
✓ CloudWatch (monitoring)
+ 50+ more...
```

### Access LocalStack Services

```bash
# Using awslocal CLI (AWS CLI + LocalStack plugin)
awslocal s3 ls
awslocal sqs list-queues
awslocal ecr describe-repositories

# Or with AWS CLI + endpoint-url
aws s3 ls --endpoint-url=http://localhost:4566
```

---

## Common Tasks

### Upload Video to S3

```bash
# When using STORAGE_TYPE=s3
awslocal s3 cp my-video.mp4 s3://vidx-video-storage/uploads/

# Get pre-signed URL
awslocal s3 presign s3://vidx-video-storage/uploads/my-video.mp4 --expires-in 3600
```

### Check SQS Queue

```bash
# List messages
awslocal sqs receive-message \
  --queue-url http://localhost:4566/000000000000/vidx-processing

# Send test message
awslocal sqs send-message \
  --queue-url http://localhost:4566/000000000000/vidx-processing \
  --message-body '{"task":"test"}'
```

### Monitor Celery Worker

```bash
# View active tasks
celery -A vidx.services.celery.worker inspect active

# View registered tasks
celery -A vidx.services.celery.worker inspect registered

# Monitor in real-time (Flower UI)
poetry add flower
celery -A vidx.services.celery.worker flower
# Open http://localhost:5555
```

### Check Service Health

```bash
# LocalStack
curl http://localhost:4566/_localstack/health | jq .

# MongoDB
mongosh "mongodb://vidx:vidx@localhost:27017/vidx" --eval "db.adminCommand('ping')"

# RabbitMQ
curl -u vidx:vidx http://localhost:15672/api/healthchecks/node

# Backend
curl http://localhost:8000/api/health
```

---

## Management Commands

### Using setup-local-dev.sh

```bash
# Start services
bash setup-local-dev.sh start

# Stop services
bash setup-local-dev.sh stop

# Restart services
bash setup-local-dev.sh restart

# View status
bash setup-local-dev.sh status

# View logs
bash setup-local-dev.sh logs localstack
bash setup-local-dev.sh logs mongodb
bash setup-local-dev.sh logs rabbitmq

# Clean slate (remove all data)
bash setup-local-dev.sh clean
```

### Manual Docker Compose

```bash
# Start
docker compose -f docker-compose.localstack.yml up -d

# Stop
docker compose -f docker-compose.localstack.yml down

# View logs
docker compose -f docker-compose.localstack.yml logs -f localstack

# Remove volumes (clean state)
docker compose -f docker-compose.localstack.yml down -v
```

---

## Deploying to AWS

### Prerequisites

- AWS account with appropriate IAM permissions
- AWS CLI configured with credentials
- Terraform installed

### Steps

```bash
# 1. Configure AWS credentials
aws configure
# or
export AWS_ACCESS_KEY_ID=...
export AWS_SECRET_ACCESS_KEY=...
export AWS_DEFAULT_REGION=us-east-1

# 2. Plan infrastructure
cd terraform
terraform plan -var-file=terraform.prod.tfvars

# 3. Apply (create resources)
terraform apply -var-file=terraform.prod.tfvars

# 4. Get outputs (cluster info, S3 bucket, SQS queue)
terraform output

# 5. Configure kubectl
aws eks update-kubeconfig --name vidx-eks-cluster --region us-east-1

# 6. Create Kubernetes secret with app credentials
kubectl create namespace vidx-prod

kubectl create secret generic vidx-backend-secret \
  -n vidx-prod \
  --from-literal=QUEUE_TYPE=sqs \
  --from-literal=STORAGE_TYPE=s3 \
  --from-literal=DB_TYPE=documentdb \
  --from-literal=AWS_S3_BUCKET=<s3-bucket-from-terraform> \
  --from-literal=VIDX_DB_HOST=<documentdb-endpoint> \
  --from-literal=AWS_ACCESS_KEY_ID=<iam-key> \
  --from-literal=AWS_SECRET_ACCESS_KEY=<iam-secret>

# 7. Update K8s manifests with real ECR URIs
# Edit k8s/backend-deployment.yaml, k8s/worker-deployment.yaml
# Replace image URIs with actual AWS ECR repositories

# 8. Deploy to EKS
kubectl apply -f k8s/

# 9. Verify deployment
kubectl get pods -n vidx-prod
kubectl get svc -n vidx-prod
kubectl get ingress -n vidx-prod
```

### Monitoring AWS Deployment

```bash
# Check pods
kubectl get pods -n vidx-prod

# View logs
kubectl logs -n vidx-prod -l app=vidx-backend
kubectl logs -n vidx-prod -l app=vidx-worker

# Check ingress
kubectl get ingress -n vidx-prod

# Monitor metrics
kubectl top nodes
kubectl top pods -n vidx-prod

# CloudWatch logs (AWS console or CLI)
aws logs tail /aws/eks/vidx-eks-cluster --follow
```

---

## Troubleshooting

### "Connection refused" errors

```bash
# Check if services are running
docker compose -f docker-compose.localstack.yml ps

# Check logs
docker compose -f docker-compose.localstack.yml logs localstack

# Restart
bash setup-local-dev.sh restart
```

### "Cannot find module" errors

```bash
# Reinstall dependencies
cd backend && poetry install
cd frontend && npm install
```

### "AWS credentials not found"

```bash
# Ensure environment is loaded
source .env.local

# Verify
echo $AWS_ACCESS_KEY_ID
echo $AWS_ENDPOINT_URL
```

### Worker not consuming tasks

```bash
# Check QUEUE_TYPE is set
env | grep QUEUE_TYPE

# If using SQS, ensure boto3 is installed
poetry show boto3  # or poetry add celery[sqs] boto3

# Restart worker
pkill -f "celery"
poetry run start-celery
```

### S3 upload fails

```bash
# Ensure bucket exists
awslocal s3 ls

# If missing, create manually
awslocal s3 mb s3://vidx-video-storage

# Check permissions
export AWS_ACCESS_KEY_ID=test
export AWS_SECRET_ACCESS_KEY=test
```

---

## Architecture & Documentation

For detailed information:

- **Architecture**: See [PLATFORM_AGNOSTIC_REFACTORING.md](PLATFORM_AGNOSTIC_REFACTORING.md)
- **LocalStack Setup**: See [LOCALSTACK_DEVELOPMENT.md](LOCALSTACK_DEVELOPMENT.md)
- **Kubernetes Reference**: See [KUBERNETES_REFERENCE.md](KUBERNETES_REFERENCE.md)
- **Infrastructure**: See [README_INFRASTRUCTURE.md](README_INFRASTRUCTURE.md)

---

## Next Steps

1. ✅ Run locally with setup script
2. 📝 Test with sample videos
3. 🔄 Try switching between QUEUE_TYPE and STORAGE_TYPE
4. ☁️ Deploy to AWS via Terraform
5. 🚀 Scale with EKS and GPU nodes

**Questions?** Check [LOCALSTACK_DEVELOPMENT.md](LOCALSTACK_DEVELOPMENT.md) for comprehensive troubleshooting and advanced usage.
