# Terraform production configuration
# Use this for production deployments

aws_region = "us-east-1"
environment = "production"
project_name = "vidx"

# VPC Configuration
vpc_cidr = "10.0.0.0/16"
private_subnet_cidrs = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
public_subnet_cidrs = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]

# EKS Configuration
eks_version = "1.29"
node_group_instance_types = ["t3.xlarge"]
node_group_desired_size = 3
node_group_min_size = 2
node_group_max_size = 10
node_group_disk_size = 100
node_group_capacity_type = "ON_DEMAND"

# S3 Configuration
s3_video_bucket_name = "vidx-video-storage"
s3_enable_versioning = true
s3_enable_server_side_encryption = true
s3_enable_mfa_delete = false
s3_lifecycle_expiration_days = 365
s3_enable_public_access_block = true

# API Access
eks_endpoint_public_access_cidrs = ["0.0.0.0/0"]

# AWS Batch Configuration (for video processing)
batch_enabled = true
batch_compute_type = "SPOT"
batch_allocation_strategy = "SPOT_CAPACITY_OPTIMIZED"
batch_min_vcpus = 0
batch_max_vcpus = 256
batch_desired_vcpus = 4
batch_instance_types = ["vt1.3xlarge", "c5.4xlarge", "c5a.4xlarge", "m5.4xlarge"]
batch_spot_bid_percentage = 70
batch_default_vcpus = 4
batch_default_memory = 16384
batch_job_queue = "vidx-processing-queue-prod"
batch_job_definition = "vidx-video-merge-prod"
batch_job_image = "vidx:latest"
s3_bucket = "vidx-video-storage"

# LocalStack
use_localstack = false

