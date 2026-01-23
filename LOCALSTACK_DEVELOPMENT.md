# LocalStack Development Environment Setup

A complete local AWS emulation setup for developing and testing VIDX with cloud-native architectures.

## Prerequisites

- Docker & Docker Compose
- AWS CLI v2 with LocalStack plugin
- Python 3.9+
- Git

## Installation

### 1. Install AWS CLI LocalStack Plugin

```bash
# Install AWS CLI LocalStack extension (optional but recommended)
pip install awslocal

# Or use `aws` with `--endpoint-url` flag in all commands
```

### 2. Clone and Configure

```bash
git clone <repo> vidx-infra
cd vidx-infra
```

## Quick Start

### Start All Services

```bash
# Start LocalStack + MongoDB + RabbitMQ
docker compose -f docker-compose.localstack.yml up -d

# Verify services are running
docker compose -f docker-compose.localstack.yml logs -f localstack
```

LocalStack will automatically initialize:
- S3 bucket: `vidx-video-storage`
- SQS queue: `vidx-processing`
- DynamoDB table: `vidx-cache`
- ECR repositories: `vidx-backend`, `vidx-frontend`
- Secrets Manager: `vidx/config`

### Set Up Environment

Create a `.env.localstack` file:

```bash
# AWS Configuration
export AWS_ENDPOINT_URL=http://localhost:4566
export AWS_DEFAULT_REGION=us-east-1
export AWS_ACCESS_KEY_ID=test
export AWS_SECRET_ACCESS_KEY=test

# Queue & Storage Configuration
export QUEUE_TYPE=sqs
export STORAGE_TYPE=s3

# Database Configuration
export DB_TYPE=mongodb
export VIDX_DB_HOST=localhost
export VIDX_DB_PORT=27017
export VIDX_DB_USER=vidx
export VIDX_DB_PASS=vidx

# Messaging Configuration (for fallback to RabbitMQ)
export RABBITMQ_HOST=localhost
export RABBITMQ_PORT=5672
export RABBITMQ_USER=vidx
export RABBITMQ_PASS=vidx

# S3 Configuration
export AWS_S3_BUCKET=vidx-video-storage
export S3_PRESIGN_EXPIRY=3600

# Backend Configuration
export VIDX_HOST=0.0.0.0
export VIDX_PORT=8000
export VIDX_LOG_LEVEL=INFO
```

Load the environment:

```bash
source .env.localstack
```

## Service Access

### LocalStack (AWS Services)
- **Endpoint**: `http://localhost:4566`
- **S3 Bucket**: `s3://vidx-video-storage`
- **SQS Queue**: `vidx-processing`
- **DynamoDB**: `vidx-cache` table
- **Credentials**: Access Key = `test`, Secret Key = `test`

### MongoDB
- **Connection**: `mongodb://vidx:vidx@localhost:27017/vidx`
- **Management**: MongoDB Compass or CLI
- **Port**: `27017`

### RabbitMQ
- **AMQP**: `amqp://vidx:vidx@localhost:5672/`
- **Management UI**: `http://localhost:15672`
- **Credentials**: `vidx` / `vidx`
- **Port (AMQP)**: `5672`
- **Port (Management)**: `15672`

## Development Workflow

### Run Backend with SQS + S3

```bash
cd backend

# Install dependencies
poetry install

# Start backend server
poetry run uvicorn vidx.web.application:app --reload

# In another terminal, start Celery worker with SQS
poetry run start-celery
```

### Run Frontend

```bash
cd frontend

npm install
npm start
```

### Run Tests

```bash
cd backend

# Run with LocalStack
poetry run pytest tests/ -v

# With coverage
poetry run pytest tests/ --cov=vidx --cov-report=html
```

### Deploy with Terraform (LocalStack)

```bash
cd terraform

# Initialize Terraform
terraform init

# Plan with LocalStack
terraform plan -var-file=terraform.localstack.tfvars

# Apply (create EKS cluster in LocalStack)
terraform apply -var-file=terraform.localstack.tfvars

# Check outputs
terraform output
```

## Useful AWS CLI Commands

All commands use LocalStack endpoint when configured.

### S3

```bash
# List buckets
awslocal s3 ls

# Upload file
awslocal s3 cp video.mp4 s3://vidx-video-storage/uploads/

# Generate pre-signed URL
awslocal s3 presign s3://vidx-video-storage/uploads/video.mp4 --expires-in 3600

# Download file
awslocal s3 cp s3://vidx-video-storage/outputs/merged.mp4 ./
```

### SQS

```bash
# List queues
awslocal sqs list-queues

# Send message
awslocal sqs send-message --queue-url http://localhost:4566/000000000000/vidx-processing \
  --message-body '{"task":"merge_videos"}'

# Receive messages
awslocal sqs receive-message --queue-url http://localhost:4566/000000000000/vidx-processing

# Check queue attributes
awslocal sqs get-queue-attributes --queue-url http://localhost:4566/000000000000/vidx-processing \
  --attribute-names All
```

### ECR

```bash
# List repositories
awslocal ecr describe-repositories

# Get login token
awslocal ecr get-login-password --region us-east-1 | \
  docker login --username AWS --password-stdin localhost:4566

# Push image
docker tag vidx-backend:latest localhost:4566/vidx-backend:latest
docker push localhost:4566/vidx-backend:latest
```

