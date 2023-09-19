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
# for the ECS task. These are sensitive values, that will be loaded from the secret and injected
# as environment variables at runtime.
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
# Create security groups, to restrict traffic from the Internet
# through the load balancer, ecs cluster, to the database
# :80, :443 & :5432 /0 -> NLB -> ECS -> PG
#

resource "aws_security_group" "network_load_balancer" {
  name        = "network_load_balancer"
  description = "Allow HTTP/s/PG inbound traffic from Internet"
  vpc_id      = var.vpc_id

  ingress {
    description      = "HTTP from Internet"
    from_port        = 80
    to_port          = 80
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  ingress {
    description      = "TLS from Internet"
    from_port        = 443
    to_port          = 443
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  ingress {
    description      = "PG from Internet"
    from_port        = 5432
    to_port          = 5432
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }
}

resource "aws_security_group" "ecs_service" {
  name        = "ecs_service"
  description = "Allow HTTP/s/PG inbound traffic from the LB only"
  vpc_id      = var.vpc_id

  ingress {
    description     = "HTTP from NLB to container port"
    from_port       = 4004
    to_port         = 4004
    protocol        = "tcp"
    security_groups = [aws_security_group.network_load_balancer.id]
  }

  ingress {
    description     = "TLS from NLB to container port"
    from_port       = 4443
    to_port         = 4443
    protocol        = "tcp"
    security_groups = [aws_security_group.network_load_balancer.id]
  }

  ingress {
    description     = "PG from NLB to container port"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.network_load_balancer.id]
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }
}

resource "aws_security_group" "rds_service" {
  name        = "rds_service"
  description = "Allow PG inbound traffic from ECS"
  vpc_id      = var.vpc_id

  ingress {
    description     = "PG from ECS JumpWire task"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.ecs_service.id]
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }
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
  vpc_security_group_ids = [aws_security_group.rds_service.id]
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
# Create a Network Load Balancer for JumpWire to expose TCP ports
# to the Internet for our ECS gateway task. This includes
# ports for proxying database connections, as well as HTTP ports for
# gateway API.
#

resource "aws_lb" "jumpwire_nlb" {
  name               = "jumpwire-rds-gateway-nlb"
  internal           = false
  load_balancer_type = "network"
  subnets            = var.vpc_public_subnet_ids
  security_groups    = [aws_security_group.network_load_balancer.id]
}

resource "aws_lb_target_group" "jumpwire_http_nlb" {
  name                   = "jumpwire-rds-gateway-http-tar"
  target_type            = "ip"
  port                   = 4004
  protocol               = "TCP"
  vpc_id                 = var.vpc_id
  connection_termination = true
  deregistration_delay   = 30

  health_check {
    protocol          = "TCP"
    healthy_threshold = 2
    interval          = 5
    timeout           = 2
  }
}

resource "aws_lb_listener" "jumpwire_http_nlb" {
  load_balancer_arn = aws_lb.jumpwire_nlb.arn
  protocol          = "TCP"
  port              = 80

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.jumpwire_http_nlb.arn
  }
}

resource "aws_lb_target_group" "jumpwire_https_nlb" {
  name                   = "jumpwire-rds-gateway-https-tar"
  target_type            = "ip"
  port                   = 4443
  protocol               = "TCP"
  vpc_id                 = var.vpc_id
  connection_termination = true
  deregistration_delay   = 30

  health_check {
    protocol          = "TCP"
    healthy_threshold = 2
    interval          = 5
    timeout           = 2
  }
}

resource "aws_lb_listener" "jumpwire_https_nlb" {
  load_balancer_arn = aws_lb.jumpwire_nlb.arn
  protocol          = "TCP"
  port              = 443

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.jumpwire_https_nlb.arn
  }
}

resource "aws_lb_target_group" "jumpwire_pg_nlb" {
  name                   = "jumpwire-rds-gateway-pg-tar"
  target_type            = "ip"
  port                   = 5432
  protocol               = "TCP"
  vpc_id                 = var.vpc_id
  connection_termination = true
  deregistration_delay   = 30

  health_check {
    protocol          = "TCP"
    healthy_threshold = 2
    interval          = 5
    timeout           = 2
  }
}

resource "aws_lb_listener" "jumpwire_pg_nlb" {
  load_balancer_arn = aws_lb.jumpwire_nlb.arn
  protocol          = "TCP"
  port              = 5432

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.jumpwire_pg_nlb.arn
  }
}

#
# Create a DNS record that will route traffic to our load balancer
# We load in an existing Route53 Hosted Zone to register the record
# If you don't have an existing Hosted Zone, you can create one here
#

data "aws_route53_zone" "jumpwire_zone" {
  name = var.route53_zone_name
}

resource "aws_route53_record" "jumpwire_hostname" {
  zone_id = data.aws_route53_zone.jumpwire_zone.zone_id
  name    = "test-db"
  type    = "A"

  alias {
    name                   = aws_lb.jumpwire_nlb.dns_name
    zone_id                = aws_lb.jumpwire_nlb.zone_id
    evaluate_target_health = true
  }
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
# Create the ECS task definition. This includes all of the environment variables
# and port mappings for the JumpWire gateway docker image. Secure variables
# are loaded from secrets.
#

resource "aws_ecs_task_definition" "jumpwire_task" {
  depends_on = [
    null_resource.task_ecr_image_builder,
    aws_lb.jumpwire_nlb
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
        "protocol": "tcp",
        "containerPort": 4004
      },
      {
        "hostPort": 4443,
        "protocol": "tcp",
        "containerPort": 4443
      },
      {
        "hostPort": 5432,
        "protocol": "tcp",
        "containerPort": 5432
      }
    ],
    "environment": [
      {
        "name": "JUMPWIRE_DOMAIN",
        "value": "${aws_route53_record.jumpwire_hostname.fqdn}"
      },
      {
        "name": "JUMPWIRE_SSO_BASE_URL",
        "value": "https://${aws_route53_record.jumpwire_hostname.fqdn}"
      },
      {
        "name": "LOG_LEVEL",
        "value": "debug"
      },
      {
        "name": "ACME_GENERATE_CERT",
        "value": "true"
      },
      {
        "name": "ACME_EMAIL",
        "value": "hello@jumpwire.io"
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
  task_definition                   = aws_ecs_task_definition.jumpwire_task.arn
  health_check_grace_period_seconds = 60
  enable_execute_command            = false
  force_new_deployment              = true

  network_configuration {
    subnets         = var.vpc_private_subnet_ids
    security_groups = [aws_security_group.ecs_service.id]
  }

  capacity_provider_strategy {
    base              = 1
    weight            = 100
    capacity_provider = "FARGATE"
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.jumpwire_http_nlb.arn
    container_name   = "jumpwire-gateway-container"
    container_port   = 4004
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.jumpwire_https_nlb.arn
    container_name   = "jumpwire-gateway-container"
    container_port   = 4443
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.jumpwire_pg_nlb.arn
    container_name   = "jumpwire-gateway-container"
    container_port   = 5432
  }
}
