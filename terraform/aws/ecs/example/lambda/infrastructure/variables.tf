variable "service_name" {
  type    = string
  default = "jumpwire-example"
}

variable "region" {
  type    = string
  default = "us-east-2"
}

variable "aws_profile" {
  type    = string
  default = "jump"
}

variable "log_retention_in_days" {
  type    = number
  default = 1
}

variable "log_level" {
  type    = string
  default = "info"
}

variable "mysql_url" {
  type = string
  sensitive = true
  description = "A full MySQL url in the form of mysql://[user]:[password]@[host]:[port]/[database]"
}

variable "lambda_security_group_ids" {
  type = list(string)
  description = "List of VPC security groups for the lambda function"
}

variable "lambda_subnet_ids" {
  type = list(string)
  description = "List of VPC subnets to deploy lambda function"
}
