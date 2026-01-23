# LocalStack configuration for local testing
# To use: terraform apply -var-file=terraform.localstack.tfvars

aws_region = "us-east-1"
environment = "localstack"
project_name = "vidx"

# VPC Configuration
vpc_cidr = "10.0.0.0/16"
private_subnet_cidrs = ["10.0.1.0/24", "10.0.2.0/24"]
public_subnet_cidrs = ["10.0.101.0/24", "10.0.102.0/24"]

# EKS Configuration
eks_version = "1.29"
node_group_instance_types = ["t3.medium"]
node_group_desired_size = 2
node_group_min_size = 1
node_group_max_size = 3
node_group_disk_size = 50
node_group_capacity_type = "ON_DEMAND"

# S3 Configuration
s3_video_bucket_name = "vidx-video-storage"
s3_enable_versioning = true
s3_enable_server_side_encryption = false
s3_enable_public_access_block = false

# AWS Batch Configuration (for local testing)
batch_enabled = true
batch_compute_type = "EC2"
batch_allocation_strategy = "BEST_FIT"
batch_min_vcpus = 0
batch_max_vcpus = 16
batch_desired_vcpus = 2
batch_instance_types = ["t3.large", "t3.xlarge"]
batch_spot_bid_percentage = 0
batch_default_vcpus = 2
batch_default_memory = 8192
batch_job_queue = "vidx-processing-queue-localstack"
batch_job_definition = "vidx-video-merge-localstack"
batch_job_image = "vidx:latest"
s3_bucket = "vidx-video-storage"

# LocalStack
use_localstack = true