### DynamoDB

```bash
# List tables
awslocal dynamodb list-tables

# Scan table
awslocal dynamodb scan --table-name vidx-cache

# Put item
awslocal dynamodb put-item --table-name vidx-cache \
  --item '{"id":{"S":"test-key"},"data":{"S":"test-value"}}'
```

### Secrets Manager

```bash
# List secrets
awslocal secretsmanager list-secrets

# Get secret value
awslocal secretsmanager get-secret-value --secret-id vidx/config

# Update secret
awslocal secretsmanager update-secret --secret-id vidx/config \
  --secret-string '{"key":"new-value"}'
```

## Monitoring & Debugging

### Check Service Health

```bash
# LocalStack health
curl http://localhost:4566/_localstack/health

# MongoDB connection test
mongosh "mongodb://vidx:vidx@localhost:27017/vidx" --eval "db.adminCommand('ping')"

# RabbitMQ health
curl -u vidx:vidx http://localhost:15672/api/healthchecks/node
```

### View Logs

```bash
# LocalStack logs
docker compose -f docker-compose.localstack.yml logs -f localstack

# MongoDB logs
docker compose -f docker-compose.localstack.yml logs -f mongodb

# RabbitMQ logs
docker compose -f docker-compose.localstack.yml logs -f rabbitmq

# All services
docker compose -f docker-compose.localstack.yml logs -f
```

### Reset LocalStack (Clean Slate)

```bash
# Stop and remove all containers and volumes
docker compose -f docker-compose.localstack.yml down -v

# Restart fresh
docker compose -f docker-compose.localstack.yml up -d
```

## Testing Workflow

### End-to-End Test

1. **Upload video via API**
   ```bash
   curl -X POST http://localhost:8000/api/video/merge \
     -F "videos=@video1.mp4" \
     -F "videos=@video2.mp4" \
     -F "audio=@audio.mp3" \
     -F "transition=dissolve"
   ```

2. **Check task status**
   ```bash
   curl http://localhost:8000/api/video/merge/status?task_id=<task_id>
   ```

3. **Download merged video**
   ```bash
   curl http://localhost:8000/api/video/merge?task_id=<task_id> -o merged.mp4
   ```

4. **Verify in S3**
   ```bash
   awslocal s3 ls s3://vidx-video-storage/outputs/
   ```

### Celery Task Monitoring

```bash
# In another terminal, monitor worker
celery -A vidx.services.celery.worker inspect active

# Check registered tasks
celery -A vidx.services.celery.worker inspect registered

# View task history
celery -A vidx.services.celery.worker inspect active_queues
```

## Troubleshooting

### LocalStack not starting

```bash
# Check Docker daemon
docker info

# View detailed logs
docker compose -f docker-compose.localstack.yml logs localstack

# Increase verbosity
DEBUG=1 docker compose -f docker-compose.localstack.yml up
```

### S3 bucket not created

```bash
# Manually create (if init script didn't run)
awslocal s3 mb s3://vidx-video-storage

# Verify
awslocal s3 ls
```

### SQS queue not accessible

```bash
# Check if queue exists
awslocal sqs list-queues

# Get queue URL
QUEUE_URL=$(awslocal sqs list-queues | jq -r '.QueueUrls[0]')
echo $QUEUE_URL

# Test send message
awslocal sqs send-message --queue-url $QUEUE_URL --message-body "test"
```

### Worker not picking up tasks

```bash
# Check Celery worker is connected to SQS
# Verify QUEUE_TYPE=sqs environment variable
env | grep QUEUE_TYPE

# Check AWS credentials
env | grep AWS_

# Restart worker
poetry run start-celery
```

## Advanced Configuration

### Use RabbitMQ instead of SQS

```bash
# Set environment
export QUEUE_TYPE=rabbitmq
export RABBITMQ_HOST=localhost

# Restart services and worker
```

### Use MongoDB directly (skip LocalStack S3)

```bash
# Set environment
export STORAGE_TYPE=local
export DB_TYPE=mongodb

# Files stored in /tmp (backend container)
```

### Enable LocalStack Pro Features

```bash
# Set license key (if you have LocalStack Pro)
export LOCALSTACK_API_KEY=<your-key>

# Add to docker-compose environment section
```

## Next Steps

1. **Develop locally** with SQS + S3 via LocalStack
2. **Test Kubernetes manifests** with LocalStack EKS
3. **Apply Terraform** to deploy mock infrastructure
4. **Switch to AWS** by changing `use_localstack=false` in Terraform variables
5. **Run CI/CD pipeline** that tests against LocalStack before deploying to AWS

## Quick Reference

| Component | Local | AWS |
|-----------|-------|-----|
| Queue | RabbitMQ (localhost:5672) | SQS (via AWS SDK) |
| Storage | Local `/tmp` | S3 (us-east-1) |
| Database | MongoDB (localhost:27017) | DocumentDB |
| Endpoint | http://localhost:4566 | AWS API |
| Credentials | test/test | AWS IAM |

## Support

For issues:
- Check LocalStack logs: `docker logs vidx-localstack`
- Test connectivity: `curl http://localhost:4566/_localstack/health`
- Verify environment: `env | grep -E 'AWS|VIDX|QUEUE|STORAGE'`
- Check Terraform state: `terraform show`
