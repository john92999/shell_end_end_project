# modules/ecr/outputs.tf

output "todo_api_url" {
  description = "Full ECR URL for todo-api. Use this in docker tag and docker push commands."
  value       = aws_ecr_repository.todo_api.repository_url
}

output "todo_ui_url" {
  description = "Full ECR URL for todo-ui. Use this in docker tag and docker push commands."
  value       = aws_ecr_repository.todo_ui.repository_url
}
