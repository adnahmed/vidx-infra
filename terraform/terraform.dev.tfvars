# Terraform development configuration
# Use this for local development and testing

aws_region = "us-east-1"
environment = "development"
project_name = "vidx"

# VPC Configuration
vpc_cidr = "10.0.0.0/16"
private_subnet_cidrs = ["10.0.1.0/24", "10.0.2.0/24"]
public_subnet_cidrs = ["10.0.101.0/24", "10.0.102.0/24"]

# EKS Configuration
eks_version = "1.29"
node_group_instance_types = ["t3.large"]
node_group_desired_size = 2
node_group_min_size = 1
node_group_max_size = 5
node_group_disk_size = 50
node_group_capacity_type = "SPOT"

# S3 Configuration
s3_video_bucket_name = "vidx-video-storage"
s3_enable_versioning = true
s3_enable_server_side_encryption = true
s3_enable_public_access_block = true

# LocalStack
use_localstack = false
