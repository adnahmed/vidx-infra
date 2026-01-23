# Terraform Module
module "eks" {
  source = "./"

  aws_region  = var.aws_region
  environment = var.environment
  project_name = var.project_name
  use_localstack = var.use_localstack

  # VPC
  vpc_cidr = var.vpc_cidr
  private_subnet_cidrs = var.private_subnet_cidrs
  public_subnet_cidrs = var.public_subnet_cidrs

  # EKS
  eks_version = var.eks_version
  node_group_instance_types = var.node_group_instance_types
  node_group_desired_size = var.node_group_desired_size
  node_group_min_size = var.node_group_min_size
  node_group_max_size = var.node_group_max_size
  node_group_disk_size = var.node_group_disk_size
  node_group_capacity_type = var.node_group_capacity_type

  # S3
  s3_video_bucket_name = var.s3_video_bucket_name
  s3_enable_versioning = var.s3_enable_versioning
  s3_enable_server_side_encryption = var.s3_enable_server_side_encryption
  s3_enable_public_access_block = var.s3_enable_public_access_block
}
