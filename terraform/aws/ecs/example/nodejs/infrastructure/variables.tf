variable "service_name" {
  type    = string
  default = "nodejs-backend"
}

variable "region" {
  type    = string
  default = "us-east-2"
}

variable "aws_profile" {
  type    = string
  default = "jump"
}

variable "forest_env_secret" {
  type        = string
  description = "Forest Admin environment secret, available in the Forest Admin dashboard"
  sensitive   = true
}

variable "forest_auth_secret" {
  type        = string
  description = "Forest Admin authentication secret, available in the Forest Admin dashboard"
  sensitive   = true
}

variable "postgresql_url" {
  type        = string
  description = "Full postgresql url containing username, password, host, port and database"
  sensitive   = true
}

variable "vpc_id" {
  type = string
  description = "VPC ID corresponding to the VPC to launch all resources"
}

variable "vpc_subnet_ids" {
  type        = list(string)
  description = "A list of subnet_ids in which to launch the service. This should be the private subnets in the VPC above"
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
