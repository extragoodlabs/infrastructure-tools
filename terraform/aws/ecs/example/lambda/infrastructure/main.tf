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
}


resource "aws_lambda_function" "staff_function" {
  function_name = "${local.function_name}-staff"

  filename      = "${local.root_dir}/release/jumpwire-example-crud-api-staff.zip"
  architectures = ["arm64"]
  runtime       = "provided.al2"
  handler       = "boostrap"

  source_code_hash = filebase64sha256("${local.root_dir}/release/jumpwire-example-crud-api-staff.zip")

  timeout     = local.default_timeout
  memory_size = local.default_memory_size
  role        = aws_iam_role.lambda_role.arn

  environment {
    variables = {
      POSTGRESQL_URL = var.postgresql_url
      RUST_LOG  = "info"
    }
  }

  vpc_config {
    security_group_ids = var.lambda_security_group_ids
    subnet_ids = var.lambda_subnet_ids
  }
}

resource "aws_lambda_function" "customer_function" {
  function_name = "${local.function_name}-customer"

  filename      = "${local.root_dir}/release/jumpwire-example-crud-api-customer.zip"
  architectures = ["arm64"]
  runtime       = "provided.al2"
  handler       = "boostrap"

  source_code_hash = filebase64sha256("${local.root_dir}/release/jumpwire-example-crud-api-customer.zip")

  timeout     = local.default_timeout
  memory_size = local.default_memory_size
  role        = aws_iam_role.lambda_role.arn

  environment {
    variables = {
      POSTGRESQL_URL = var.postgresql_url
      RUST_LOG  = "info"
    }
  }

  vpc_config {
    security_group_ids = var.lambda_security_group_ids
    subnet_ids = var.lambda_subnet_ids
  }
}

resource "aws_lambda_function" "default_function" {
  function_name = "${local.function_name}-default"

  filename      = "${local.root_dir}/release/jumpwire-example-crud-api-default.zip"
  architectures = ["arm64"]
  runtime       = "provided.al2"
  handler       = "boostrap"

  source_code_hash = filebase64sha256("${local.root_dir}/release/jumpwire-example-crud-api-default.zip")

  timeout     = local.default_timeout
  memory_size = local.default_memory_size
  role        = aws_iam_role.lambda_role.arn

  environment {
    variables = {
      POSTGRESQL_URL = var.postgresql_url
      RUST_LOG  = "info"
    }
  }

  vpc_config {
    security_group_ids = var.lambda_security_group_ids
    subnet_ids = var.lambda_subnet_ids
  }
}

#
# Logs to CloudWatch
#

resource "aws_cloudwatch_log_group" "staff_lambda_log_group" {
  name              = "/aws/lambda/${aws_lambda_function.staff_function.function_name}"
  retention_in_days = var.log_retention_in_days
}

resource "aws_cloudwatch_log_group" "customer_lambda_log_group" {
  name              = "/aws/lambda/${aws_lambda_function.customer_function.function_name}"
  retention_in_days = var.log_retention_in_days
}

resource "aws_cloudwatch_log_group" "default_lambda_log_group" {
  name              = "/aws/lambda/${aws_lambda_function.default_function.function_name}"
  retention_in_days = var.log_retention_in_days
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
}

resource "aws_lambda_permission" "staff_apigw" {
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.staff_function.arn
  principal     = "apigateway.amazonaws.com"

  source_arn = "${aws_apigatewayv2_api.api.execution_arn}/*/*"
}

resource "aws_lambda_permission" "customer_apigw" {
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.customer_function.arn
  principal     = "apigateway.amazonaws.com"

  source_arn = "${aws_apigatewayv2_api.api.execution_arn}/*/*"
}

resource "aws_lambda_permission" "default_apigw" {
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.default_function.arn
  principal     = "apigateway.amazonaws.com"

  source_arn = "${aws_apigatewayv2_api.api.execution_arn}/*/*"
}

##
## /staff route
##

resource "aws_apigatewayv2_integration" "staff" {
  api_id           = aws_apigatewayv2_api.api.id
  integration_type = "AWS_PROXY"

  connection_type           = "INTERNET"
  description               = "Staff CRUD API"
  integration_method        = "POST"
  payload_format_version    = "2.0"
  integration_uri           = aws_lambda_function.staff_function.invoke_arn
}

resource "aws_apigatewayv2_route" "staff" {
  api_id    = aws_apigatewayv2_api.api.id
  route_key = "ANY /staff"

  target = "integrations/${aws_apigatewayv2_integration.staff.id}"
}

resource "aws_apigatewayv2_deployment" "staff" {
  api_id      = aws_apigatewayv2_route.staff.api_id
  description = "Staff deployment"

  lifecycle {
    create_before_destroy = true
  }
}

##
## /customer route
##

resource "aws_apigatewayv2_integration" "customer" {
  api_id           = aws_apigatewayv2_api.api.id
  integration_type = "AWS_PROXY"

  connection_type           = "INTERNET"
  description               = "Customer CRUD API"
  integration_method        = "POST"
  payload_format_version    = "2.0"
  integration_uri           = aws_lambda_function.customer_function.invoke_arn
}

resource "aws_apigatewayv2_route" "customer" {
  api_id    = aws_apigatewayv2_api.api.id
  route_key = "ANY /customers"

  target = "integrations/${aws_apigatewayv2_integration.customer.id}"
}

resource "aws_apigatewayv2_deployment" "customer" {
  api_id      = aws_apigatewayv2_route.customer.api_id
  description = "Customer deployment"

  lifecycle {
    create_before_destroy = true
  }
}

##
## $default route
##

resource "aws_apigatewayv2_integration" "default" {
  api_id           = aws_apigatewayv2_api.api.id
  integration_type = "AWS_PROXY"

  connection_type           = "INTERNET"
  description               = "Customer CRUD API"
  integration_method        = "POST"
  payload_format_version    = "2.0"
  integration_uri           = aws_lambda_function.default_function.invoke_arn
}

resource "aws_apigatewayv2_route" "default" {
  api_id    = aws_apigatewayv2_api.api.id
  route_key = "$default"

  target = "integrations/${aws_apigatewayv2_integration.default.id}"
}

resource "aws_apigatewayv2_deployment" "default" {
  api_id      = aws_apigatewayv2_route.default.api_id
  description = "Default deployment"

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_apigatewayv2_stage" "default" {
  api_id = aws_apigatewayv2_api.api.id
  name   = "$default"
  auto_deploy = true
}
