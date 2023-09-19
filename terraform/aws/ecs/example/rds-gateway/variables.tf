variable "region" {
  type    = string
  default = "us-east-2"
}

variable "aws_profile" {
  type        = string
  description = "Profile for set of AWS credentials to use when executing the cli command to upload Docker image to ECR"
  default     = "default"
}

variable "jumpwire_root_token" {
  type        = string
  description = "Auth token for connecting to JumpWire management API"
  sensitive   = true
}

variable "jumpwire_encryption_key" {
  type        = string
  description = "Random key to use for database field encryption"
  sensitive   = true
}

variable "route53_zone_name" {
  type        = string
  description = "Name of Route53 Hosted Zone where an alias record for JumpWire will be created"
}

variable "vpc_id" {
  type        = string
  description = "VPC ID corresponding to the VPC to launch all resources"
}

variable "vpc_private_subnet_ids" {
  type        = list(string)
  description = "A list of private subnet_ids in which to launch services that do not need direct internet connection, such as the database and ecs task."
}

variable "vpc_public_subnet_ids" {
  type        = list(string)
  description = "A list of public subnet_ids in which to launch services that do need direct internet connection, such as a network load balancer."
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
