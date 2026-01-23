#!/bin/bash
# LocalStack initialization script
# This script runs automatically when LocalStack starts to create required AWS resources

set -e

echo "[LocalStack Init] Starting resource initialization..."

# AWS credentials for LocalStack
export AWS_ACCESS_KEY_ID=test
export AWS_SECRET_ACCESS_KEY=test
export AWS_DEFAULT_REGION=us-east-1
export AWS_ENDPOINT_URL=http://localhost:4566

# Function to retry a command
retry() {
    local n=1
    local max=30
    local delay=1
    while true; do
        "$@" && break || {
            if [[ $n -lt $max ]]; then
                ((n++))
                sleep $delay;
            else
                return 1
            fi
        }
    done
}

# Wait for LocalStack to be fully ready
echo "[LocalStack Init] Waiting for LocalStack to be ready..."
retry curl -s http://localhost:4566/_localstack/health >/dev/null

# Create S3 bucket
echo "[LocalStack Init] Creating S3 bucket..."
awslocal s3 mb s3://vidx-video-storage 2>/dev/null || echo "S3 bucket already exists"

# Create SQS queue
echo "[LocalStack Init] Creating SQS queue..."
awslocal sqs create-queue --queue-name vidx-processing \
  --attributes "VisibilityTimeout=300,MessageRetentionPeriod=1209600" \
  2>/dev/null || echo "SQS queue already exists"

# Create DynamoDB table (optional: for caching/sessions)
echo "[LocalStack Init] Creating DynamoDB table..."
awslocal dynamodb create-table \
  --table-name vidx-cache \
  --attribute-definitions AttributeName=id,AttributeType=S \
  --key-schema AttributeName=id,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  2>/dev/null || echo "DynamoDB table already exists"

# Create ECR repositories
echo "[LocalStack Init] Creating ECR repositories..."
awslocal ecr create-repository --repository-name vidx-backend 2>/dev/null || echo "ECR backend repo already exists"
awslocal ecr create-repository --repository-name vidx-frontend 2>/dev/null || echo "ECR frontend repo already exists"

# Create Secrets Manager secret for app configuration
echo "[LocalStack Init] Creating Secrets Manager secret..."
awslocal secretsmanager create-secret \
  --name vidx/config \
  --secret-string '{"db_host":"mongodb","db_port":27017,"db_user":"vidx","db_pass":"vidx"}' \
  2>/dev/null || echo "Secret already exists"

# Create AWS Batch resources
echo "[LocalStack Init] Setting up AWS Batch for video processing..."

# Create IAM role for Batch
echo "[LocalStack Init] Creating IAM role for Batch..."
BATCH_ROLE_ARN=$(awslocal iam create-role \
  --role-name vidx-batch-task-role \
  --assume-role-policy-document '{
    "Version": "2012-10-17",
    "Statement": [
      {
        "Effect": "Allow",
        "Principal": {
          "Service": "batch.amazonaws.com"
        },
        "Action": "sts:AssumeRole"
      }
    ]
  }' 2>/dev/null | jq -r '.Role.Arn' || echo "arn:aws:iam::000000000000:role/vidx-batch-task-role")

# Create IAM role for EC2 instances in Batch
BATCH_EC2_ROLE=$(awslocal iam create-role \
  --role-name vidx-batch-ec2-role \
  --assume-role-policy-document '{
    "Version": "2012-10-17",
    "Statement": [
      {
        "Effect": "Allow",
        "Principal": {
          "Service": "ec2.amazonaws.com"
        },
        "Action": "sts:AssumeRole"
      }
    ]
  }' 2>/dev/null | jq -r '.Role.Arn' || echo "arn:aws:iam::000000000000:role/vidx-batch-ec2-role")

# Create instance profile
awslocal iam create-instance-profile \
  --instance-profile-name vidx-batch-instance-profile 2>/dev/null || echo "Instance profile already exists"

awslocal iam add-role-to-instance-profile \
  --instance-profile-name vidx-batch-instance-profile \
  --role-name vidx-batch-ec2-role 2>/dev/null || echo "Role already attached to instance profile"

