variable "region" {
  type        = string
  description = "The AWS region to create resources in"
  default     = "us-east-2"
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
  description = "The JumpWire cluster token, which will be stored as a secret and injected into the container runtime as an environment variable"
  sensitive   = true
}

variable "jumpwire_image" {
  type        = string
  description = "Docker image for the latest version of the JumpWire engine."
}

variable "vpc_subnet_ids" {
  type = list(string)
  description = "A list of subnet_ids in which to launch the service"
}
