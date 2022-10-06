variable "region" {
  type        = string
  description = "The AWS region to create resources in"
  default     = "us-east-2"
}

variable "jumpwire_frontend" {
  type        = string
  description = "Frontend endpoint URL (typically a websocket, or wss://) to sync the latest policy definitions"
  default     = "wss://app.jumpwire.ai"
}

variable "jumpwire_token" {
  type        = string
  description = "The JumpWire cluster token, which will be stored as a secret and injected into the container runtime as an environment variable"
  sensitive   = true
}

variable "jumpwire_image" {
  type        = string
  description = "Docker image for the latest version of the JumpWire engine."
  default     = "jumpwire/jumpwire"
}

variable "jumpwire_environment" {
  type        = string
  description = "The name of the environment that this installation will target"
  default     = "production"
}

variable "vpc_subnet_ids" {
  type        = list(string)
  description = "A list of subnet_ids in which to launch the service"
}

variable "task_cpu" {
  type        = number
  description = "The amount of CPU to assign to the task. Values range between 256 and 16384."
  default     = 2048
  validation {
    condition     = 256 == var.task_cpu || 1024 == var.task_cpu || 2048 == var.task_cpu || 4096 == var.task_cpu || 8192 == var.task_cpu || 16384 == var.task_cpu
    error_message = "CPU values must be one of - 256, 1024, 2048, 4096, 8192, 16384"
  }
}

variable "task_memory" {
  type        = number
  description = "The amount of memory to assign to the task. Values range between 1GB and 120GB in various units. Please see AWS documentation for moer information"
  default     = 4096
}