# Create VPC (if not exists)
echo "[LocalStack Init] Setting up networking for Batch..."
VPC_ID=$(awslocal ec2 describe-vpcs --filters "Name=cidr,Values=10.0.0.0/16" --query 'Vpcs[0].VpcId' --output text 2>/dev/null || echo "")

if [ -z "$VPC_ID" ] || [ "$VPC_ID" = "None" ]; then
  VPC_ID=$(awslocal ec2 create-vpc --cidr-block 10.0.0.0/16 --query 'Vpc.VpcId' --output text)
  echo "[LocalStack Init] Created VPC: $VPC_ID"
else
  echo "[LocalStack Init] Using existing VPC: $VPC_ID"
fi

# Create subnets
SUBNET_ID=$(awslocal ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC_ID" --query 'Subnets[0].SubnetId' --output text 2>/dev/null || echo "")

if [ -z "$SUBNET_ID" ] || [ "$SUBNET_ID" = "None" ]; then
  SUBNET_ID=$(awslocal ec2 create-subnet --vpc-id $VPC_ID --cidr-block 10.0.1.0/24 --query 'Subnet.SubnetId' --output text)
  echo "[LocalStack Init] Created subnet: $SUBNET_ID"
else
  echo "[LocalStack Init] Using existing subnet: $SUBNET_ID"
fi

# Create security group
SG_ID=$(awslocal ec2 describe-security-groups --filters "Name=group-name,Values=vidx-batch-sg" --query 'SecurityGroups[0].GroupId' --output text 2>/dev/null || echo "")

if [ -z "$SG_ID" ] || [ "$SG_ID" = "None" ]; then
  SG_ID=$(awslocal ec2 create-security-group --group-name vidx-batch-sg --description "Security group for Batch" --vpc-id $VPC_ID --query 'GroupId' --output text)
  echo "[LocalStack Init] Created security group: $SG_ID"
else
  echo "[LocalStack Init] Using existing security group: $SG_ID"
fi

# Create Batch compute environment
echo "[LocalStack Init] Creating Batch compute environment..."
awslocal batch create-compute-environment \
  --compute-environment-name vidx-processing-env \
  --type MANAGED \
  --state ENABLED \
  --compute-resources "
  {
    \"type\": \"EC2\",
    \"minvCpus\": 0,
    \"maxvCpus\": 16,
    \"desiredvCpus\": 2,
    \"instanceTypes\": [\"t3.large\", \"t3.xlarge\"],
    \"subnets\": [\"$SUBNET_ID\"],
    \"securityGroupIds\": [\"$SG_ID\"],
    \"instanceRole\": \"arn:aws:iam::000000000000:instance-profile/vidx-batch-instance-profile\"
  }
  " \
  2>/dev/null || echo "Compute environment already exists"

# Create Batch job queue
echo "[LocalStack Init] Creating Batch job queue..."
awslocal batch create-job-queue \
  --job-queue-name vidx-processing-queue \
  --state ENABLED \
  --priority 100 \
  --compute-environment-order "order=1,computeEnvironment=vidx-processing-env" \
  2>/dev/null || echo "Job queue already exists"

# Register Batch job definition
echo "[LocalStack Init] Registering Batch job definition..."
awslocal batch register-job-definition \
  --job-definition-name vidx-video-merge \
  --type container \
  --container-properties '{
    "image": "vidx-backend:latest",
    "vcpus": 2,
    "memory": 8192,
    "jobRoleArn": "arn:aws:iam::000000000000:role/vidx-batch-task-role",
    "environment": [
      {"name": "S3_BUCKET", "value": "vidx-video-storage"},
      {"name": "AWS_REGION", "value": "us-east-1"}
    ]
  }' \
  2>/dev/null || echo "Job definition already exists"

echo "[LocalStack Init] ✓ Resource initialization complete!"
echo ""
echo "Created resources:"
echo "  - S3 bucket: vidx-video-storage"
echo "  - SQS queue: vidx-processing"
echo "  - DynamoDB table: vidx-cache"
echo "  - ECR repos: vidx-backend, vidx-frontend"
echo "  - Secrets Manager: vidx/config"
echo "  - AWS Batch:"
echo "    - Compute Environment: vidx-processing-env"
echo "    - Job Queue: vidx-processing-queue"
echo "    - Job Definition: vidx-video-merge"

