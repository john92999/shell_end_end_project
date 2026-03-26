# modules/eks/variables.tf

variable "environment" {
  type        = string
  description = "Environment name (dev, prod)"
}

variable "private_subnet_ids" {
  type        = list(string)
  description = "Private subnet IDs. EKS nodes run here — not accessible from internet."
}

variable "eks_cluster_role_arn" {
  type        = string
  description = "IAM role ARN for EKS control plane. Allows EKS to manage AWS resources."
}

variable "eks_node_role_arn" {
  type        = string
  description = "IAM role ARN for EKS worker nodes. Allows nodes to register and pull images."
}

variable "app_sg_id" {
  type        = string
  description = "Security group for the cluster. Allows traffic from ALB only."
}

variable "kms_key_arn" {
  type        = string
  description = "KMS key ARN for encrypting Kubernetes secrets stored in etcd."
}

variable "node_instance_type" {
  type        = string
  description = "EC2 instance type for EKS worker nodes. t3.medium for dev, m5.large for prod."
  default     = "t3.medium"
}
