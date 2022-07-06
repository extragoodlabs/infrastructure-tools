variable "region" {
  type        = string
  description = "The AWS region to create resources in"
  default     = "us-east-2"
}

variable "aws_account_id" {
  type        = string
  description = "The id of the AWS account to create resources in"
}

variable "jumpwire_config_endpoint" {
  type        = string
  description = "Configuration endpoint URL for the engine to bootstrap from."
}

variable "jumpwire_frontend" {
  type        = string
  description = "Frontend endpoint URL (typically a websocket, or wss://) to sync the latest policy definitions"
}

variable "jumpwire_token" {
  type        = string
  description = "ARN for a AWS Secrets Manager that stores the JumpWire token, and is injected into the container runtime as an environment variable"
  sensitive   = true
}

variable "jumpwire_image" {
  type        = string
  description = "Docker image for the latest version of the JumpWire engine."
}
