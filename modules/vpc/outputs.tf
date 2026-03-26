# modules/vpc/outputs.tf
# Values this module exposes to the caller (main.tf)
# Other modules read these outputs — e.g. security module needs vpc_id

output "vpc_id" {
  description = "The ID of the VPC. All other modules need this to attach to the network."
  value       = aws_vpc.main.id
}

output "public_subnet_ids" {
  description = "IDs of the public subnets. ALB goes here."
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "IDs of the private subnets. EKS nodes and EC2 go here."
  value       = aws_subnet.private[*].id
}

output "data_subnet_ids" {
  description = "IDs of the data subnets. DocumentDB, Redis, MSK go here."
  value       = aws_subnet.data[*].id
}
