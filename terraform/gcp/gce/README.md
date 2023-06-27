# Terraform Template for JumpWire on Google Compute Engine

This folder contains a Terraform template to deploy the JumpWire engine.

The following resources are created by this Terraform template:
- A GCE instance
- An external static IPv4 attached to the GCE instance
- Firewall rules pointing to the GCE instance

## Sample usage

This is a sample module invocation:

```hcl
module "jumpwire-gce" {
  source                = "github.com/jumpwire-ai/infrastructure-tools//terraform/gcp/gce"
  instance_count        = 1
  project_id            = "my-project"
  region                = "europe-west3"
  zone                  = "europe-west3-c"
  network               = "my-network"
  subnetwork            = "https://www.googleapis.com/compute/v1/projects/my-project/regions/europe-west3/subnetworks/my-subnetwork"
  token                 = "my-cluster-token"
  domain                = "jumpwire.example.com"
  ssh_keys              = {
      my_user = local_file.my_public_ssh_key.content
  }
  tls_key = local_file.tls_key.content
  tls_cert = local_file.tls_cert.content
}
```

## Inputs

The value needed for `token` is the authentication token listed on your JumpWire cluster's [configuration page](https://app.jumpwire.io/clusters)


| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| boot\_disk\_size | Size of the boot disk. | `number` | `10` | no |
| domain | Domain that will be used to connect to the cluster. | `string` | `"localhost"` | no |
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
| token | JumpWire cluster token. | `string` | n/a | yes |
| vm\_tags | Additional network tags for the instances. | `list(string)` | `["jumpwire"]` | no |
| zone | Instance zone. | `string` | n/a | yes |

## Outputs

| Name | Description |
|------|-------------|
| instances | Instance name => address map. |
| external\_addresses | List of instance external addresses. |
| names | List of instance names. |
