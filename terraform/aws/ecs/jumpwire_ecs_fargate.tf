variable "jumpwire_config_endpoint" {
  type        = "string"
  description = "Configuration endpoint URL for the engine to bootstrap from."
}

variable "jumpwire_frontend" {
  type        = "string"
  description = "Frontend endpoint URL (typically a websocket, or wss://) to sync the latest policy definitions"
}

variable "jumpwire_token" {
  type        = "string"
  description = "ARN for a AWS Secrets Manager that stores the JumpWire token, and is injected into the container runtime as an environment variable"
  sensitive   = true
}

variable "jumpwire_image" {
  type        = "string"
  description = "Docker image for the latest version of the JumpWire engine."
}

/*
* Create a secret to store the JUMPWIRE_TOKEN environment variable
* Create a policy to allow the ECS task to read the secret
*/

variable "jumpwire_token" {
  default = {
    JUMPWIRE_TOKEN = "${var.jumpwire_token}"
  }

  type = map(string)
}

resource "aws_secretsmanager_secret" "jumpwire_token" {
  name_prefix = "jumpwire/token"
}

resource "aws_secretsmanager_secret_version" "jumpwire_token" {
  secret_id     = aws_secretsmanager_secret.jumpwire_token.id
  secret_string = jsonencode(var.jumpwire_token)
}

data "aws_iam_policy" "ecs_task_execution" {
  arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role" "ecs_task_execution_role" {
  name = "ecsTaskExecutionRole"
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
    name = "read_secrets_manager"

    policy = jsonencode({
      Version = "2012-10-17"
      Statement = [
        {
          Action   = [
            "secretsmanager:GetSecretValue",
            "kms:Decrypt"
          ]
          Effect   = "Allow"
          Resource = [
            "arn:aws:secretsmanager:${data.region}:${data.aws_account_id}:secret:${aws_secretsmanager_secret.jumpwire_token.name}",
            "arn:aws:kms:${data.region}:${data.aws_account_id}:key/${aws_secretsmanager_secret.jumpwire_token.id}"
          ]
        },
      ]
    })
  }
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution_role_policy_attach" {
   role       = "${aws_iam_role.ecs_task_execution_role.name}"
   policy_arn = "${data.aws_iam_policy.ecs_task_execution.arn}"
}

resource "aws_iam_role_policy_attachment" "on_role_policy_attach" {
   role       = "${aws_iam_role.ecs_task_execution_role.name}"
   policy_arn = "${data.aws_iam_policy.ecs_task_execution.arn}"
}

resource "IAM ROLE RESOURCE" "task_execution_role" {
}

resource "SECRETS MANAGER" "token_secret" {
}

resource "aws_ecs_task_definition" "jumpwire_engine_task" {
  family                   = "jumpwire-engine-task"
  compatibilities          = ["EC2", "FARGATE"]
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
        "awslogs-group": "/ecs/jumpwire-engine-task",
        "awslogs-region": "us-east-2",
        "awslogs-stream-prefix": "ecs"
      }
    },
  }
]
TASK_DEFINITION

  runtime_platform {
    operating_system_family = "LINUX"
  }
}
