# ─────────────────────────────────────────────────────────────────
# modules/eks/main.tf
#
# PURPOSE: Creates the Kubernetes cluster that runs todo-ui.
#
# WHAT IS EKS?
#   EKS = Elastic Kubernetes Service.
#   Kubernetes is a system that runs and manages Docker containers.
#   You tell it "run 2 copies of my todo-ui container" and it:
#     - Starts 2 containers (pods) across 2 different servers
#     - Restarts them if they crash (self-healing)
#     - Adds more copies when traffic grows (autoscaling)
#     - Removes unhealthy copies from the load balancer (readiness)
#
#   EKS specifically means AWS manages the Kubernetes "control plane"
#   (the brain of Kubernetes). You only manage the worker nodes
#   (the EC2 instances where your pods actually run).
#
# KEY CONCEPTS:
#
#   OIDC (OpenID Connect):
#     A technology that lets Kubernetes pods prove their identity
#     to AWS. Think of it as a passport system.
#     Without OIDC, pods cannot get AWS credentials.
#     With OIDC, a pod can say "I am the todo-ui service account"
#     and AWS grants it the matching IAM role's permissions.
#     This is called IRSA (IAM Roles for Service Accounts).
#
#   Why OIDC instead of access keys?
#     Access keys = static passwords (can be stolen, must be rotated)
#     OIDC/IRSA  = temporary tokens (auto-rotated every 15 minutes)
#
#   Managed Node Group:
#     Instead of creating EC2 instances yourself and joining them
#     to the cluster, you tell AWS "give me 2 t3.medium nodes."
#     AWS creates them, patches them, and replaces them if they fail.
#
#   Why nodes in PRIVATE subnets?
#     Pods (your app containers) run on nodes. Nobody should be able
#     to SSH directly into a node from the internet. Private subnets
#     ensure nodes are reachable only from within the VPC.
# ─────────────────────────────────────────────────────────────────

# ── EKS Cluster (Control Plane) ────────────────────────────────────
# This creates the Kubernetes "brain" — the API server, scheduler,
# and controller manager. AWS manages this for you.
# You never see or touch these servers — they are invisible.
resource "aws_eks_cluster" "main" {
  name     = "${var.environment}-eks"
  role_arn = var.eks_cluster_role_arn  # IAM role that allows EKS to manage AWS resources
  version  = "1.29"                    # Kubernetes version

  vpc_config {
    # Worker nodes live in private subnets
    subnet_ids = var.private_subnet_ids

    # endpoint_private_access = true: kubectl commands from inside the VPC work
    # endpoint_public_access  = false: kubectl API server is NOT reachable from internet
    # This means you must be inside the VPC (via VPN or bastion) to run kubectl
    endpoint_private_access = true
    endpoint_public_access  = true  # set to false in production — use VPN to access

    security_group_ids = [var.app_sg_id]
  }

  # Enable CloudWatch logging for the Kubernetes control plane.
  # These logs tell you:
  #   api          → every kubectl command made (audit trail)
  #   audit        → who did what in the cluster (security)
  #   authenticator → who logged in (authentication events)
  #   scheduler    → pod scheduling decisions
  enabled_cluster_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]

  # Encrypt Kubernetes secrets (passwords stored in etcd).
  # Kubernetes stores ConfigMaps and Secrets in etcd (its internal database).
  # Without this, secrets are stored as base64 in etcd — easily decoded.
  # With KMS encryption, even if someone gets the etcd data, it is unreadable.
  encryption_config {
    provider {
      key_arn = var.kms_key_arn
    }
    resources = ["secrets"] # encrypt only the Secrets resource type
  }

  tags = {
    Name = "${var.environment}-eks"
  }
}

# ── OIDC Provider ──────────────────────────────────────────────────
# OIDC = OpenID Connect.
# This is the "passport office" for your pods.
#
# HOW IRSA WORKS (step by step):
#   1. We create an OIDC provider that links EKS to AWS IAM.
#   2. We create an IAM role with a trust policy that says:
#      "only the todo-ui Kubernetes service account can use this role"
#   3. The todo-ui pod runs with that service account.
#   4. When todo-ui calls AWS (e.g. Secrets Manager), AWS checks:
#      "is this pod's service account allowed?" → yes → grants access
#
# WHY IS THIS BETTER THAN NODE ROLE?
#   If you put Secrets Manager access on the node role, then
#   EVERY pod on that node can access Secrets Manager — including
#   a compromised pod. IRSA gives access to ONLY the specific pod.
#
# data "tls_certificate": reads the TLS certificate from the EKS
# OIDC issuer URL to get its fingerprint (a security identifier).
data "tls_certificate" "eks" {
  url = aws_eks_cluster.main.identity[0].oidc[0].issuer
}

