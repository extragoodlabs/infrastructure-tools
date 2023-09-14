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
  region  = var.region
  profile = var.aws_profile
}

data "aws_caller_identity" "current" {}

#
# Generate a password for authenticating with our RDS instance
# This password won't be shared, but instead is used only by the gateway
#

resource "random_password" "db_password" {
  length  = 32
  special = false
}

#
# Create a secret and key to store the JUMPWIRE_ROOT_TOKEN and JUMPWIRE_ENCRYPTION_KEY variables
# for the ECS task.
#

locals {
  root_dir       = path.module
  aws_account_id = data.aws_caller_identity.current.account_id
  rds_username   = "jumpwire"
  rds_password   = random_password.db_password.result

  token_secret = {
    JUMPWIRE_ROOT_TOKEN     = "${var.jumpwire_root_token}"
    JUMPWIRE_ENCRYPTION_KEY = "${var.jumpwire_encryption_key}"
  }
}

resource "aws_kms_key" "jumpwire" {
  description             = "KMS key for encrypting JumpWire secrets and cloudwatch logs from the ECS cluster"
  deletion_window_in_days = 7
}

resource "aws_kms_alias" "jumpwire" {
  name          = "alias/ecs/jumpwire-rds-gateway"
  target_key_id = aws_kms_key.jumpwire.key_id
}

resource "aws_secretsmanager_secret" "jumpwire_token" {
  name_prefix = "/ecs/jumpwire/jumpwire-rds-gateway-token"
  kms_key_id  = aws_kms_key.jumpwire.id
}

resource "aws_secretsmanager_secret_version" "jumpwire_token" {
  secret_id     = aws_secretsmanager_secret.jumpwire_token.id
  secret_string = jsonencode(local.token_secret)
}

#
# Create an RDS instance.
# If you already have a database running, you can replace this with a data block.
# All we need is the username/password/hostname to configure the gateway container.
#

resource "aws_db_subnet_group" "test_db_subnet_group" {
  name       = "test_db_subnet_group"
  subnet_ids = var.vpc_private_subnet_ids
}

resource "aws_db_instance" "test_db" {
  instance_class         = "db.t3.micro"
  allocated_storage      = 10
  db_name                = "test_db"
  engine                 = "postgres"
  username               = local.rds_username
  password               = local.rds_password
  vpc_security_group_ids = var.vpc_security_group_ids
  db_subnet_group_name   = aws_db_subnet_group.test_db_subnet_group.name
  skip_final_snapshot    = true
}

#
# Build a JumpWire container image with a configuration file for accessing
# the RDS instance
#

resource "aws_ecr_repository" "task_repository" {
  name         = "jumpwire-rds-gateway-repository"
  force_delete = true
}

resource "null_resource" "task_ecr_image_builder" {
  depends_on = [
    aws_db_instance.test_db
  ]

  triggers = {
    docker_file       = filesha256("${local.root_dir}/Dockerfile")
    dockerignore_file = filesha256("${local.root_dir}/.dockerignore")
    config_file       = filesha256("${local.root_dir}/jumpwire.yaml")
  }

  provisioner "local-exec" {
    working_dir = local.root_dir
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      aws ecr get-login-password --region ${var.region} --profile ${var.aws_profile} | docker login --username AWS --password-stdin ${local.aws_account_id}.dkr.ecr.${var.region}.amazonaws.com
      docker image build -t ${aws_ecr_repository.task_repository.repository_url}:latest --build-arg db_name=${aws_db_instance.test_db.db_name} --build-arg db_username=${local.rds_username} --build-arg db_password=${local.rds_password} --build-arg db_hostname=${aws_db_instance.test_db.address} .
      docker push ${aws_ecr_repository.task_repository.repository_url}:latest
    EOT
  }
}

#
# Create a Application Load Balancer for JumpWire to receive HTTP requests
# This ALB will be forwarded traffic from the API Gateway with VPC link below
#

resource "aws_lb" "jumpwire" {
  name            = "jumpwire-rds-gateway-alb"
  internal        = true
  subnets         = var.vpc_private_subnet_ids
  ip_address_type = "ipv4"
}

resource "aws_lb_target_group" "jumpwire" {
  name            = "jumpwire-rds-gateway-alb-tar"
  target_type     = "ip"
  ip_address_type = "ipv4"
  port            = 80
  protocol        = "HTTP"
  vpc_id          = var.vpc_id


  health_check {
    path              = "/ping"
    port              = 4004
    healthy_threshold = 2
    interval          = 5
    timeout           = 2
    protocol          = "HTTP"
  }
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
# Create a Network Load Balancer for JumpWire to expose a TCP port
# for proxying database connections
#

resource "aws_lb" "jumpwire_nlb" {
  name               = "jumpwire-rds-gateway-nlb"
  internal           = false
  load_balancer_type = "network"
  subnets            = var.vpc_public_subnet_ids
}

resource "aws_lb_target_group" "jumpwire_nlb" {
  name            = "jumpwire-rds-gateway-nlb-tar"
  target_type     = "ip"
  ip_address_type = "ipv4"
  port            = 5432
  protocol        = "TCP"
  vpc_id          = var.vpc_id

  health_check {
    protocol = "TCP"
  }
}

resource "aws_lb_listener" "jumpwire_nlb" {
  load_balancer_arn = aws_lb.jumpwire_nlb.arn
  protocol          = "TCP"
  port              = 5432

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.jumpwire_nlb.arn
  }
}

