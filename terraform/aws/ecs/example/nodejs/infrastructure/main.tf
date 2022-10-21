terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.16"
    }
  }

  required_version = ">= 1.2.0"
}

provider "aws" {
  region = var.region
}

data "aws_caller_identity" "current" {}

# Set up local variables for use in other resources
locals {
  root_dir       = "${path.module}/.."
  aws_account_id = data.aws_caller_identity.current.account_id
  aws_profile    = var.aws_profile

  task_secrets = {
    FOREST_ENV_SECRET  = "${var.forest_env_secret}"
    FOREST_AUTH_SECRET = "${var.forest_auth_secret}"
    POSTGRESQL_URL     = "${var.postgresql_url}"
  }
}

#
# Create ECR repository
# Build and push docker container to ECR repository
#

resource "aws_ecr_repository" "task_repository" {
  name         = "${var.service_name}-repository"
  force_delete = true
}

resource "null_resource" "task_ecr_image_builder" {
  triggers = {
    docker_file    = filesha256("${local.root_dir}/Dockerfile")
    package_file   = filesha256("${local.root_dir}/package.json")
    yarn_lock_file = filesha256("${local.root_dir}/yarn.lock")
    src_dir        = sha256(join("", [for f in fileset("${local.root_dir}/src", "**") : filesha256("${local.root_dir}/src/${f}")]))
  }

  provisioner "local-exec" {
    working_dir = local.root_dir
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      aws ecr get-login-password --region ${var.region} --profile ${var.aws_profile} | docker login --username AWS --password-stdin ${local.aws_account_id}.dkr.ecr.${var.region}.amazonaws.com
      docker image build -t ${aws_ecr_repository.task_repository.repository_url}:latest .
      docker push ${aws_ecr_repository.task_repository.repository_url}:latest
    EOT
  }
}

data "aws_ecr_image" "task_image" {
  depends_on = [
    null_resource.task_ecr_image_builder
  ]

  repository_name = "${var.service_name}-repository"
  image_tag       = "latest"
}

#
# Create Secrets Manager for task environment variables
#

resource "aws_kms_key" "jumpwire" {
  description             = "KMS key for encrypting secret environment variables and cloudwatch logs from the ECS cluster"
  deletion_window_in_days = 7
}

resource "aws_kms_alias" "jumpwire" {
  name          = "alias/ecs/${var.service_name}"
  target_key_id = aws_kms_key.jumpwire.key_id
}

resource "aws_secretsmanager_secret" "task_secrets" {
  name_prefix = "/ecs/${var.service_name}"
  kms_key_id  = aws_kms_key.jumpwire.id
}

resource "aws_secretsmanager_secret_version" "task_secrets" {
  secret_id     = aws_secretsmanager_secret.task_secrets.id
  secret_string = jsonencode(local.task_secrets)
}

#
# Create Cloudwatch log stream for task container logs
#

resource "aws_cloudwatch_log_group" "jumpwire" {
  name              = "/ecs/${var.service_name}-task"
  retention_in_days = 1
}

#
# Create an IAM policy to allow the ECS task to read the secret
# and use a managed role for execution
#
# This policy will appear under the name 'ecsTaskExecutionRoleWithSecrets'
#

data "aws_iam_policy" "ecs_task_execution" {
  arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role" "ecs_task_execution_role" {
  name = "${var.service_name}-task-execution-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Sid    = ""
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      },
    ]
  })

  inline_policy {
    name = "read_secrets_manager_and_ssm"

    policy = jsonencode({
      Version = "2012-10-17"
      Statement = [
        {
          Action = [
            "secretsmanager:GetSecretValue",
            "kms:Decrypt",
            "ssm:GetParameters",
            "ssmmessages:CreateControlChannel",
            "ssmmessages:CreateDataChannel",
            "ssmmessages:OpenControlChannel",
            "ssmmessages:OpenDataChannel"
          ]
          Effect   = "Allow"
          Resource = "*"
        },
      ]
    })
  }
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution_role_policy_attach" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = data.aws_iam_policy.ecs_task_execution.arn
}

#
# Create a Network Load Balancer for receiving requests from the Internet
#

resource "aws_lb" "jumpwire" {
  name            = "${var.service_name}-alb"
  internal        = true
  subnets         = var.vpc_subnet_ids
  ip_address_type = "ipv4"
}

resource "aws_lb_target_group" "jumpwire" {
  name            = "${var.service_name}-alb-tar"
  target_type     = "ip"
  ip_address_type = "ipv4"
  port            = 80
  protocol        = "HTTP"
  vpc_id          = var.vpc_id
}

resource "aws_lb_listener" "jumpwire" {
  load_balancer_arn = aws_lb.jumpwire.arn
  protocol          = "HTTP"
  port              = 80

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.jumpwire.arn
  }
}

#
# HTTP API
#

