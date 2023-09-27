# Terraform Template for JumpWire on Google Compute Engine

This folder contains a Terraform template to deploy the JumpWire engine.

The following resources are created by this Terraform template:
- A GCE instance
- An external static IPv4 attached to the GCE instance
- Firewall rules pointing to the GCE instance

## Sample usage

This is a sample module invocation:

```hcl
data "local_file" "public_ssh_key" {
  filename = "id_rsa.pub"
}

data "local_sensitive_file" "tls_key" {
  filename = "${path.module}/tls.key"
}

data "local_file" "tls_cert" {
  filename = "${path.module}/tls.crt"
}

data "local_file" "config" {
  filename = "${path.module}/jumpwire.yaml"
}

resource "random_password" "token" {
  length = 32
}

resource "random_password" "key" {
  length = 32
}

module "jumpwire-gce" {
  source                = "github.com/extragoodlabs/infrastructure-tools//terraform/gcp/gce"
  instance_count        = 1
  project_id            = "my-project"
  region                = "europe-west3"
  zone                  = "europe-west3-c"
  network               = "my-network"
  subnetwork            = "https://www.googleapis.com/compute/v1/projects/my-project/regions/europe-west3/subnetworks/my-subnetwork"
  domain                = "jumpwire.example.com"
  ssh_keys              = {
    my_user = data.local_file.public_ssh_key.content
  }
  env = {
    JUMPWIRE_ROOT_TOKEN     = base64encode(random_password.token.result)
    JUMPWIRE_ENCRYPTION_KEY = base64encode(random_password.key.result)
  }
  tls_key  = data.local_file.tls_key.content
  tls_cert = data.local_file.tls_cert.content
  config   = data.local_file.config.content
}

output "external_addresses" {
  description = "List of instance external addresses."
  value       = module.jumpwire-gce.external_addresses
}

output "api_token" {
  description = "Bearer token for authenticating to the API."
  value       = base64encode(random_password.token.result)
  sensitive   = true
}
```

## Inputs

**JumpWire Enterprise**: The JumpWire controller token is listed on the JumpWire cluster's [configuration page](https://app.jumpwire.io/clusters) and is set as the environment variable `JUMPWIRE_TOKEN`.

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| boot\_disk\_size | Size of the boot disk. | `number` | `10` | no |
| config | YAML string of JumpWire configuration. This will be loaded as a file on disk. | `string` | "" | no |
| domain | Domain that will be used to connect to the cluster. | `string` | `"localhost"` | no |
| env | Environment variables to assign to JumpWire. | `map(string)` | {} | no |
| instance\_count | Number of instances to create. | `number` | `1` | no |
| instance\_type | Instance machine type. | `string` | `"n2-standard-4"` | no |
| labels | Labels to be attached to the resources | `map(string)` | <pre>{<br>  "service": "jumpwire"<br>}</pre> | no |
| network | Name of the VPC subnet to use for firewall rules. | `string` | n/a | yes |
| prefix | Prefix to prepend to resource names. | `string` | `"jumpwire"` | no |
| project\_id | Project id where the instances will be created. | `string` | n/a | yes |
| region | Region for external addresses. | `string` | n/a | yes |
| scopes | Instance scopes. | `list(string)` | <pre>[<br>  "https://www.googleapis.com/auth/devstorage.read_only",<br>  "https://www.googleapis.com/auth/logging.write",<br>  "https://www.googleapis.com/auth/monitoring.write",<br>  "https://www.googleapis.com/auth/service.management.readonly",<br>  "https://www.googleapis.com/auth/servicecontrol",<br>  "https://www.googleapis.com/auth/trace.append"<br>]</pre> | no |
| service\_account | Instance service account. | `string` | `""` | no |
| ssh\_keys | Username and public keys that are allowed to SSH into the instances. | `map` | `{}` | no |
| stackdriver\_logging | Enable the Stackdriver logging agent. | `bool` | `true` | no |
| stackdriver\_monitoring | Enable the Stackdriver monitoring agent. | `bool` | `true` | no |
| subnetwork | Self link of the VPC subnet to use for the internal interface. | `string` | n/a | yes |
| tls\_cert | PEM encoded TLS public certificate for use when a client connects to the JumpWire proxy. It should be valid for `domain`. | `string` | `""` | no |
| tls\_key | PEM encoded TLS private key for use when a client connects to the JumpWire proxy. It should be valid for `domain`. | `string` | `""` | no |
| vm\_tags | Additional network tags for the instances. | `list(string)` | `["jumpwire"]` | no |
| zone | Instance zone. | `string` | n/a | yes |

## Outputs

| Name | Description |
|------|-------------|
| instances | Instance name => address map. |
| external\_addresses | List of instance external addresses. |
| names | List of instance names. |
