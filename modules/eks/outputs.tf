# modules/eks/outputs.tf
#
# PURPOSE: Exposes EKS cluster details needed by:
#   - root outputs.tf  (to print the cluster name after apply)
#   - deploy.sh        (to run: aws eks update-kubeconfig --name <cluster_name>)
#   - k8s/service-account.yaml  (needs the IRSA role ARN)
#
# WHY THIS FILE WAS CAUSING THE ERROR:
#   outputs.tf line 8 said: module.eks.cluster_name
#   Terraform looked inside modules/eks/ for an output named
#   "cluster_name" — the file didn't exist so Terraform failed.
#   Creating this file with the correct output name fixes the error.

output "cluster_name" {
  # This is the EKS cluster name you use with kubectl and AWS CLI.
  # After terraform apply, run:
  #   aws eks update-kubeconfig --region ap-south-1 --name <this_value>
  # Then: kubectl get nodes
  description = "EKS cluster name. Use with: aws eks update-kubeconfig --name <value>"
  value       = aws_eks_cluster.main.name
}

output "cluster_endpoint" {
  # The HTTPS endpoint of the Kubernetes API server.
  # kubectl sends all commands to this URL.
  # It is stored in ~/.kube/config after running aws eks update-kubeconfig.
  description = "Kubernetes API server endpoint URL."
  value       = aws_eks_cluster.main.endpoint
}

output "cluster_version" {
  description = "Kubernetes version running on this cluster."
  value       = aws_eks_cluster.main.version
}

output "oidc_provider_arn" {
  # The OIDC provider ARN is needed to create IRSA roles for additional pods.
  # If you add a new service that needs AWS access, use this ARN
  # in its IAM role trust policy.
  description = "OIDC provider ARN. Use when creating IRSA roles for pods."
  value       = aws_iam_openid_connect_provider.eks.arn
}

output "oidc_provider_url" {
  # The URL without https:// prefix — needed in IAM condition keys.
  # Example: oidc.eks.ap-south-1.amazonaws.com/id/ABCD1234
  description = "OIDC provider URL without https://. Used in IAM trust policy conditions."
  value       = replace(aws_iam_openid_connect_provider.eks.url, "https://", "")
}

output "todo_ui_irsa_role_arn" {
  # Add this ARN as an annotation on the Kubernetes service account
  # in k8s/service-account.yaml:
  #   eks.amazonaws.com/role-arn: "<this_value>"
  description = "IAM role ARN for todo-ui pods to access AWS Secrets Manager via IRSA."
  value       = aws_iam_role.todo_ui_irsa.arn
}
