/* AWS DynamoDB and ElastiCache resources for VIDX.

This module defines the database and cache infrastructure for VIDX,
supporting both local development (LocalStack) and AWS production. */

# ============================================================================
# DynamoDB Table
# ============================================================================

resource "aws_dynamodb_table" "vidx_items" {
  name         = var.dynamodb_table_name
  billing_mode = "PAY_PER_REQUEST" # On-demand pricing (good for variable workloads)
  hash_key     = "id"

  attribute {
    name = "id"
    type = "S" # String
  }

  # Enable point-in-time recovery for production
  point_in_time_recovery {
    enabled = var.environment != "dev"
  }

  # Enable encryption at rest
  server_side_encryption {
    enabled     = true
    kms_key_arn = var.use_localstack ? null : aws_kms_key.dynamodb[0].arn
  }

  # Enable TTL for automatic cleanup
  ttl {
    attribute_name = "expires_at"
    enabled        = true
  }

  tags = {
    Name        = "${var.project_name}-dynamodb-items"
    Environment = var.environment
  }
}

# Optional: Global Secondary Indexes for queries
resource "aws_dynamodb_table" "vidx_items_gsi" {
  count      = var.enable_dynamodb_gsi ? 1 : 0
  depends_on = [aws_dynamodb_table.vidx_items]

  name         = "${var.dynamodb_table_name}-gsi"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "type"
  range_key    = "created_at"

  attribute {
    name = "type"
    type = "S"
  }

  attribute {
    name = "created_at"
    type = "S"
  }

  tags = {
    Name        = "${var.project_name}-dynamodb-gsi"
    Environment = var.environment
  }
}

# ============================================================================
# ElastiCache Redis Cluster
# ============================================================================

# Security group for ElastiCache
resource "aws_security_group" "elasticache" {
  name_prefix = "${var.project_name}-elasticache-"
  vpc_id      = aws_vpc.main.id

  # Allow inbound Redis connections from application security group
  ingress {
    from_port   = 6379
    to_port     = 6379
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # In production, restrict to app security group
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "${var.project_name}-elasticache-sg"
    Environment = var.environment
  }
}

# ElastiCache subnet group
resource "aws_elasticache_subnet_group" "vidx" {
  count      = var.use_localstack ? 0 : 1
  name       = "${var.project_name}-subnet-group"
  subnet_ids = aws_subnet.private[*].id

  tags = {
    Name        = "${var.project_name}-elasticache-subnet-group"
    Environment = var.environment
  }
}

# ElastiCache Redis cluster
resource "aws_elasticache_replication_group" "vidx" {
  count                      = var.enable_elasticache ? 1 : 0
  replication_group_id       = "${var.project_name}-redis"
  description                = "Redis replication group for ${var.project_name}"
  engine                     = "redis"
  engine_version             = var.elasticache_engine_version
  node_type                  = var.elasticache_node_type
  num_cache_clusters         = var.elasticache_num_nodes
  parameter_group_name       = aws_elasticache_parameter_group.vidx[0].name
  port                       = 6379
  subnet_group_name          = var.use_localstack ? null : aws_elasticache_subnet_group.vidx[0].name
  security_group_ids         = [aws_security_group.elasticache.id]
  automatic_failover_enabled = var.elasticache_num_nodes > 1 && !var.use_localstack
  multi_az_enabled           = var.elasticache_num_nodes > 1 && var.environment != "dev"
  transit_encryption_enabled = !var.use_localstack
  at_rest_encryption_enabled = !var.use_localstack
  snapshot_retention_limit   = var.environment == "dev" ? 0 : 7
  snapshot_window            = "03:00-05:00"
  auto_minor_version_upgrade = true
  maintenance_window         = "mon:03:00-mon:04:00"

  log_delivery_configuration {
    destination      = aws_cloudwatch_log_group.elasticache_slow_log[0].name
    destination_type = "cloudwatch-logs"
    log_format       = "json"
    log_type         = "slow-log"
  }

  log_delivery_configuration {
    destination      = aws_cloudwatch_log_group.elasticache_engine_log[0].name
    destination_type = "cloudwatch-logs"
    log_format       = "json"
    log_type         = "engine-log"
  }

  tags = {
    Name        = "${var.project_name}-elasticache"
    Environment = var.environment
  }

  depends_on = [aws_elasticache_parameter_group.vidx]
}

# ElastiCache parameter group for customization
resource "aws_elasticache_parameter_group" "vidx" {
  count  = var.enable_elasticache ? 1 : 0
  name   = "${var.project_name}-redis-params"
  family = "redis7"

  # Redis 7.x performance parameters
  parameter {
    name  = "maxmemory-policy"
    value = "allkeys-lru" # Evict least recently used keys when memory is full
  }

  parameter {
    name  = "timeout"
    value = "300" # Close idle connections after 300 seconds
  }

  parameter {
    name  = "tcp-keepalive"
    value = "60"
  }

  tags = {
    Name        = "${var.project_name}-redis-params"
    Environment = var.environment
  }
}

# CloudWatch log groups for ElastiCache
resource "aws_cloudwatch_log_group" "elasticache_slow_log" {
  count             = var.enable_elasticache ? 1 : 0
  name              = "/aws/elasticache/${var.project_name}/slow-log"
  retention_in_days = var.environment == "dev" ? 3 : 7

  tags = {
    Name        = "${var.project_name}-elasticache-slow-log"
    Environment = var.environment
  }
}

resource "aws_cloudwatch_log_group" "elasticache_engine_log" {
  count             = var.enable_elasticache ? 1 : 0
  name              = "/aws/elasticache/${var.project_name}/engine-log"
  retention_in_days = var.environment == "dev" ? 3 : 7

  tags = {
    Name        = "${var.project_name}-elasticache-engine-log"
    Environment = var.environment
  }
}

# ============================================================================
# KMS Key for DynamoDB Encryption (Production only)
# ============================================================================

resource "aws_kms_key" "dynamodb" {
  count                   = var.use_localstack ? 0 : 1
  description             = "KMS key for DynamoDB encryption"
  deletion_window_in_days = 10
  enable_key_rotation     = true

  tags = {
    Name        = "${var.project_name}-dynamodb-key"
    Environment = var.environment
  }
}

resource "aws_kms_alias" "dynamodb" {
  count         = var.use_localstack ? 0 : 1
  name          = "alias/${var.project_name}-dynamodb"
  target_key_id = aws_kms_key.dynamodb[0].key_id
}

# ============================================================================
# Outputs
# ============================================================================

output "dynamodb_table_name" {
  description = "DynamoDB table name for video items"
  value       = aws_dynamodb_table.vidx_items.name
}

output "dynamodb_table_arn" {
  description = "DynamoDB table ARN"
  value       = aws_dynamodb_table.vidx_items.arn
}

output "elasticache_endpoint" {
  description = "ElastiCache Redis primary endpoint"
  value       = var.enable_elasticache ? aws_elasticache_replication_group.vidx[0].primary_endpoint_address : null
}

output "elasticache_port" {
  description = "ElastiCache Redis port"
  value       = var.enable_elasticache ? aws_elasticache_replication_group.vidx[0].port : 6379
}

output "elasticache_cluster_id" {
  description = "ElastiCache cluster ID"
  value       = var.enable_elasticache ? aws_elasticache_replication_group.vidx[0].id : null
}
