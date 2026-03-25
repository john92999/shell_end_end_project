# EKS Control Plane
resource "aws_eks_cluster""main" {
  name     = "${var.env}-eks"
  role_arn = var.eks_cluster_role_arn
  version  = "1.29"

  vpc_config {
    subnet_ids              = var.private_subnet_ids
    endpoint_private_access = true    # API server accessible from within VPC
    endpoint_public_access  = false   # NO public access to k8s API server
    security_group_ids      = [var.app_sg_id]
  }

  # Enable CloudWatch logging for audit, authenticator, and API server
  enabled_cluster_log_types = ["api","audit","authenticator","controllerManager","scheduler"]

  encryption_config {
    provider { key_arn = var.kms_key_arn }
    resources = ["secrets"]    # encrypt Kubernetes secrets in etcd
  }
}

# Managed Node Group — AWS handles node patching and replacement
resource "aws_eks_node_group""app" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "${var.env}-app-nodes"
  node_role_arn   = var.eks_node_role_arn
  subnet_ids      = var.private_subnet_ids
  instance_types  = ["t3.medium"]

  scaling_config {
    desired_size = 2
    min_size     = 2
    max_size     = 6
  }

  # Rolling update — replaces one node at a time
  update_config { max_unavailable = 1 }

  labels = { role = "app" }
}

# OIDC Provider — required for IRSA
data "tls_certificate""eks" {
  url = aws_eks_cluster.main.identity[0].oidc[0].issuer
}
resource "aws_iam_openid_connect_provider""eks" {
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.eks.certificates[0].sha1_fingerprint]
  url             = aws_eks_cluster.main.identity[0].oidc[0].issuer
}
