output "vpc_id" {
  value       = aws_vpc.main_vpc.id # This must match the resource name in your main.tf
  description = "The ID of the VPC"
}