resource "aws_apigatewayv2_api" "api" {
  name          = "${var.service_name}-api"
  protocol_type = "HTTP"
}

resource "aws_apigatewayv2_vpc_link" "jumpwire" {
  name               = "${var.service_name}-api-link"
  security_group_ids = var.vpc_security_group_ids
  subnet_ids         = var.vpc_subnet_ids
}

resource "aws_apigatewayv2_integration" "jumpwire" {
  api_id           = aws_apigatewayv2_api.api.id
  integration_type = "HTTP_PROXY"
  integration_uri  = aws_lb_listener.jumpwire.arn

  integration_method = "ANY"
  connection_type    = "VPC_LINK"
  connection_id      = aws_apigatewayv2_vpc_link.jumpwire.id
}

resource "aws_apigatewayv2_route" "jumpwire" {
  api_id    = aws_apigatewayv2_api.api.id
  route_key = "ANY /{proxy+}"

  target = "integrations/${aws_apigatewayv2_integration.jumpwire.id}"
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.api.id
  name        = "$default"
  auto_deploy = true
}

#
# Create the ECS task definition. This includes all of the environment variables
# and port mappings for the JumpWire engine docker image.
#
# Note: you can update defaults if your infrastructure doesn't need a particular proxy
#       (i.e. MySQL), or if you want to give the task more cpu and memory resources
#

resource "aws_ecs_task_definition" "jumpwire_task" {
  depends_on = [
    null_resource.task_ecr_image_builder
  ]

  family                   = "${var.service_name}-task"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.task_cpu
  memory                   = var.task_memory
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn
  task_role_arn            = aws_iam_role.ecs_task_execution_role.arn
  container_definitions    = <<TASK_DEFINITION
[
  {
    "name": "${var.service_name}-container",
    "image": "${aws_ecr_repository.task_repository.repository_url}:${data.aws_ecr_image.task_image.image_tag}",
    "cpu": ${var.task_cpu},
    "memory": ${var.task_memory},
    "essential": true,
    "portMappings": [
      {
        "hostPort": 3000,
        "protocol": "tcp",
        "containerPort": 3000
      }
    ],
    "environment": [
      {
        "name": "NODE_ENV",
        "value": "${var.node_env}"
      },
      {
        "name": "FOREST_AGENT_URL",
        "value": "${aws_apigatewayv2_api.api.api_endpoint}"
      }
    ],
    "secrets": [
      {
        "valueFrom": "${aws_secretsmanager_secret.task_secrets.arn}:FOREST_ENV_SECRET::",
        "name": "FOREST_ENV_SECRET"
      },
      {
        "valueFrom": "${aws_secretsmanager_secret.task_secrets.arn}:FOREST_AUTH_SECRET::",
        "name": "FOREST_AUTH_SECRET"
      },
      {
        "valueFrom": "${aws_secretsmanager_secret.task_secrets.arn}:POSTGRESQL_URL::",
        "name": "POSTGRESQL_URL"
      }
    ],
    "logConfiguration": {
      "logDriver": "awslogs",
      "secretOptions": null,
      "options": {
        "awslogs-group": "/ecs/${var.service_name}-task",
        "awslogs-region": "${var.region}",
        "awslogs-stream-prefix": "ecs"
      }
    }
  }
]
TASK_DEFINITION

  runtime_platform {
    operating_system_family = "LINUX"
  }
}

#
# Create an ECS cluster for launching the service with task
#

resource "aws_ecs_cluster" "jumpwire" {
  name = "${var.service_name}-ecs-cluster"

  configuration {
    execute_command_configuration {
      kms_key_id = aws_kms_key.jumpwire.key_id
      logging    = "OVERRIDE"

      log_configuration {
        cloud_watch_encryption_enabled = false
        cloud_watch_log_group_name     = aws_cloudwatch_log_group.jumpwire.name
      }
    }
  }
}

resource "aws_ecs_cluster_capacity_providers" "jumpwire_fargate" {
  cluster_name = aws_ecs_cluster.jumpwire.name

  capacity_providers = ["FARGATE"]

  default_capacity_provider_strategy {
    base              = 1
    weight            = 100
    capacity_provider = "FARGATE"
  }
}

#
# Create an ECS service for running the JumpWire engine task
# which will be created in the cluster above
#

resource "aws_ecs_service" "jumpwire" {
  depends_on = [
    aws_lb_listener.jumpwire
  ]

  name          = "${var.service_name}-ecs-service"
  cluster       = aws_ecs_cluster.jumpwire.id
  desired_count = 1

  # Track the latest ACTIVE revision
  task_definition        = aws_ecs_task_definition.jumpwire_task.arn
  enable_execute_command = true

  network_configuration {
    subnets = var.vpc_subnet_ids
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.jumpwire.arn
    container_name   = "${var.service_name}-container"
    container_port   = 3000
  }
}
