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
      type = "s"
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