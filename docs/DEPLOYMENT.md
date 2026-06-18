# Cargo Tracker - AWS ECS Fargate Deployment Guide

## Table of Contents
1. [Overview](#overview)
2. [Prerequisites](#prerequisites)
3. [Local Development Setup](#local-development-setup)
4. [Building Docker Image](#building-docker-image)
5. [AWS ECS Fargate Prerequisites](#aws-ecs-fargate-prerequisites)
6. [ECS Task Definition Explained](#ecs-task-definition-explained)
7. [ECS Service Configuration](#ecs-service-configuration)
8. [Deployment to AWS ECS Fargate](#deployment-to-aws-ecs-fargate)
9. [Monitoring and Logging](#monitoring-and-logging)
10. [Troubleshooting](#troubleshooting)
11. [Scaling and Management](#scaling-and-management)
12. [Security Considerations](#security-considerations)

---

## Overview

This guide provides comprehensive instructions for deploying the **Eclipse Cargo Tracker** application (a Jakarta EE 10 application) to AWS ECS Fargate. The application is containerized using Docker and deployed as a serverless container on AWS ECS.

### Application Details
- **Framework**: Jakarta EE 10
- **Application Server**: Payara Micro 6.2025.3
- **Java Version**: 11
- **Build Tool**: Maven
- **Package Type**: WAR
- **Default Port**: 8080
- **Database**: H2 (embedded for development), PostgreSQL (production)

---

## Prerequisites

### Required Software
1. **Docker Desktop** (v20.10 or later)
   - Download: https://www.docker.com/products/docker-desktop
   - Verify: `docker --version`

2. **AWS CLI** (v2.x)
   - Download: https://aws.amazon.com/cli/
   - Verify: `aws --version`
   - Configure: `aws configure`

3. **Git** (for cloning repository)
   - Download: https://git-scm.com/
   - Verify: `git --version`

4. **Java 11 JDK** (for local development)
   - Download: https://adoptium.net/
   - Verify: `java -version`

5. **Maven 3.9+** (for local builds)
   - Download: https://maven.apache.org/download.cgi
   - Verify: `mvn -version`

### AWS Account Requirements
- Active AWS account with appropriate permissions
- IAM user with permissions for:
  - ECS (create/manage clusters, services, tasks)
  - ECR (create/manage repositories, push images)
  - VPC (create/manage networking resources)
  - CloudWatch Logs (create/view log groups)
  - IAM (create/manage roles)
  - Elastic Load Balancing (optional, for ALB)

---

## Local Development Setup

### 1. Clone the Repository
```bash
git clone <repository-url>
cd BackendServices
```

### 2. Build the Application Locally
```bash
# Using Maven
mvn clean package

# The WAR file will be generated at:
# target/cargo-tracker.war
```

### 3. Run with Docker Compose
```bash
# Build and start the application
docker-compose up --build

# Access the application
# http://localhost:8080/cargo-tracker/
```

### 4. Stop the Application
```bash
docker-compose down
```

---

## Building Docker Image

### Using the Build Script

#### Linux/macOS
```bash
cd scripts
chmod +x build-push.sh
./build-push.sh
```

#### Windows
```cmd
cd scripts
build-push.bat
```

### Script Features
- Interactive registry selection (AWS ECR or Docker Hub)
- Automatic ECR repository creation
- Image tag sanitization
- Authentication handling
- Build and push automation

### Manual Docker Build
```bash
# Build the image
docker build -t cargo-tracker:latest .

# Tag for registry
docker tag cargo-tracker:latest <registry>/<repository>:latest

# Push to registry
docker push <registry>/<repository>:latest
```

---

## AWS ECS Fargate Prerequisites

### 1. Create VPC and Networking Resources

#### Option A: Use Default VPC
```bash
# List default VPC
aws ec2 describe-vpcs --filters "Name=isDefault,Values=true" --region us-east-1

# List subnets in default VPC
aws ec2 describe-subnets --filters "Name=vpc-id,Values=<vpc-id>" --region us-east-1
```

#### Option B: Create New VPC
```bash
# Create VPC
aws ec2 create-vpc --cidr-block 10.0.0.0/16 --region us-east-1

# Create subnets (at least 2 in different AZs)
aws ec2 create-subnet --vpc-id <vpc-id> --cidr-block 10.0.1.0/24 --availability-zone us-east-1a
aws ec2 create-subnet --vpc-id <vpc-id> --cidr-block 10.0.2.0/24 --availability-zone us-east-1b

# Create Internet Gateway
aws ec2 create-internet-gateway
aws ec2 attach-internet-gateway --vpc-id <vpc-id> --internet-gateway-id <igw-id>

# Create Route Table
aws ec2 create-route-table --vpc-id <vpc-id>
aws ec2 create-route --route-table-id <rt-id> --destination-cidr-block 0.0.0.0/0 --gateway-id <igw-id>
```

### 2. Create Security Group
```bash
# Create security group
aws ec2 create-security-group \
  --group-name cargo-tracker-sg \
  --description "Security group for Cargo Tracker ECS tasks" \
  --vpc-id <vpc-id> \
  --region us-east-1

# Allow inbound HTTP traffic (port 8080)
aws ec2 authorize-security-group-ingress \
  --group-id <sg-id> \
  --protocol tcp \
  --port 8080 \
  --cidr 0.0.0.0/0 \
  --region us-east-1

# Allow inbound HTTP traffic (port 80) for ALB
aws ec2 authorize-security-group-ingress \
  --group-id <sg-id> \
  --protocol tcp \
  --port 80 \
  --cidr 0.0.0.0/0 \
  --region us-east-1
```

### 3. Create IAM Roles

#### ECS Task Execution Role
```bash
# Create trust policy file (trust-policy.json)
cat > trust-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "ecs-tasks.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF

# Create role
aws iam create-role \
  --role-name ecsTaskExecutionRole \
  --assume-role-policy-document file://trust-policy.json

# Attach managed policy
aws iam attach-role-policy \
  --role-name ecsTaskExecutionRole \
  --policy-arn arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy
```

#### ECS Task Role (for application permissions)
```bash
# Create role
aws iam create-role \
  --role-name ecsTaskRole \
  --assume-role-policy-document file://trust-policy.json

# Attach policies as needed (e.g., S3, DynamoDB, etc.)
```

### 4. Create CloudWatch Log Group
```bash
aws logs create-log-group \
  --log-group-name /ecs/cargo-tracker \
  --region us-east-1
```

---

## ECS Task Definition Explained

### Key Components

#### 1. Launch Type Configuration
```json
{
  "requiresCompatibilities": ["FARGATE"],
  "networkMode": "awsvpc"
}
```
- **FARGATE**: Serverless compute engine for containers
- **awsvpc**: Each task gets its own ENI and private IP

#### 2. CPU and Memory
```json
{
  "cpu": "512",
  "memory": "1024"
}
```
**Valid Fargate CPU/Memory Combinations:**
- CPU: 256 (.25 vCPU) → Memory: 512, 1024, 2048 MB
- CPU: 512 (.5 vCPU) → Memory: 1024, 2048, 3072, 4096 MB
- CPU: 1024 (1 vCPU) → Memory: 2048-8192 MB
- CPU: 2048 (2 vCPU) → Memory: 4096-16384 MB
- CPU: 4096 (4 vCPU) → Memory: 8192-30720 MB

#### 3. Execution Role
```json
{
  "executionRoleArn": "arn:aws:iam::<account-id>:role/ecsTaskExecutionRole"
}
```
- Allows ECS to pull images from ECR
- Allows ECS to write logs to CloudWatch

#### 4. Container Definition
```json
{
  "containerDefinitions": [
    {
      "name": "cargo-tracker",
      "image": "<ecr-uri>:latest",
      "essential": true,
      "portMappings": [
        {
          "containerPort": 8080,
          "protocol": "tcp"
        }
      ],
      "environment": [
        {
          "name": "JAVA_OPTS",
          "value": "-Xmx512m -Xms256m"
        }
      ],
      "logConfiguration": {
        "logDriver": "awslogs",
        "options": {
          "awslogs-group": "/ecs/cargo-tracker",
          "awslogs-region": "us-east-1",
          "awslogs-stream-prefix": "ecs"
        }
      }
    }
  ]
}
```

---

## ECS Service Configuration

### Key Components

#### 1. Launch Type
```json
{
  "launchType": "FARGATE",
  "platformVersion": "LATEST"
}
```

#### 2. Network Configuration
```json
{
  "networkConfiguration": {
    "awsvpcConfiguration": {
      "subnets": ["subnet-xxx", "subnet-yyy"],
      "securityGroups": ["sg-xxx"],
      "assignPublicIp": "ENABLED"
    }
  }
}
```
- **subnets**: At least 2 subnets in different AZs for high availability
- **securityGroups**: Security group allowing inbound traffic on port 8080
- **assignPublicIp**: ENABLED for internet access (or use NAT Gateway)

#### 3. Deployment Configuration
```json
{
  "deploymentConfiguration": {
    "maximumPercent": 200,
    "minimumHealthyPercent": 50,
    "deploymentCircuitBreaker": {
      "enable": true,
      "rollback": true
    }
  }
}
```
- **maximumPercent**: Maximum tasks during deployment (200% = 2x desired count)
- **minimumHealthyPercent**: Minimum healthy tasks during deployment (50%)
- **deploymentCircuitBreaker**: Automatic rollback on deployment failure

#### 4. Load Balancer (Optional)
```json
{
  "loadBalancers": [
    {
      "targetGroupArn": "arn:aws:elasticloadbalancing:...",
      "containerName": "cargo-tracker",
      "containerPort": 8080
    }
  ],
  "healthCheckGracePeriodSeconds": 300
}
```

---

## Deployment to AWS ECS Fargate

### Using the Deployment Script

#### Linux/macOS
```bash
cd scripts
chmod +x deploy-image.sh
./deploy-image.sh
```

#### Windows
```cmd
cd scripts
deploy-image.bat
```

### Script Workflow
1. **Prompts for Configuration**
   - AWS Region
   - ECS Cluster Name
   - Docker Image URI
   - VPC and Subnet IDs
   - Security Group ID
   - Load Balancer requirement

2. **Creates Resources**
   - ECS Cluster (if not exists)
   - CloudWatch Log Group
   - Application Load Balancer (if requested)
   - Target Group (if ALB requested)

3. **Registers Task Definition**
   - Replaces placeholders with actual values
   - Registers with ECS

4. **Creates/Updates Service**
   - Creates new service if doesn't exist
   - Updates existing service with new task definition

5. **Waits for Stability**
   - Monitors deployment progress
   - Waits for tasks to reach running state

### Manual Deployment Steps

#### 1. Register Task Definition
```bash
aws ecs register-task-definition \
  --cli-input-json file://ecs/task-definition.json \
  --region us-east-1
```

#### 2. Create ECS Cluster
```bash
aws ecs create-cluster \
  --cluster-name cargo-tracker-cluster \
  --region us-east-1
```

#### 3. Create Service
```bash
aws ecs create-service \
  --cli-input-json file://ecs/service-definition.json \
  --region us-east-1
```

#### 4. Update Service (for redeployment)
```bash
aws ecs update-service \
  --cluster cargo-tracker-cluster \
  --service cargo-tracker-service \
  --force-new-deployment \
  --region us-east-1
```

---

## Monitoring and Logging

### CloudWatch Logs

#### View Logs in Console
1. Navigate to CloudWatch → Log groups
2. Select `/ecs/cargo-tracker`
3. View log streams for each task

#### View Logs via CLI
```bash
# Tail logs in real-time
aws logs tail /ecs/cargo-tracker --follow --region us-east-1

# Filter logs
aws logs filter-log-events \
  --log-group-name /ecs/cargo-tracker \
  --filter-pattern "ERROR" \
  --region us-east-1
```

### ECS Service Metrics

#### View in Console
1. Navigate to ECS → Clusters → cargo-tracker-cluster
2. Select service → Metrics tab
3. View CPU, Memory, Network metrics

#### View via CLI
```bash
# Describe service
aws ecs describe-services \
  --cluster cargo-tracker-cluster \
  --services cargo-tracker-service \
  --region us-east-1

# List tasks
aws ecs list-tasks \
  --cluster cargo-tracker-cluster \
  --service-name cargo-tracker-service \
  --region us-east-1

# Describe task
aws ecs describe-tasks \
  --cluster cargo-tracker-cluster \
  --tasks <task-arn> \
  --region us-east-1
```

### Application Health Checks

The application exposes the following endpoints:
- **Main Application**: `http://<alb-dns>/cargo-tracker/`
- **Health Check**: Handled by ALB target group health checks

---

## Troubleshooting

### Common Issues

#### 1. Task Fails to Start
**Symptoms**: Tasks transition from PENDING to STOPPED

**Possible Causes**:
- Invalid CPU/memory combination
- Image pull errors (ECR permissions)
- Container startup failures

**Solutions**:
```bash
# Check task stopped reason
aws ecs describe-tasks \
  --cluster cargo-tracker-cluster \
  --tasks <task-arn> \
  --region us-east-1 \
  --query 'tasks[0].stoppedReason'

# Check CloudWatch logs
aws logs tail /ecs/cargo-tracker --follow --region us-east-1

# Verify ECR permissions
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin <account-id>.dkr.ecr.us-east-1.amazonaws.com
```

#### 2. Service Fails to Reach Steady State
**Symptoms**: Service stuck in deployment, tasks continuously restarting

**Possible Causes**:
- Health check failures
- Application startup errors
- Insufficient resources

**Solutions**:
```bash
# Check service events
aws ecs describe-services \
  --cluster cargo-tracker-cluster \
  --services cargo-tracker-service \
  --region us-east-1 \
  --query 'services[0].events[0:10]'

# Increase health check grace period
# Edit service-definition.json:
"healthCheckGracePeriodSeconds": 600

# Check application logs
aws logs tail /ecs/cargo-tracker --follow --region us-east-1
```

#### 3. Cannot Access Application
**Symptoms**: ALB returns 503 or connection timeout

**Possible Causes**:
- Security group not allowing traffic
- Target group health checks failing
- Tasks not registered with target group

**Solutions**:
```bash
# Check target group health
aws elbv2 describe-target-health \
  --target-group-arn <target-group-arn> \
  --region us-east-1

# Verify security group rules
aws ec2 describe-security-groups \
  --group-ids <sg-id> \
  --region us-east-1

# Check ALB listener rules
aws elbv2 describe-listeners \
  --load-balancer-arn <alb-arn> \
  --region us-east-1
```

#### 4. High Memory Usage
**Symptoms**: Tasks killed due to OOM (Out of Memory)

**Solutions**:
```bash
# Increase task memory in task-definition.json
"memory": "2048"

# Adjust JVM heap size in environment variables
"JAVA_OPTS": "-Xmx1536m -Xms512m -XX:MaxRAMPercentage=75.0"

# Re-register task definition and update service
```

#### 5. Database Connection Issues
**Symptoms**: Application fails to connect to database

**Solutions**:
- Verify database connection string in environment variables
- Check security group allows traffic from ECS tasks to database
- Verify database credentials
- For H2 embedded: Ensure volume is mounted correctly
- For PostgreSQL: Verify RDS security group and connection string

---

## Scaling and Management

### Manual Scaling

#### Update Desired Count
```bash
aws ecs update-service \
  --cluster cargo-tracker-cluster \
  --service cargo-tracker-service \
  --desired-count 4 \
  --region us-east-1
```

### Auto Scaling

#### Create Auto Scaling Target
```bash
aws application-autoscaling register-scalable-target \
  --service-namespace ecs \
  --resource-id service/cargo-tracker-cluster/cargo-tracker-service \
  --scalable-dimension ecs:service:DesiredCount \
  --min-capacity 2 \
  --max-capacity 10 \
  --region us-east-1
```

#### Create Scaling Policy (CPU-based)
```bash
aws application-autoscaling put-scaling-policy \
  --service-namespace ecs \
  --resource-id service/cargo-tracker-cluster/cargo-tracker-service \
  --scalable-dimension ecs:service:DesiredCount \
  --policy-name cpu-scaling-policy \
  --policy-type TargetTrackingScaling \
  --target-tracking-scaling-policy-configuration file://scaling-policy.json \
  --region us-east-1
```

**scaling-policy.json**:
```json
{
  "TargetValue": 70.0,
  "PredefinedMetricSpecification": {
    "PredefinedMetricType": "ECSServiceAverageCPUUtilization"
  },
  "ScaleInCooldown": 300,
  "ScaleOutCooldown": 60
}
```

### Blue/Green Deployments

#### Using AWS CodeDeploy
1. Create CodeDeploy application
2. Create deployment group with ECS configuration
3. Configure traffic shifting (linear, canary, all-at-once)
4. Deploy new task definition revision

```bash
# Create CodeDeploy application
aws deploy create-application \
  --application-name cargo-tracker-app \
  --compute-platform ECS \
  --region us-east-1

# Create deployment group
aws deploy create-deployment-group \
  --application-name cargo-tracker-app \
  --deployment-group-name cargo-tracker-dg \
  --service-role-arn <codedeploy-role-arn> \
  --ecs-services clusterName=cargo-tracker-cluster,serviceName=cargo-tracker-service \
  --load-balancer-info targetGroupInfoList=[{name=cargo-tracker-tg}] \
  --blue-green-deployment-configuration file://blue-green-config.json \
  --region us-east-1
```

---

## Security Considerations

### 1. Network Security
- Use private subnets with NAT Gateway for production
- Restrict security group rules to minimum required ports
- Use VPC endpoints for AWS services (ECR, CloudWatch, etc.)

### 2. IAM Permissions
- Follow principle of least privilege
- Use separate task execution and task roles
- Rotate IAM credentials regularly
- Use IAM roles for service accounts

### 3. Container Security
- Use non-root user in Dockerfile (already implemented)
- Scan images for vulnerabilities (AWS ECR scanning)
- Keep base images updated
- Use specific image tags (not `latest` in production)

### 4. Secrets Management
- Use AWS Secrets Manager or Parameter Store for sensitive data
- Never hardcode credentials in task definitions
- Use environment variables or secrets in task definition

**Example with Secrets Manager**:
```json
{
  "secrets": [
    {
      "name": "DB_PASSWORD",
      "valueFrom": "arn:aws:secretsmanager:us-east-1:123456789:secret:db-password"
    }
  ]
}
```

### 5. Logging and Monitoring
- Enable CloudWatch Container Insights
- Set up CloudWatch alarms for critical metrics
- Enable AWS CloudTrail for API auditing
- Use AWS Config for compliance monitoring

### 6. Data Protection
- Enable encryption at rest for EBS volumes
- Use HTTPS/TLS for data in transit
- Enable ALB access logs
- Implement proper backup strategies

---

## Additional Resources

### AWS Documentation
- [Amazon ECS Developer Guide](https://docs.aws.amazon.com/ecs/)
- [AWS Fargate User Guide](https://docs.aws.amazon.com/AmazonECS/latest/userguide/what-is-fargate.html)
- [ECS Task Definitions](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/task_definitions.html)
- [ECS Service Definition](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/service_definition_parameters.html)

### Jakarta EE Resources
- [Jakarta EE Documentation](https://jakarta.ee/)
- [Payara Documentation](https://docs.payara.fish/)
- [Eclipse Cargo Tracker](https://github.com/eclipse-ee4j/cargotracker)

### Docker Resources
- [Docker Documentation](https://docs.docker.com/)
- [Dockerfile Best Practices](https://docs.docker.com/develop/develop-images/dockerfile_best-practices/)

---

## Support and Contribution

For issues, questions, or contributions:
- GitHub Issues: [Project Repository]
- Documentation: [Project Wiki]
- Community: [Discussion Forum]

---

**Last Updated**: 2025
**Version**: 1.0
**Maintained By**: DevOps Team
