variable "aws_region" {
  description = "AWS region to deploy resources"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "production"

  validation {
    condition     = contains(["development", "staging", "production"], var.environment)
    error_message = "Environment must be development, staging, or production."
  }
}

variable "project_name" {
  description = "Project name"
  type        = string
  default     = "vidx"
}

variable "use_localstack" {
  description = "Use LocalStack for local testing instead of real AWS"
  type        = bool
  default     = false
}

# VPC Variables
variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets"
  type        = list(string)
  default     = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]
}

# EKS Variables
variable "eks_version" {
  description = "EKS cluster Kubernetes version"
  type        = string
  default     = "1.29"
}

variable "eks_endpoint_private_access" {
  description = "Enable private API endpoint"
  type        = bool
  default     = true
}

variable "eks_endpoint_public_access" {
  description = "Enable public API endpoint"
  type        = bool
  default     = true
}

variable "eks_endpoint_public_access_cidrs" {
  description = "List of CIDR blocks that can access the public API endpoint"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "node_group_name" {
  description = "EKS managed node group name"
  type        = string
  default     = "vidx-node-group"
}

variable "node_group_instance_types" {
  description = "EC2 instance types for node group"
  type        = list(string)
  default     = ["t3.xlarge"]
}

variable "node_group_desired_size" {
  description = "Desired number of nodes"
  type        = number
  default     = 3

  validation {
    condition     = var.node_group_desired_size >= 1 && var.node_group_desired_size <= 100
    error_message = "Desired size must be between 1 and 100."
  }
}

variable "node_group_min_size" {
  description = "Minimum number of nodes"
  type        = number
  default     = 2

  validation {
    condition     = var.node_group_min_size >= 1 && var.node_group_min_size <= 100
    error_message = "Min size must be between 1 and 100."
  }
}

variable "node_group_max_size" {
  description = "Maximum number of nodes"
  type        = number
  default     = 10

  validation {
    condition     = var.node_group_max_size >= 1 && var.node_group_max_size <= 100
    error_message = "Max size must be between 1 and 100."
  }
}

variable "node_group_disk_size" {
  description = "EBS volume size for nodes (GB)"
  type        = number
  default     = 100
}

variable "node_group_capacity_type" {
  description = "Capacity type for nodes (ON_DEMAND or SPOT)"
  type        = string
  default     = "ON_DEMAND"

  validation {
    condition     = contains(["ON_DEMAND", "SPOT"], var.node_group_capacity_type)
    error_message = "Capacity type must be ON_DEMAND or SPOT."
  }
}

# GPU Node Group Variables
variable "gpu_node_group_enabled" {
  description = "Enable a dedicated GPU node group"
  type        = bool
  default     = true
}

variable "gpu_node_group_name" {
  description = "GPU EKS managed node group name"
  type        = string
  default     = "vidx-gpu-node-group"
}

variable "gpu_instance_types" {
  description = "EC2 instance types for GPU node group"
  type        = list(string)
  default     = ["g4dn.xlarge"]
}

variable "gpu_node_desired_size" {
  description = "Desired number of GPU nodes"
  type        = number
  default     = 1
}

variable "gpu_node_min_size" {
  description = "Minimum number of GPU nodes"
  type        = number
  default     = 0
}

variable "gpu_node_max_size" {
  description = "Maximum number of GPU nodes"
  type        = number
  default     = 3
}

variable "gpu_node_disk_size" {
  description = "EBS volume size for GPU nodes (GB)"
  type        = number
  default     = 200
}

# SQS Variables
variable "sqs_queue_name" {
  description = "Name of the SQS queue for video processing"
  type        = string
  default     = "vidx-processing"
}
variable "sqs_visibility_timeout" {
  description = "SQS visibility timeout in seconds"
  type        = number
  default     = 300
}
variable "sqs_message_retention_seconds" {
  description = "SQS message retention in seconds"
  type        = number
  default     = 1209600 # 14 days
}

# S3 Variables
variable "s3_video_bucket_name" {
  description = "S3 bucket name for video storage"
  type        = string
  default     = "vidx-video-storage"
}

variable "s3_enable_versioning" {
  description = "Enable S3 versioning"
  type        = bool
  default     = true
}

variable "s3_enable_server_side_encryption" {
  description = "Enable S3 server-side encryption"
  type        = bool
  default     = true
}

variable "s3_enable_mfa_delete" {
  description = "Enable MFA delete (requires versioning)"
  type        = bool
  default     = false
}

variable "s3_lifecycle_expiration_days" {
  description = "Number of days before S3 objects expire"
  type        = number
  default     = 365
}

variable "s3_enable_public_access_block" {
  description = "Block all public access to S3 bucket"
  type        = bool
  default     = true
}

# DynamoDB Variables
variable "dynamodb_table_name" {
  description = "DynamoDB table name for video items"
  type        = string
  default     = "vidx-items"
}

variable "enable_dynamodb_gsi" {
  description = "Enable DynamoDB Global Secondary Indexes"
  type        = bool
  default     = false
}

variable "dynamodb_billing_mode" {
  description = "DynamoDB billing mode (PAY_PER_REQUEST or PROVISIONED)"
  type        = string
  default     = "PAY_PER_REQUEST"

  validation {
    condition     = contains(["PAY_PER_REQUEST", "PROVISIONED"], var.dynamodb_billing_mode)
    error_message = "Must be either PAY_PER_REQUEST or PROVISIONED"
  }
}

# ElastiCache Variables
variable "enable_elasticache" {
  description = "Enable ElastiCache Redis cluster"
  type        = bool
  default     = true
}

variable "elasticache_node_type" {
  description = "ElastiCache node type (e.g., cache.t3.micro, cache.t3.small)"
  type        = string
  default     = "cache.t3.micro"  # Use cache.t4g.micro for ARM64 (cheaper)
}

variable "elasticache_num_nodes" {
  description = "Number of cache nodes (1 for dev, 3+ for production multi-AZ)"
  type        = number
  default     = 1

  validation {
    condition     = var.elasticache_num_nodes >= 1 && var.elasticache_num_nodes <= 100
    error_message = "Must be between 1 and 100 nodes"
  }
}

variable "elasticache_engine_version" {
  description = "Redis engine version"
  type        = string
  default     = "7.0"
}

variable "elasticache_port" {
  description = "ElastiCache port"
  type        = number
  default     = 6379
}

# Tags
variable "tags" {
  description = "Common tags to apply to resources"
  type        = map(string)
  default = {
    Terraform   = "true"
    Environment = "production"
    Project     = "vidx"
  }
}
