### Example architecture for a stateful NodeJS application on AWS

In this example, we will set up a backend for [Forest Admin](https://www.forestadmin.com/), as a NodeJS application using [Express](https://www.npmjs.com/package/express) and [Sequelize](https://www.npmjs.com/package/sequelize). This NodeJS app will be packaged as a Docker container, and run on AWS using ECS Fargate, HTTP Gateway, and Application Load Balancer.

> Don't just visualize your data — handle it in the most convenient way possible. With Forest Admin, your business teams can manipulate and organize data through one simple interface.

Forest Admin is a tool for visualizing and manipulating data sources, replacing internally built tools with the ability to perform CRUD directly against tables. It also supports dashboarding arbitrary queries, creating alerts, etc.

Here we use Forest Admin to demonstrate how JumpWire can be plugged into existing application without modification. In this case, we configure Sequelize with a PostgreSQL URL from a JumpWire proxy, to connect to the source RDS instance.

### Getting Started

Before diving into the code, sign up for an account on [Forest Admin](https://app.forestadmin.com/signup). This tool also uses a hybrid deployment model (similar to JumpWire) - Forest Admin hosts a SaaS dashboard that connects to a backend run "on premise", aka inside our VPC. This ensures that data accessed by Forest Admin front-end stays (mostly) local to our private cloud, as it's loaded client side by the browswer directly from the backend.

There is a nice guided setup for Forest Admin, for creating new projects. We'll need to wait until the infrastructure is set up to have the url for the backend, but you can intially point Forest Admin to your localhost running the backend with `yarn`. Take note of the ENV and AUTH secrets provided after creating the project in Forest Admin, we'll pass those as variables to our Terraform script for secure storage.

### Infrastructure as Code

Terraform is used to define all of the AWS services necessary to host the NodeJS application - as a Docker container running on Fargate. Terraform will also build the docker container locally and use the AWS cli to upload it to an ECR repository.

The infrastructure as code sets up an [http api private integration](https://docs.aws.amazon.com/apigateway/latest/developerguide/http-api-private-integration.html). We've defined the following AWS resources in the included in the Terraform [template](infrastructure/main.tf).

!['AWS HTTP API Private Integration'](https://docs.aws.amazon.com/images/apigateway/latest/developerguide/images/private-integration.png)

### **SecretsManager**

A SecretsManager secret containing JSON corresponding to environment variables that contain secrets. Secret values are passed into Terraform using sensitive variables, so the value is never printed or logged. Secrets are injected as environment variables to the Docker container task, ensuring that the value is never exposed.

The following secret values are required to run the example:

| Env var     | Terraform var | Description |
| ----------- | ------------- | ----------- |
| FOREST_ENV_SECRET | forest_env_secret | Environment secret supplied by Forest Admin when creating a project |
| FOREST_AUTH_SECRET | forest_auth_secret | Auth secret supplied by Forest Admin when creating a project |
| POSTGRESQL_URL | postgresql_url | Full url for PostgreSQL connection in the format of: postgresql://username:password@host:5432/storefront |

### **Elastic Container Repository**

A repository for uploading a Docker image, to be served by Fargate. We will reference the repository url and image tag in the container definition used by the Fargate task.

There is a `null_resource` used to build a Docker image locally and upload it to the repository using the aws cli -

```
resource "null_resource" "task_ecr_image_builder" {
  triggers = {
    ...
  }

  provisioner "local-exec" {
    working_dir = local.root_dir
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      aws ecr get-login-password --region ${var.region} --profile ${var.aws_profile} | docker login --username AWS --password-stdin ${local.aws_account_id}.dkr.ecr.${var.region}.amazonaws.com
      docker image build -t ${aws_ecr_repository.task_repository.repository_url}:latest .
      docker push ${aws_ecr_repository.task_repository.repository_url}:latest
    EOT
  }
}
```

### **IAM Profiles**
We need to extend the `service-role/AmazonECSTaskExecutionRolePolicy` with extra allowed actions to read secrets from Secrets Manager. This is done through an inline policy attached to the IAM role

```
Statement = [
  {
    Action = [
      "secretsmanager:GetSecretValue",
      "kms:Decrypt",
      "ssm:GetParameters",
    ]
    Effect   = "Allow"
    Resource = "*"
  },
]
```

### **Application Load Balancer**
An ALB will connect our API Gateway to Fargate task containers running in private subnets of our VPC. The Elastic Container Service will use this load balancer to distribute requests across tasks in a cluster. Port will be set at 80 and the protocol is `HTTP`.

### **Elastic Container Service**
We use ECS to run our Docker container, creating a Service, Cluster and Task. The Service will use the ALB referenced above, the Cluster will use Fargate capacity providers, and the Task will have a container definition referencing the repository url and image.

The container definition also loads secrets from Secrets Manager as environment variables for the container runtime, as well as port mappings to the host.

The Service will manage the ALB, registering and deregistering targets for each running task in the ALB's target group.

### **API Gateway v2**
An HTTP API Gateway will receive requests from the internet and proxy them to the ALB. It will reach the ALB through a integration with vpc link, since the ALB is running in our private subnet. Wiring up the API was the trickiest part to getting this all to work, especially since we launch the tasks in a private vpc that also contains our RDS instance. This keeps all of our data in a private network, on servers that are never addressable from the internet.