#
# HTTP API Gateway that connects the internet to the ALB 
# to allow connections to JumpWire management API
#

resource "aws_apigatewayv2_api" "jumpwire_api" {
  name          = "jumpwire-rds-gateway-api"
  protocol_type = "HTTP"
}

resource "aws_apigatewayv2_vpc_link" "jumpwire" {
  name               = "jumpwire-rds-gateway-api-link"
  security_group_ids = var.vpc_security_group_ids
  subnet_ids         = var.vpc_private_subnet_ids
}

resource "aws_apigatewayv2_integration" "jumpwire" {
  api_id           = aws_apigatewayv2_api.jumpwire_api.id
  integration_type = "HTTP_PROXY"
  integration_uri  = aws_lb_listener.jumpwire.arn

  integration_method = "ANY"
  connection_type    = "VPC_LINK"
  connection_id      = aws_apigatewayv2_vpc_link.jumpwire.id
}

resource "aws_apigatewayv2_route" "jumpwire" {
  api_id    = aws_apigatewayv2_api.jumpwire_api.id
  route_key = "ANY /{proxy+}"

  target = "integrations/${aws_apigatewayv2_integration.jumpwire.id}"
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.jumpwire_api.id
  name        = "$default"
  auto_deploy = true
}

#
# Create an IAM policy to allow the ECS task to read the secret
# and use a managed role for execution
#
# This policy will appear under the name 'testDbGatewayTaskExecutionRoleWithSecrets'
#

data "aws_iam_policy" "ecs_task_execution" {
  arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role" "ecs_task_execution_role" {
  name = "testDbGatewayTaskExecutionRoleWithSecrets"
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
# Create the ECS task definition. This includes all of the environment variables
# and port mappings for the JumpWire gateway docker image. Secure variables
# are loaded from secrets.
#

resource "aws_ecs_task_definition" "jumpwire_task" {
  depends_on = [
    null_resource.task_ecr_image_builder,
    aws_apigatewayv2_api.jumpwire_api
  ]

  family                   = "jumpwire-rds-gateway-task"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.task_cpu
  memory                   = var.task_memory
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn
  task_role_arn            = aws_iam_role.ecs_task_execution_role.arn
  container_definitions    = <<TASK_DEFINITION
[
  {
    "name": "jumpwire-gateway-container",
    "image": "${aws_ecr_repository.task_repository.repository_url}:latest",
    "cpu": ${var.task_cpu},
    "memory": ${var.task_memory},
    "essential": true,
    "portMappings": [
      {
        "hostPort": 4004,
        "containerPort": 4004
      },
      {
        "hostPort": 4443,
        "containerPort": 4443
      },
      {
        "hostPort": 5432,
        "containerPort": 5432
      }
    ],
    "environment": [
      {
        "name": "JUMPWIRE_DOMAIN",
        "value": "${aws_apigatewayv2_api.jumpwire_api.id}.execute-api.${var.region}.amazonaws.com"
      },
      {
        "name": "JUMPWIRE_SSO_BASE_URL",
        "value": "${aws_apigatewayv2_api.jumpwire_api.api_endpoint}"
      }
    ],
    "secrets": [
      {
        "valueFrom": "${aws_secretsmanager_secret.jumpwire_token.arn}:JUMPWIRE_ROOT_TOKEN::",
        "name": "JUMPWIRE_ROOT_TOKEN"
      },
      {
        "valueFrom": "${aws_secretsmanager_secret.jumpwire_token.arn}:JUMPWIRE_ENCRYPTION_KEY::",
        "name": "JUMPWIRE_ENCRYPTION_KEY"
      }
    ],
    "logConfiguration": {
      "logDriver": "awslogs",
      "secretOptions": null,
      "options": {
        "awslogs-group": "/ecs/jumpwire-rds-gateway-task",
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

resource "aws_cloudwatch_log_group" "jumpwire" {
  name              = "/ecs/jumpwire-rds-gateway-task"
  retention_in_days = 1
}

resource "aws_ecs_cluster" "jumpwire" {
  name = "jumpwire-rds-gateway"

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
    null_resource.task_ecr_image_builder
  ]

  name          = "jumpwire-rds-gateway-service"
  cluster       = aws_ecs_cluster.jumpwire.id
  desired_count = 1

  # Track the latest ACTIVE revision
  task_definition        = aws_ecs_task_definition.jumpwire_task.arn
  enable_execute_command = true

  network_configuration {
    subnets = var.vpc_private_subnet_ids
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.jumpwire.arn
    container_name   = "jumpwire-gateway-container"
    container_port   = 4004
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.jumpwire_nlb.arn
    container_name   = "jumpwire-gateway-container"
    container_port   = 5432
  }
}
