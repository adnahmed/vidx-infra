"""
AWS Batch Resources for Video Processing

This Terraform configuration creates:
1. IAM role for Batch jobs to assume
2. Batch compute environment (using EC2/VT1 instances)
3. Batch job queue
4. Batch job definition for video merging
"""

# IAM Role for Batch Task Execution
resource "aws_iam_role" "batch_task_role" {
  name = "${var.project_name}-batch-task-role-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "batch.amazonaws.com"
        }
      },
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name        = "${var.project_name}-batch-task-role"
    Environment = var.environment
  }
}

# IAM Policy for Batch Task
resource "aws_iam_role_policy" "batch_task_policy" {
  name = "${var.project_name}-batch-task-policy-${var.environment}"
  role = aws_iam_role.batch_task_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject"
        ]
        Resource = ["${var.s3_video_bucket_arn}/*"]
      },
      {
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken",
          "ecr:BatchGetImage",
          "ecr:GetDownloadUrlForLayer",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "*"
      }
    ]
  })
}

# IAM Instance Profile for EC2
resource "aws_iam_instance_profile" "batch_instance_profile" {
  name = "${var.project_name}-batch-instance-profile-${var.environment}"
  role = aws_iam_role.batch_task_role.name
}

# IAM Role for Batch Service
resource "aws_iam_role" "batch_service_role" {
  name = "${var.project_name}-batch-service-role-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "batch.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "batch_service_policy" {
  role       = aws_iam_role.batch_service_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSBatchServiceRole"
}

# Security Group for Batch
resource "aws_security_group" "batch_sg" {
  name        = "${var.project_name}-batch-sg-${var.environment}"
  description = "Security group for AWS Batch compute environment"
  vpc_id      = var.vpc_id

  ingress {
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 65535
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "${var.project_name}-batch-sg"
    Environment = var.environment
  }
}

# Batch Compute Environment
resource "aws_batch_compute_environment" "video_processing" {
  compute_environment_name = "${var.project_name}-video-processing-${var.environment}"
  type                     = "MANAGED"
  state                    = "ENABLED"
  service_role             = aws_iam_role.batch_service_role.arn

  compute_resources {
    type                = var.batch_compute_type # "EC2" or "SPOT"
    allocationStrategy  = var.batch_allocation_strategy
    minvCpus            = var.batch_min_vcpus
    maxvCpus            = var.batch_max_vcpus
    desiredvCpus        = var.batch_desired_vcpus
    instanceTypes       = var.batch_instance_types
    subnets             = var.private_subnet_ids
    security_group_ids  = [aws_security_group.batch_sg.id]
    instance_role       = aws_iam_instance_profile.batch_instance_profile.arn

    tags = {
      Name        = "${var.project_name}-batch-compute"
      Environment = var.environment
    }

    # Spot configuration for cost optimization
    bid_percentage = var.batch_spot_bid_percentage
  }

  depends_on = [aws_iam_role_policy_attachment.batch_service_policy]

  tags = {
    Name        = "${var.project_name}-compute-env"
    Environment = var.environment
  }
}

# Job Queue
resource "aws_batch_job_queue" "video_processing" {
  name            = "${var.project_name}-processing-queue-${var.environment}"
  state           = "ENABLED"
  priority        = 100
  compute_environment_order {
    order               = 1
    compute_environment = aws_batch_compute_environment.video_processing.arn
  }

  tags = {
    Name        = "${var.project_name}-job-queue"
    Environment = var.environment
  }
}

# CloudWatch Log Group
resource "aws_cloudwatch_log_group" "batch_logs" {
  name              = "/aws/batch/${var.project_name}-${var.environment}"
  retention_in_days = var.log_retention_days

  tags = {
    Name        = "${var.project_name}-batch-logs"
    Environment = var.environment
  }
}

# Job Definition
resource "aws_batch_job_definition" "video_merge" {
  name                  = "${var.project_name}-video-merge-${var.environment}"
  type                  = "container"
  container_properties = jsonencode({
    image      = var.batch_job_image
    vcpus      = var.batch_default_vcpus
    memory     = var.batch_default_memory
    jobRoleArn = aws_iam_role.batch_task_role.arn
    
    # Set working directory
    workingDirectory = "/app/backend"
    
    # Set entrypoint - will check for JOB_ID env var
    entrypoint = ["/bin/bash", "-c"]
    command = ["docker-entrypoint.sh"]
    
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.batch_logs.name
        "awslogs-region"        = var.aws_region
        "awslogs-stream-prefix" = "vidx-merge"
      }
    }
    
    # Environment variables for batch job execution
    environment = [
      {
        name  = "S3_BUCKET"
        value = var.s3_bucket
      },
      {
        name  = "AWS_REGION"
        value = var.aws_region
      },
      {
        name  = "ENVIRONMENT"
        value = var.environment
      },
      {
        name  = "FFMPEG_BINARY"
        value = "/opt/ffmpeg_build/bin/ffmpeg"
      },
      {
        name  = "FFPROBE_BINARY"
        value = "/opt/ffmpeg_build/bin/ffprobe"
      }
    ]
    
    mountPoints = []
    volumes     = []
  })

  tags = {
    Name        = "${var.project_name}-job-definition"
    Environment = var.environment
  }
}

# Outputs
output "batch_job_queue_name" {
  description = "Name of the AWS Batch job queue"
  value       = aws_batch_job_queue.video_processing.name
}

output "batch_job_definition_name" {
  description = "Name of the AWS Batch job definition"
  value       = aws_batch_job_definition.video_merge.name
}

output "batch_compute_environment_arn" {
  description = "ARN of the compute environment"
  value       = aws_batch_compute_environment.video_processing.arn
}
