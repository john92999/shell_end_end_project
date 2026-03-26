resource "aws_s3_bucket" "statefilebucket" {
    bucket = "statefilebucket-pjwesley7"
    region = "ap-south-1"
}

resource "aws_s3_bucket_versioning" "versioning" {
    bucket = aws_s3_bucket.statefilebucket.id
    versioning_configuration {
        status = "Enabled"
    }
}

resource "aws_s3_bucket_server_side_encryption_configuration""enc"{
    bucket = aws_s3_bucket.statefilebucket.id
    rule {
      apply_server_side_encryption_by_default{
        sse_algorithm = "aws:kms"
      }
    }
}

resource "aws_s3_bucket_public_access_block""block"{
    bucket = aws_s3_bucket.statefilebucket.id
    block_public_acls = true
    block_public_policy = true
    ignore_public_acls = true
    restrict_public_buckets = true
}

resource "aws_dynamodb_table""tf_lock"{
    name = "terraform-state-lock"
    billing_mode = "PAY_PER_REQUEST"
    hash_key = "LockID"
    attribute {
      name = "LockID"
      type = "S"
    }
    tags = {
        Name = "terraform-lock"
    }
}   

resource "aws_vpc" "main_vpc" {
    cidr_block = "10.0.0.0/16"
    tags = {
        Name = "main_vpc"
    }
}

resource "aws_subnet" "public_1" {
    vpc_id = aws_vpc.main_vpc.id
    cidr_block = "10.0.1.0/24"
    availability_zone = "ap-south-1a"
    tags = {
       Name = "public-subnet-1"
    }
}

resource "aws_subnet" "public_2" {
    vpc_id = aws_vpc.main_vpc.id
    cidr_block = "10.0.2.0/24"
    availability_zone = "ap-south-1b"
    tags = {
        Name = "public-subnet-2"
    }
}


module "vpc" {
  source = "./modules/vpc"

  environment        = var.environment
  vpc_cidr           = var.vpc_cidr
  public_cidrs       = var.public_cidrs
  private_cidrs      = var.private_cidrs
  data_cidrs         = var.data_cidrs
  availability_zones = var.availability_zones
}

module "iam" {
  source = "./modules/iam"
  environment = var.environment
}

module "security" {
  source = "./modules/security"

  environment      = var.environment
  vpc_id           = module.vpc.vpc_id         # the VPC these security groups belong to
  docdb_password   = var.docdb_password        # stored in Secrets Manager (not in code)
  redis_auth_token = var.redis_auth_token      # stored in Secrets Manager
}


module "ecr" {
  source = "./modules/ecr"

  environment = var.environment
}

module "docdb" {
  source = "./modules/docdb"

  environment      = var.environment
  data_subnet_ids  = module.vpc.data_subnet_ids     # place DB in data subnets (most isolated)
  db_sg_id         = module.security.db_sg_id       # only app can talk to DB
  kms_key_arn      = module.security.kms_key_arn    # encrypt DB data
  docdb_password   = var.docdb_password
}

module "elasticache" {
  source = "./modules/elasticache"

  environment      = var.environment
  data_subnet_ids  = module.vpc.data_subnet_ids     # place Redis in data subnets
  redis_sg_id      = module.security.redis_sg_id   # only app can talk to Redis
  kms_key_arn      = module.security.kms_key_arn    # encrypt cache data
  redis_auth_token = var.redis_auth_token
}

module "msk" {
  source = "./modules/msk"

  environment     = var.environment
  data_subnet_ids = module.vpc.data_subnet_ids     # place Kafka in data subnets
  msk_sg_id       = module.security.msk_sg_id     # only app can talk to Kafka
  kms_key_arn     = module.security.kms_key_arn   # encrypt messages
}

module "alb" {
  source = "./modules/alb"

  environment       = var.environment
  vpc_id            = module.vpc.vpc_id
  public_subnet_ids = module.vpc.public_subnet_ids  # ALB must be in public subnets
  alb_sg_id         = module.security.alb_sg_id     # allows 80/443 from internet
  waf_acl_arn       = module.security.waf_acl_arn   # attach WAF to ALB
}

module "ec2" {
  source = "./modules/ec2"

  environment          = var.environment
  private_subnet_ids   = module.vpc.private_subnet_ids  # EC2 in private subnets
  app_sg_id            = module.security.app_sg_id      # only ALB can reach EC2
  ec2_instance_profile = module.iam.ec2_instance_profile_name
  api_target_group_arn = module.alb.api_target_group_arn  # ALB health-checks EC2 here
  kms_key_arn          = module.security.kms_key_arn       # encrypt EBS volumes
  instance_type        = var.api_instance_type
  ecr_api_url          = module.ecr.todo_api_url           # pull Docker image from ECR
  docdb_endpoint       = module.docdb.cluster_endpoint     # pass DB address to app
  redis_endpoint       = module.elasticache.redis_endpoint # pass Redis address to app
  msk_brokers          = module.msk.bootstrap_brokers      # pass Kafka brokers to app
  secrets_arn          = module.security.docdb_secret_arn  # ARN of the DB credentials secret
}

module "eks" {
  source = "./modules/eks"

  environment          = var.environment
  private_subnet_ids   = module.vpc.private_subnet_ids  # nodes in private subnets
  eks_cluster_role_arn = module.iam.eks_cluster_role_arn
  eks_node_role_arn    = module.iam.eks_node_role_arn
  app_sg_id            = module.security.app_sg_id
  kms_key_arn          = module.security.kms_key_arn    # encrypt Kubernetes secrets
  node_instance_type   = var.eks_node_instance_type
}
