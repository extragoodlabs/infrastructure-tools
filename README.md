# Infrastructure tooling for managing installations of JumpWire

![Lego builders building legos](infrastructure-tools.png)

This repository contains Infrastructure-as-Code templates for various tools and systems. They can be cloned and used directly, or serve as a reference for your own deployments of JumpWire.

## Container distributions for JumpWire

JumpWire releases a container distribution for the "JumpWire engine", which can run alongside application and database servers in your private network. This ensures that data never leaves your cloud, and gives full control for scaling a cluster of JumpWire engines to account for specific workloads. The container is hosted on GitHub Container Registry at `ghcr.io/jumpwire-ai/jumpwire`.

For more information on running JumpWire, please refer to our [documentation site](https://docs.jumpwire.io/deployment).

The following templates and tools are available or in development:

### Kubernetes Helm

JumpWire's helm repository is located at [https://charts.jumpwire.io](https://charts.jumpwire.io)

It can be added to your Kubernetes project by running the following command:

```shell
$ helm repo add jumpwire https://charts.jumpwire.io
```

See our documentation for more instructions on [running JumpWire with helm](https://docs.jumpwire.io/self-hosting-with-helm)

### Amazon Web Services (AWS)

A Terraform file for deploying JumpWire using AWS Elastic Container Service is under [this subdirectory](terraform/aws/ecs), with a detailed [README.md](terraform/aws/ecs/README.md)

For instructions on how to set up JumpWire through the AWS console, see [this page in our documentation](https://docs.jumpwire.io/self-hosting-with-aws-ecs)

### Google Cloud Platform (GCP)

A Terraform file for deploying JumpWire using Google Compute Engine is under [this subdirectory](terraform/gcp/gce), with a detailed [README.md](terraform/gcp/gce/README.md)
