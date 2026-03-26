# ─────────────────────────────────────────────────────────────────
# modules/iam/main.tf
#
# PURPOSE: Creates IAM Roles — "permission cards" that allow
# AWS services (EC2, EKS) to call other AWS services.
#
# KEY CONCEPT — IAM Role vs Security Group:
#   Security Group = NETWORK firewall (which port/IP can connect)
#   IAM Role       = PERMISSIONS (can this service read S3? Write to Secrets Manager?)
#
# WHY NOT ACCESS KEYS?
#   Access keys are like a username+password hardcoded in code.
#   If someone steals your code (GitHub leak), they get full AWS access.
#   IAM Roles are temporary credentials automatically rotated by AWS.
#   A running EC2 with an IAM role never needs access keys.
#
# IRSA = IAM Role for Service Account
#   In Kubernetes, each pod runs with a "service account" (an identity).
#   IRSA links a Kubernetes service account to an IAM Role.
#   This means ONLY the todo-ui pod gets Secrets Manager access —
#   not every pod on the cluster.
# ─────────────────────────────────────────────────────────────────

# ── EC2 Role — for todo-api servers ───────────────────────────────
# This role is attached to EC2 instances running todo-api.
# It gives them permission to:
#  - Use SSM Session Manager (so you can SSH without opening port 22)
#  - Read Secrets Manager (to fetch DB passwords at startup)
#  - Pull images from ECR (Elastic Container Registry)
resource "aws_iam_role" "ec2_api_role" {
  name = "${var.environment}-ec2-api-role"

  # assume_role_policy = "who is allowed to use this role"
  # Here we say: only the EC2 service can assume this role.
  # IMPORTANT: Use commas (,) not semicolons (;) inside jsonencode blocks.
  # Semicolons in the original code were a syntax error.
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}

# Allow EC2 to use SSM Session Manager — lets you connect to the instance
# without opening port 22 (SSH). Much more secure.
resource "aws_iam_role_policy_attachment" "ec2_ssm" {
  role       = aws_iam_role.ec2_api_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# Allow EC2 to read secrets from Secrets Manager.
# The todo-api needs to fetch the DB password, Redis token, etc. at startup.
resource "aws_iam_role_policy_attachment" "ec2_secrets" {
  role       = aws_iam_role.ec2_api_role.name
  policy_arn = "arn:aws:iam::aws:policy/SecretsManagerReadWrite"
}

# Allow EC2 to pull Docker images from ECR (our private Docker registry).
resource "aws_iam_role_policy_attachment" "ec2_ecr" {
  role       = aws_iam_role.ec2_api_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

# Instance Profile = the "wrapper" that attaches an IAM Role to an EC2 instance.
# You cannot attach an IAM Role directly to EC2 — you must use an Instance Profile.
resource "aws_iam_instance_profile" "ec2_api" {
  name = "${var.environment}-ec2-api-profile"
  role = aws_iam_role.ec2_api_role.name
}

# ── EKS Cluster Role ───────────────────────────────────────────────
# The EKS control plane (the "brain" of Kubernetes, managed by AWS)
# needs this role to manage EC2 nodes, load balancers, etc. on your behalf.
# Think of it as: "AWS's EKS service has permission to act as this role."
resource "aws_iam_role" "eks_cluster_role" {
  name = "${var.environment}-eks-cluster-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "eks.amazonaws.com" }
    }]
  })
}

# AmazonEKSClusterPolicy = the permissions the EKS control plane needs
# (create load balancers, describe EC2 instances, etc.)
resource "aws_iam_role_policy_attachment" "eks_cluster_policy" {
  role       = aws_iam_role.eks_cluster_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

# ── EKS Node Group Role ────────────────────────────────────────────
# Worker nodes are the EC2 instances where your pods actually run.
# They need permissions to:
#  - Register themselves with the EKS cluster (AmazonEKSWorkerNodePolicy)
#  - Set up pod networking (AmazonEKS_CNI_Policy)
#  - Pull Docker images from ECR (AmazonEC2ContainerRegistryReadOnly)
resource "aws_iam_role" "eks_node_role" {
  name = "${var.environment}-eks-node-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "node_worker" {
  role       = aws_iam_role.eks_node_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_role_policy_attachment" "node_cni" {
  role       = aws_iam_role.eks_node_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

resource "aws_iam_role_policy_attachment" "node_ecr" {
  role       = aws_iam_role.eks_node_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

# ── Cluster Autoscaler Role ────────────────────────────────────────
# The Cluster Autoscaler runs inside Kubernetes and needs permission
# to add/remove EC2 nodes from the Auto Scaling Group.
# Without this, you have to manually add nodes when your app grows.
resource "aws_iam_role" "cluster_autoscaler" {
  name = "${var.environment}-cluster-autoscaler-role"

  # This role uses IRSA — it can only be assumed by the
  # cluster-autoscaler service account inside the EKS cluster.
  # We use a placeholder assume_role_policy here and update it
  # after the EKS cluster is created (because we need the OIDC URL).
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy" "cluster_autoscaler" {
  name = "cluster-autoscaler"
  role = aws_iam_role.cluster_autoscaler.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "autoscaling:DescribeAutoScalingGroups",
        "autoscaling:DescribeAutoScalingInstances",
        "autoscaling:DescribeLaunchConfigurations",
        "autoscaling:DescribeScalingActivities",
        "autoscaling:DescribeTags",
        "autoscaling:SetDesiredCapacity",
        "autoscaling:TerminateInstanceInAutoScalingGroup",
        "ec2:DescribeLaunchTemplateVersions",
        "ec2:DescribeInstanceTypes"
      ]
      Resource = "*"
    }]
  })
}
