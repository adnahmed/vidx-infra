terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.30"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.27"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.13"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }

  # Uncomment and update for production remote state management
  # backend "s3" {
  #   bucket         = "vidx-terraform-state"
  #   key            = "prod/terraform.tfstate"
  #   region         = "us-east-1"
  #   encrypt        = true
  #   dynamodb_table = "terraform-state-lock"
  # }

  backend "local" {
    path = "terraform.tfstate"
  }
}

provider "aws" {
  region = var.aws_region

  # Support for LocalStack local development using best practices
  # Reference: https://docs.localstack.cloud/aws/integrations/infrastructure-as-code/terraform/
  skip_credentials_validation = var.use_localstack
  skip_metadata_api_check     = var.use_localstack
  skip_requesting_account_id  = var.use_localstack
  s3_use_path_style           = var.use_localstack

  # LocalStack endpoint configuration
  # All services route through http://localhost:4566 when use_localstack=true
  dynamic "endpoints" {
    for_each = var.use_localstack ? [1] : []
    content {
      # Core AWS services
      sts = "http://localhost:4566"
      ec2 = "http://localhost:4566"
      iam = "http://localhost:4566"

      # Container services
      ecr = "http://localhost:4566"
      eks = "http://localhost:4566"
      ecs = "http://localhost:4566"

      # Storage services
      s3        = "http://localhost:4566"
      s3control = "http://localhost:4566"

      # Database services
      rds      = "http://localhost:4566"
      dynamodb = "http://localhost:4566"

      # Cache service (ElastiCache)
      elasticache = "http://localhost:4566"

      # Monitoring and logging
      cloudwatch = "http://localhost:4566"
      logs       = "http://localhost:4566"

      # Load balancing and auto scaling
      elbv2       = "http://localhost:4566"
      elb         = "http://localhost:4566"
      autoscaling = "http://localhost:4566"

      # Security and encryption
      secretsmanager = "http://localhost:4566"
      kms            = "http://localhost:4566"
      acm            = "http://localhost:4566"

      # Messaging and functions
      lambda = "http://localhost:4566"
      sqs    = "http://localhost:4566"
      sns    = "http://localhost:4566"

      # Infrastructure as Code
      cloudformation = "http://localhost:4566"

      # DNS
      route53 = "http://localhost:4566"

      # Additional services for comprehensive coverage
      kinesis      = "http://localhost:4566"
      firehose     = "http://localhost:4566"
      apigateway   = "http://localhost:4566"
      apigatewayv2 = "http://localhost:4566"
      cloudtrail   = "http://localhost:4566"
      config       = "http://localhost:4566"
      events       = "http://localhost:4566"
      xray         = "http://localhost:4566"
    }
  }

  default_tags {
    tags = {
      Terraform   = "true"
      Environment = var.environment
      Project     = "vidx-infra"
      ManagedBy   = "terraform"
      CreatedAt   = timestamp()
    }
  }
}

provider "kubernetes" {
  host                   = data.aws_eks_cluster.cluster.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.cluster.certificate_authority[0].data)
  token                  = data.aws_eks_cluster_auth.cluster.token
}

provider "helm" {
  kubernetes {
    host                   = data.aws_eks_cluster.cluster.endpoint
    cluster_ca_certificate = base64decode(data.aws_eks_cluster.cluster.certificate_authority[0].data)
    token                  = data.aws_eks_cluster_auth.cluster.token
  }
}

data "aws_eks_cluster" "cluster" {
  name = aws_eks_cluster.main.name

  depends_on = [aws_eks_cluster.main]
}

data "aws_eks_cluster_auth" "cluster" {
  name = aws_eks_cluster.main.name

  depends_on = [aws_eks_cluster.main]
}

data "aws_availability_zones" "available" {
  state = "available"
}
