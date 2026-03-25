resource "aws_iam_role""ec2_api_role" {
    name = "${var.env}-ec2-api-role"
    assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{ Action="sts:AssumeRole", Effect="Allow", Principal={ Service="ec2.amazonaws.com" } }]
  })
}

resource "aws_iam_role_policy_attachment" "ec2_ssm" {
    role = aws_iam_role.ec2_api_role.name
    policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment""ec2_secrets" {
  role       = aws_iam_role.ec2_api_role.name
  policy_arn = "arn:aws:iam::aws:policy/SecretsManagerReadWrite"
}

resource "aws_iam_instance_profile""ec2_api" {
  name = "${var.env}-ec2-api-profile"
  role = aws_iam_role.ec2_api_role.name
}

resource "aws_iam_role""eks_cluster_role" {
  name = "${var.env}-eks-cluster-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{ Action="sts:AssumeRole", Effect="Allow", Principal={ Service="eks.amazonaws.com" } }]
  })
}

resource "aws_iam_role_policy_attachment""eks_cluster_policy" {
  role       = aws_iam_role.eks_cluster_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

resource "aws_iam_role""eks_node_role"{
    name = "${var.env}-eks-node-role"
    assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{ Action="sts:AssumeRole", Effect="Allow", Principal={ Service="ec2.amazonaws.com" } }]
  })
}

resource "aws_iam_role_policy_attachment""node_worker" {
  role = aws_iam_role.eks_node_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}
resource "aws_iam_role_policy_attachment""node_cni" {
  role = aws_iam_role.eks_node_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}
resource "aws_iam_role_policy_attachment""node_ecr" {
  role = aws_iam_role.eks_node_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

data "aws_iam_policy_document""irsa_assume" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
        type = "Federated"
        identifiers = [var.oidc_provider_arn]
    }
    condition {
      test     = "StringEquals"
      variable = "${var.oidc_provider_url}:sub"
      values   = ["system:serviceaccount:todo:todo-ui-sa"]
    }
    condition {
      test     = "StringEquals"
      variable = "${var.oidc_provider_url}:aud"
      values   = ["system:serviceaccount:todo:todo-ui-sa"]
    }
    
  }
}

resource "aws_iam_role""todo_ui_irsa" {
  name               = "${var.env}-todo-ui-irsa"
  assume_role_policy = data.aws_iam_policy_document.irsa_assume.json
}
resource "aws_iam_role_policy_attachment""ui_secrets" {
  role       = aws_iam_role.todo_ui_irsa.name
  policy_arn = "arn:aws:iam::aws:policy/SecretsManagerReadWrite"
}

