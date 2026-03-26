# modules/iam/outputs.tf
# Values other modules need from IAM

output "ec2_instance_profile_name" {
  description = "Attach this to the EC2 launch template so the instance has AWS permissions"
  value       = aws_iam_instance_profile.ec2_api.name
}

output "eks_cluster_role_arn" {
  description = "The EKS cluster needs this role ARN to manage AWS resources"
  value       = aws_iam_role.eks_cluster_role.arn
}

output "eks_node_role_arn" {
  description = "EKS worker nodes need this role to register with the cluster and pull images"
  value       = aws_iam_role.eks_node_role.arn
}
