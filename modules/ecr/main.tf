# ─────────────────────────────────────────────────────────────────
# modules/ecr/main.tf
#
# PURPOSE: Creates ECR (Elastic Container Registry) repositories.
#
# WHAT IS ECR?
#   ECR is AWS's private Docker Hub.
#   When you run `docker build`, you get a Docker image.
#   That image needs to be stored somewhere so EC2 and EKS can
#   pull (download) it when starting containers.
#   We use ECR (not Docker Hub) because:
#     - It's inside AWS so pulling is fast and free
#     - EC2 and EKS can pull using their IAM roles — no passwords
#     - Images are private — only your AWS account can access them
#
# WE CREATE TWO REPOSITORIES:
#   - todo-ui  : the React frontend image
#   - todo-api : the Spring Boot backend image
# ─────────────────────────────────────────────────────────────────

# ── todo-api image repository ──────────────────────────────────────
# BUG FIX: Original code had name = "todo-ui" inside the todo_api
# resource block — it was naming the wrong repository!
resource "aws_ecr_repository" "todo_api" {
  name = "todo-api" # BUG FIX: was "todo-ui" in original code — wrong name!

  # image_tag_mutability = "IMMUTABLE" means once you push an image
  # with tag "1.0.0", you can NEVER overwrite it with a different image.
  #
  # WHY IS IMMUTABLE IMPORTANT?
  #   Imagine you deploy version "1.0.0" to production and it works great.
  #   A developer accidentally pushes a broken build as "1.0.0" again.
  #   If tags are MUTABLE (overwritable), production suddenly pulls the
  #   broken image on next restart — without anyone knowing why.
  #   IMMUTABLE prevents this: each version is permanent and traceable.
  #   Use a new tag (1.0.1, 1.0.2) for each new build.
  image_tag_mutability = "IMMUTABLE"

  # scan_on_push = true: every time you push a new Docker image,
  # ECR automatically scans it for known security vulnerabilities.
  # Example: if your base image has a known CVE (security hole),
  # ECR tells you immediately so you can fix it.
  image_scanning_configuration {
    scan_on_push = true
  }

  tags = {
    Name = "${var.environment}-todo-api-ecr"
  }
}

# ── todo-ui image repository ───────────────────────────────────────
resource "aws_ecr_repository" "todo_ui" {
  name                 = "todo-ui"
  image_tag_mutability = "IMMUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = {
    Name = "${var.environment}-todo-ui-ecr"
  }
}

# ── Lifecycle Policy ──────────────────────────────────────────────
# Every Docker push creates a new image. Without cleanup,
# you would accumulate hundreds of old images and pay for storage.
#
# This policy says: keep only the 10 most recent images.
# When image #11 is pushed, the oldest one is automatically deleted.
#
# We apply the same policy to both repositories.
resource "aws_ecr_lifecycle_policy" "todo_api" {
  repository = aws_ecr_repository.todo_api.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep only last 10 images to save storage cost"
      selection = {
        tagStatus   = "any"               # applies to all tags (tagged and untagged)
        countType   = "imageCountMoreThan"
        countNumber = 10
      }
      action = {
        type = "expire" # delete images beyond the count limit
      }
    }]
  })
}

resource "aws_ecr_lifecycle_policy" "todo_ui" {
  repository = aws_ecr_repository.todo_ui.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep only last 10 images to save storage cost"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 10
      }
      action = {
        type = "expire"
      }
    }]
  })
}
