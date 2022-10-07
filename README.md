## Infrastructure tooling for managing installations of JumpWire

![Lego builders building legos](infrastructure-tools.png)

This repository contains Infrastructure-as-Code templates for various tools and systems. They can be cloned and used directly, or serve as a reference for your own deployments of JumpWire.

#### Container distributions for JumpWire

JumpWire releases a container distribution for the "JumpWire engine", which can run alongside application and database servers in your private network. This ensures that data never leaves your cloud, and gives full control for scaling a cluster of JumpWire engines to account for specific workloads. The container is hosted on [dockerhub](https://hub.docker.com/r/jumpwire/jumpwire).

For more information on running JumpWire, please refer to our [documentation site](https://docs.jumpwire.ai/deployment).

The following templates and tools are available or in development:

### Kubernetes Helm

JumpWire's helm repository is located at [https://charts.jumpwire.ai](https://charts.jumpwire.ai)

It can be added to your Kubernetes project by running the following command:

```shell
$ helm repo add jumpwire https://charts.jumpwire.ai
```

See our documentation for more instructions on [running JumpWire with helm](https://docs.jumpwire.ai/self-hosting-with-helm)

### AWS Terraform

A Terraform file for deploying JumpWire using ECS is under [this subdirectory](terraform/aws/ecs), with a detailed [README.md](terraform/aws/ecs/README.md)

For instructions on how to set up JumpWire through the AWS console, see [this page in our documentation](https://docs.jumpwire.ai/self-hosting-with-aws-ecs)

### AWS CDK

_coming soon_

### GCP Terraform

_coming soon_