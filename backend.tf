terraform {
    backend "s3" {
    key = "terraform.tfstate"
    bucket = "statefilebucket-pjwesley7"
    region = "ap-south-1"
    encrypt = true
    }
}

resource "aws_s3_bucket" "statefilebucket" {
  bucket = "statefilebucket-pjwesley7"
  force_destroy = true
}