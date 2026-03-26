# ─────────────────────────────────────────────────────────────────
# main.tf  (ROOT)
#
# FIX APPLIED: Removed stale inline resources that were left over
# from the original learning exercise:
#   REMOVED: aws_s3_bucket (had invalid "region" argument → crash)
#   REMOVED: aws_s3_bucket_versioning
#   REMOVED: aws_s3_bucket_server_side_encryption_configuration
#   REMOVED: aws_s3_bucket_public_access_block
#   REMOVED: aws_dynamodb_table
#   REMOVED: aws_vpc.main_vpc     (duplicate of vpc module)
#   REMOVED: aws_subnet.public_1  (duplicate of vpc module)
#   REMOVED: aws_subnet.public_2  (duplicate of vpc module)
#
# WHY? aws_s3_bucket does NOT accept a "region" argument — Terraform
# would crash. The S3/DynamoDB bootstrap belongs in bootstrap/main.tf
# and is run ONCE separately before this project.
#
# This file now ONLY contains module calls.
# ─────────────────────────────────────────────────────────────────

module "vpc" {
  source             = "./modules/vpc"
  environment        = var.environment
  vpc_cidr           = var.vpc_cidr
  public_cidrs       = var.public_cidrs
  private_cidrs      = var.private_cidrs
  data_cidrs         = var.data_cidrs
  availability_zones = var.availability_zones
}

module "iam" {
  source      = "./modules/iam"
  environment = var.environment
}

module "security" {
  source           = "./modules/security"
  environment      = var.environment
  vpc_id           = module.vpc.vpc_id
  docdb_password   = var.docdb_password
  redis_auth_token = var.redis_auth_token
}

module "ecr" {
  source      = "./modules/ecr"
  environment = var.environment
}

module "docdb" {
  source          = "./modules/docdb"
  environment     = var.environment
  data_subnet_ids = module.vpc.data_subnet_ids
  db_sg_id        = module.security.db_sg_id
  kms_key_arn     = module.security.kms_key_arn
  docdb_password  = var.docdb_password
}

module "elasticache" {
  source           = "./modules/elasticache"
  environment      = var.environment
  data_subnet_ids  = module.vpc.data_subnet_ids
  redis_sg_id      = module.security.redis_sg_id
  kms_key_arn      = module.security.kms_key_arn
  redis_auth_token = var.redis_auth_token
}

module "msk" {
  source          = "./modules/msk"
  environment     = var.environment
  data_subnet_ids = module.vpc.data_subnet_ids
  msk_sg_id       = module.security.msk_sg_id
  kms_key_arn     = module.security.kms_key_arn
}

module "alb" {
  source            = "./modules/alb"
  environment       = var.environment
  vpc_id            = module.vpc.vpc_id
  public_subnet_ids = module.vpc.public_subnet_ids
  alb_sg_id         = module.security.alb_sg_id
  waf_acl_arn       = module.security.waf_acl_arn
}

module "ec2" {
  source               = "./modules/ec2"
  environment          = var.environment
  private_subnet_ids   = module.vpc.private_subnet_ids
  app_sg_id            = module.security.app_sg_id
  ec2_instance_profile = module.iam.ec2_instance_profile_name
  api_target_group_arn = module.alb.api_target_group_arn
  kms_key_arn          = module.security.kms_key_arn
  instance_type        = var.api_instance_type
  ecr_api_url          = module.ecr.todo_api_url
  docdb_endpoint       = module.docdb.cluster_endpoint
  redis_endpoint       = module.elasticache.redis_endpoint
  msk_brokers          = module.msk.bootstrap_brokers
  secrets_arn          = module.security.docdb_secret_arn
  redis_secret_arn     = module.security.redis_secret_arn
}

module "eks" {
  source               = "./modules/eks"
  environment          = var.environment
  private_subnet_ids   = module.vpc.private_subnet_ids
  eks_cluster_role_arn = module.iam.eks_cluster_role_arn
  eks_node_role_arn    = module.iam.eks_node_role_arn
  app_sg_id            = module.security.app_sg_id
  kms_key_arn          = module.security.kms_key_arn
  node_instance_type   = var.eks_node_instance_type
}
