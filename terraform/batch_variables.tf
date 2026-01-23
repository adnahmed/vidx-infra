# AWS Batch Configuration Variables

variable "batch_enabled" {
  description = "Enable AWS Batch for video processing"
  type        = bool
  default     = true
}

variable "batch_compute_type" {
  description = "Batch compute type - EC2 or SPOT"
  type        = string
  default     = "SPOT"
  validation {
    condition     = contains(["EC2", "SPOT"], var.batch_compute_type)
    error_message = "Batch compute type must be EC2 or SPOT"
  }
}

variable "batch_allocation_strategy" {
  description = "Batch allocation strategy"
  type        = string
  default     = "SPOT_CAPACITY_OPTIMIZED"
  validation {
    condition     = contains(["SPOT_CAPACITY_OPTIMIZED", "BEST_FIT", "BEST_FIT_PROGRESSIVE", "SPOT_PRICE_CAPACITY_OPTIMIZED"], var.batch_allocation_strategy)
    error_message = "Invalid batch allocation strategy"
  }
}

variable "batch_min_vcpus" {
  description = "Minimum vCPUs in compute environment"
  type        = number
  default     = 0
}

variable "batch_max_vcpus" {
  description = "Maximum vCPUs in compute environment"
  type        = number
  default     = 256
}

variable "batch_desired_vcpus" {
  description = "Desired vCPUs in compute environment"
  type        = number
  default     = 4
}

variable "batch_instance_types" {
  description = "EC2 instance types for Batch (VT1 for video, C5 for general)"
  type        = list(string)
  default     = ["vt1.3xlarge", "c5.4xlarge", "c5a.4xlarge", "m5.4xlarge"]
}

variable "batch_spot_bid_percentage" {
  description = "Bid percentage for Spot instances (0-100)"
  type        = number
  default     = 70
}

variable "batch_default_vcpus" {
  description = "Default vCPUs for batch jobs"
  type        = number
  default     = 4
}

variable "batch_default_memory" {
  description = "Default memory (MB) for batch jobs"
  type        = number
  default     = 16384
}

variable "batch_job_image" {
  description = "Docker image URI for batch jobs (e.g., {ACCOUNT}.dkr.ecr.{REGION}.amazonaws.com/vidx:latest)"
  type        = string
  default     = "vidx:latest"
}

variable "batch_job_queue" {
  description = "AWS Batch job queue name"
  type        = string
  default     = "vidx-processing-queue"
}

variable "batch_job_definition" {
  description = "AWS Batch job definition name"
  type        = string
  default     = "vidx-video-merge"
}

variable "s3_bucket" {
  description = "S3 bucket for video storage and outputs"
  type        = string
  default     = "vidx-video-storage"
}

variable "log_retention_days" {
  description = "CloudWatch log retention in days"
  type        = number
  default     = 30
}