# Register the EKS cluster's OIDC issuer with AWS IAM.
# This tells AWS: "trust tokens signed by this EKS cluster."
resource "aws_iam_openid_connect_provider" "eks" {
  # The URL that issues the OIDC tokens (from EKS)
  url = aws_eks_cluster.main.identity[0].oidc[0].issuer

  # The audience — who the token is intended for
  # "sts.amazonaws.com" = AWS Security Token Service (grants temp credentials)
  client_id_list = ["sts.amazonaws.com"]

  # The fingerprint of the OIDC issuer's TLS certificate.
  # AWS uses this to verify that tokens really come from this cluster.
  thumbprint_list = [data.tls_certificate.eks.certificates[0].sha1_fingerprint]

  tags = {
    Name = "${var.environment}-eks-oidc"
  }
}

# ── IRSA Role for todo-ui pods ─────────────────────────────────────
# This IAM role is assumed ONLY by the todo-ui Kubernetes service account.
# It gives todo-ui pods permission to read from Secrets Manager.
#
# The trust policy uses OIDC conditions to restrict which service
# account can assume this role:
#   namespace: todo
#   service account name: todo-ui-sa
# Any other pod cannot assume this role — even on the same cluster.
resource "aws_iam_role" "todo_ui_irsa" {
  name = "${var.environment}-todo-ui-irsa"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = "sts:AssumeRoleWithWebIdentity"
      Principal = {
        # The OIDC provider we just created — format: oidc.eks.<region>.amazonaws.com/id/<cluster-id>
        Federated = aws_iam_openid_connect_provider.eks.arn
      }
      Condition = {
        StringEquals = {
          # Only the "todo-ui-sa" service account in the "todo" namespace can assume this role
          "${replace(aws_iam_openid_connect_provider.eks.url, "https://", "")}:sub" = "system:serviceaccount:todo:todo-ui-sa"
          "${replace(aws_iam_openid_connect_provider.eks.url, "https://", "")}:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })

  tags = {
    Name = "${var.environment}-todo-ui-irsa"
  }
}

# Give the todo-ui pod permission to read Secrets Manager secrets.
# It needs this to fetch the DocDB connection string at startup.
resource "aws_iam_role_policy_attachment" "todo_ui_secrets" {
  role       = aws_iam_role.todo_ui_irsa.name
  policy_arn = "arn:aws:iam::aws:policy/SecretsManagerReadWrite"
}

# ── EKS Managed Node Group ─────────────────────────────────────────
# Node group = the EC2 instances where your pods run.
# "Managed" = AWS handles launching, patching, and replacing nodes.
# You only specify: how many, what size, which subnets.
resource "aws_eks_node_group" "app" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "${var.environment}-app-nodes"
  node_role_arn   = var.eks_node_role_arn      # role for the EC2 nodes
  subnet_ids      = var.private_subnet_ids     # nodes in PRIVATE subnets
  instance_types  = [var.node_instance_type]   # t3.medium by default

  # Scaling config — how many nodes to run
  scaling_config {
    desired_size = 2   # start with 2 nodes
    min_size     = 2   # never go below 2 (for HA)
    max_size     = 6   # can scale up to 6 nodes when traffic spikes
  }

  # Rolling update: when updating nodes, replace one at a time.
  # max_unavailable = 1 means only 1 node is down at a time.
  # Pods from the draining node are moved to the remaining nodes first.
  update_config {
    max_unavailable = 1
  }

  # Labels are key-value pairs added to nodes.
  # Pods can use nodeSelector to only run on nodes with specific labels.
  # "role=app" lets you ensure app pods go to app nodes (not system nodes).
  labels = {
    role = "app"
    env  = var.environment
  }

  # Node group cannot be created before the cluster
  depends_on = [aws_eks_cluster.main]

  tags = {
    Name = "${var.environment}-app-nodes"
    # These tags are read by Cluster Autoscaler to know which ASG to scale
    "k8s.io/cluster-autoscaler/enabled"                  = "true"
    "k8s.io/cluster-autoscaler/${var.environment}-eks"   = "owned"
  }
}

# ── CloudWatch Log Group for EKS ──────────────────────────────────
# The EKS control plane logs (api, audit, authenticator, etc.)
# go to this CloudWatch log group.
resource "aws_cloudwatch_log_group" "eks" {
  name              = "/aws/eks/${var.environment}-eks/cluster"
  retention_in_days = 30

  tags = {
    Name = "${var.environment}-eks-logs"
  }
}
