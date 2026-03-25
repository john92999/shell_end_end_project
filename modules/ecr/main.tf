resource "aws_ecr_repository""todo_ui"{
    name = "todo-ui"
    image_tag_mutability = "IMMUTABLE"
    image_scanning_configuration {
        scan_on_push = true
    }
}

resource "aws_ecr_repository" "todo_api"{
    name = "todo-ui"
    image_tag_mutability = "IMMUTABLE"
    image_scanning_configuration {
        scan_on_push = true
    }
}

resource "aws_ecr_lifecycle_policy" "todo_api" {
    repository = aws_ecr_repository.todo_api.name
    policy = jsonencode({
        rules = [{
            rulePriority = 1
            selection = {
                tagStatus="any"
                countType="imageCountMoreThan"
                countNumber=10
            }
            action = {
                type = "expire"
            }
        }]
    })
}