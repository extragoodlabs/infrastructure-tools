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
  region                   = var.region
  shared_config_files      = ["/home/ryan/.aws/config"]
  shared_credentials_files = ["/home/ryan/.aws/credentials"]
  profile                  = "jump"
}

data "aws_caller_identity" "current" {}

#
# Create a secret and key to store the JUMPWIRE_TOKEN environment variable
#


locals {
  aws_account_id = data.aws_caller_identity.current.account_id

  token_secret = {
    JUMPWIRE_TOKEN = "${var.jumpwire_token}"
  }
}

resource "aws_kms_key" "jumpwire" {
  description             = "KMS key for encrypting JumpWire secrets and cloudwatch logs from the ECS cluster"
  deletion_window_in_days = 7
}

resource "aws_kms_alias" "jumpwire" {
  name          = "alias/ecs/jumpwire"
  target_key_id = aws_kms_key.jumpwire.key_id
}

resource "aws_secretsmanager_secret" "jumpwire_token" {
  name_prefix = "/ecs/jumpwire/token"
  kms_key_id  = aws_kms_key.jumpwire.id
}

resource "aws_secretsmanager_secret_version" "jumpwire_token" {
  secret_id     = aws_secretsmanager_secret.jumpwire_token.id
  secret_string = jsonencode(local.token_secret)
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
  name = "ecsTaskExecutionRoleWithSecrets"
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
            "ssmmessages:CreateControlChannel",
            "ssmmessages:CreateDataChannel",
            "ssmmessages:OpenControlChannel",
            "ssmmessages:OpenDataChannel"
          ]
          Effect = "Allow"
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

resource "aws_iam_role_policy_attachment" "on_role_policy_attach" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = data.aws_iam_policy.ecs_task_execution.arn
}

#
# Create the ECS task definition. This includes all of the environment variables
# and port mappings for the JumpWire engine docker image.
#
# Note: you can update defaults if your infrastructure doesn't need a particular proxy
#       (i.e. MySQL), or if you want to give the task more cpu and memory resources
#

resource "aws_ecs_task_definition" "jumpwire_task" {
  family                   = "jumpwire-task"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 1024
  memory                   = 2048
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn
  task_role_arn            = aws_iam_role.ecs_task_execution_role.arn
  container_definitions    = <<TASK_DEFINITION
[
  {
    "name": "jumpwire-engine-container",
    "image": "${var.jumpwire_image}",
    "cpu": 1024,
    "memory": 2048,
    "essential": true,
    "portMappings": [
      {
        "hostPort": 4000,
        "protocol": "tcp",
        "containerPort": 4000
      },
      {
        "hostPort": 9568,
        "protocol": "tcp",
        "containerPort": 9568
      },
      {
        "hostPort": 5432,
        "protocol": "tcp",
        "containerPort": 5432
      },
      {
        "hostPort": 3306,
        "protocol": "tcp",
        "containerPort": 3306
      }
    ],
    "environment": [
      {
        "name": "JUMPWIRE_CONFIG_ENDPOINT",
        "value": "${var.jumpwire_config_endpoint}"
      },
      {
        "name": "JUMPWIRE_FRONTEND",
        "value": "${var.jumpwire_frontend}"
      },
      {
        "name": "DEV_MODE",
        "value": "1"
      }
    ],
    "secrets": [
      {
        "valueFrom": "${aws_secretsmanager_secret.jumpwire_token.arn}:JUMPWIRE_TOKEN::",
        "name": "JUMPWIRE_TOKEN"
      }
    ],
    "logConfiguration": {
      "logDriver": "awslogs",
      "secretOptions": null,
      "options": {
        "awslogs-group": "/ecs/jumpwire-task",
        "awslogs-region": "us-east-2",
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

resource "aws_cloudwatch_log_group" "jumpwire" {
  name = "/ecs/jumpwire-task"
  retention_in_days = 1
  # kms_key_id = aws_kms_key.jumpwire.arn
}

resource "aws_ecs_cluster" "jumpwire" {
  name = "jumpwire"

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
  name          = "jumpwire-service"
  cluster       = aws_ecs_cluster.jumpwire.id
  desired_count = 1

  # Track the latest ACTIVE revision
  task_definition = aws_ecs_task_definition.jumpwire_task.arn
  enable_execute_command = true

  network_configuration {
    subnets = var.vpc_subnet_ids
  }
}
