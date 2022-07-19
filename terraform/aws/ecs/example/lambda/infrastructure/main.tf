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
  root_dir       = "${path.module}/.."
  aws_account_id = data.aws_caller_identity.current.account_id
  aws_profile    = var.aws_profile

  default_memory_size = 256
  default_timeout     = 60

  function_name = "${var.service_name}-lambda"
  build_args    = "--build-arg binary=handler --build-arg log_level=${var.log_level}"
}

#
# Create ECR repository
# Build and push docker container to ECR repository
#

# resource "aws_ecr_repository" "lambda_repository" {
#   name         = "${var.service_name}-crud-api"
#   force_delete = true
# }

# resource "null_resource" "lambda_ecr_image_builder" {
#   triggers = {
#     docker_file     = filesha256("${local.root_dir}/Dockerfile")
#     cargo_file      = filesha256("${local.root_dir}/Cargo.toml")
#     cargo_lock_file = filesha256("${local.root_dir}/Cargo.lock")
#     src_dir         = sha256(join("", [for f in fileset("${local.root_dir}/src", "**") : filesha256("${local.root_dir}/src/${f}")]))
#   }

#   provisioner "local-exec" {
#     working_dir = local.root_dir
#     interpreter = ["/bin/bash", "-c"]
#     command     = <<-EOT
#       aws ecr get-login-password --region ${var.region} --profile ${var.aws_profile} | docker login --username AWS --password-stdin ${local.aws_account_id}.dkr.ecr.${var.region}.amazonaws.com
#       docker image build -t ${aws_ecr_repository.lambda_repository.repository_url}:latest ${local.build_args} .
#       docker push ${aws_ecr_repository.lambda_repository.repository_url}:latest
#     EOT
#   }
# }

resource "null_resource" "lambda_cargo_builder" {
  triggers = {
    docker_file     = filesha256("${local.root_dir}/Dockerfile")
    cargo_file      = filesha256("${local.root_dir}/Cargo.toml")
    cargo_lock_file = filesha256("${local.root_dir}/Cargo.lock")
    src_dir         = sha256(join("", [for f in fileset("${local.root_dir}/src", "**") : filesha256("${local.root_dir}/src/${f}")]))
  }

  provisioner "local-exec" {
    working_dir = local.root_dir
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      docker build -t jumpwire-example-crud-api --build-arg name=jumpwire-crud-api-staff --output type=local,dest=release .
    EOT
  }
}

# data "aws_ecr_image" "lambda_image" {
#   depends_on = [
#     null_resource.lambda_ecr_image_builder
#   ]

#   repository_name = "${var.service_name}-crud-api"
#   image_tag       = "latest"
# }

#
# Build lambda function from container
#

resource "aws_lambda_function" "lambda_function" {
  depends_on = [
    null_resource.lambda_cargo_builder
  ]
  function_name = local.function_name

  filename      = "${local.root_dir}/release/jumpwire-crud-api-staff.zip"
  architectures = ["arm64"]
  runtime       = "provided.al2"
  handler       = "boostrap"

  source_code_hash = filebase64sha256("${local.root_dir}/release/jumpwire-crud-api-staff.zip")

  timeout     = local.default_timeout
  memory_size = local.default_memory_size
  role        = aws_iam_role.lambda_role.arn

  vpc_config {
    security_group_ids = ["sg-0d8777c2f154beda9"]
    subnet_ids = ["subnet-0343d3298066c851b", "subnet-03a6411cf6733033b"]
  }
}

#
# Logs to CloudWatch
#

resource "aws_cloudwatch_log_group" "lambda_log_group" {
  name              = "/aws/lambda/${aws_lambda_function.lambda_function.function_name}"
  retention_in_days = 1
}

#
# IAM role for AWS managed policy 
#

resource "aws_iam_role" "lambda_role" {
  name = "${var.service_name}-iam-role-${var.region}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = ""
        Effect = "Allow"
        Action = "sts:AssumeRole"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "basic_lambda_policy" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

#
# HTTP API
#

resource "aws_apigatewayv2_api" "api" {
  name          = "${var.service_name}-http-api"
  protocol_type = "HTTP"
  target        = aws_lambda_function.lambda_function.arn
}

resource "aws_lambda_permission" "apigw" {
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.lambda_function.arn
  principal     = "apigateway.amazonaws.com"

  source_arn = "${aws_apigatewayv2_api.api.execution_arn}/*/*"
}
