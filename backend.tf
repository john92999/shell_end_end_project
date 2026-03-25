terraform {
    backend "s3" {
    key = "terraform.tfstate"
    bucket = "statefilebucket-pjwesley7"
    region = "ap-south-1"
    dynamodb_table = "terraform-state-lock"
    encrypt = true
    }
}