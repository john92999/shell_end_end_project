# modules/vpc/variables.tf
# All inputs this module needs from the caller (main.tf)

variable "environment" {
  type        = string
  description = "Environment name used as prefix in resource names (dev, prod)"
}

variable "vpc_cidr" {
  type        = string
  description = "IP address range for the VPC. e.g. 10.0.0.0/16"
}

variable "public_cidrs" {
  type        = list(string)
  description = "List of CIDR blocks for public subnets. One per AZ."
}

variable "private_cidrs" {
  type        = list(string)
  description = "List of CIDR blocks for private subnets. One per AZ."
}

variable "data_cidrs" {
  type        = list(string)
  description = "List of CIDR blocks for data subnets (DB/cache/kafka). One per AZ."
}

variable "availability_zones" {
  type        = list(string)
  description = "List of AZ names. e.g. [ap-south-1a, ap-south-1b]"
}
