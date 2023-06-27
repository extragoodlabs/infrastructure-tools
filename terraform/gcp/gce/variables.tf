variable "project_id" {
  description = "Project id where the instances will be created."
  type        = string
}

variable "region" {
  type        = string
  description = "Instance region."
}

variable "zone" {
  type        = string
  description = "Instance zone."
}

variable "network" {
  description = "Name of the VPC network to use for creating firewall rules."
  type        = string
}

variable "subnetwork" {
  description = "Self link of the VPC subnet to use for the internal interface."
  type        = string
}

variable "instance_count" {
  type        = number
  description = "The number of instances to create"
  default     = 1
}

variable "instance_type" {
  type        = string
  description = "The GCE instance type to create"
  default     = "n2-standard-4"
}

variable "vm_tags" {
  description = "Additional network tags for the instances."
  type        = list(string)
  default     = ["jumpwire"]
}

variable "boot_disk_size" {
  description = "Size of the boot disk."
  type        = number
  default     = 10
}

variable "scopes" {
  description = "Instance scopes."
  type        = list(string)
  default = [
    "https://www.googleapis.com/auth/devstorage.read_only",
    "https://www.googleapis.com/auth/logging.write",
    "https://www.googleapis.com/auth/monitoring.write",
    "https://www.googleapis.com/auth/service.management.readonly",
    "https://www.googleapis.com/auth/servicecontrol",
    "https://www.googleapis.com/auth/trace.append",
  ]
}

variable "service_account" {
  description = "Instance service account."
  type        = string
  default     = ""
}

variable "prefix" {
  type        = string
  description = "Prefix to prepend to resource names."
  default     = "jumpwire"
}

variable "stackdriver_logging" {
  description = "Enable the Stackdriver logging agent."
  type        = bool
  default     = true
}

variable "stackdriver_monitoring" {
  description = "Enable the Stackdriver monitoring agent."
  type        = bool
  default     = true
}

variable "labels" {
  description = "Labels to be attached to the resources"
  type        = map(string)
  default = {
    service = "jumpwire"
  }
}

variable "token" {
  type        = string
  description = "The JumpWire cluster token, which will be stored as a secret and injected into the container runtime as an environment variable"
  sensitive   = true
}

variable "domain" {
  type        = string
  description = "Domain to use when connecting to the JumpWire cluster."
  default     = "localhost"
}

variable "ssh_keys" {
  type        = map(string)
  description = "Username and public keys that are allowed to SSH into the instances."
  default     = {}
}

variable "tls_key" {
  type        = string
  description = "PEM encoded TLS key for use when a client connects to the JumpWire proxy. It should be valid for `domain`."
  sensitive   = true
  default     = ""
}

variable "tls_cert" {
  type        = string
  description = "PEM encoded TLS certificate for use when a client connects to the JumpWire proxy. It should be valid for `domain`."
  default     = ""
}
