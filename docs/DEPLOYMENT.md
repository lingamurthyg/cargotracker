# Cargo Tracker - AWS ECS Fargate Deployment Guide

## Table of Contents
1. [Overview](#overview)
2. [Prerequisites](#prerequisites)
3. [Local Development Setup](#local-development-setup)
4. [Building and Pushing Docker Images](#building-and-pushing-docker-images)
5. [AWS ECS Fargate Prerequisites](#aws-ecs-fargate-prerequisites)
6. [ECS Fargate Setup](#ecs-fargate-setup)
7. [ECS Task Definition Explained](#ecs-task-definition-explained)
8. [ECS Service Configuration](#ecs-service-configuration)
9. [ECS Fargate Deployment Walkthrough](#ecs-fargate-deployment-walkthrough)
10. [Configuration Management](#configuration-management)
11. [Monitoring and Logging](#monitoring-and-logging)
12. [Troubleshooting](#troubleshooting)
13. [Scaling and Management](#scaling-and-management)
14. [Security Considerations](#security-considerations)
15. [Technology-Specific Notes](#technology-specific-notes)

---

## Overview

This guide provides comprehensive instructions for deploying the **Eclipse Cargo Tracker** application, a Jakarta EE 10 application, to AWS ECS Fargate. The application demonstrates Domain-Driven Design (DDD) principles and uses Payara Micro as the application server.

**Application Details:**
- **Framework**: Jakarta EE 10
- **Application Server**: Payara Micro 6.2025.3
- **Java Version**: 11
- **Build Tool**: Maven
- **Package Type**: WAR
- **Default Port**: 8080
- **Database**: H2 (embedded) or PostgreSQL (cloud profile)

---

## Prerequisites

### Required Software
- **Docker**: Version 20.10 or higher
- **Docker Compose**: Version 2.0 or higher
- **AWS CLI**: Version 2.x
- **Maven**: Version 3.6 or higher (for local builds)
- **Java JDK**: Version 11 or higher
- **Git**: For version control

### AWS Account Requirements
- Active AWS account with appropriate permissions
- IAM user with permissions for:
  - ECS (Elastic Container Service)
  - ECR (Elastic Container Registry)
  - VPC and networking
  - CloudWatch Logs
  - IAM role creation
  - Application Load Balancer (optional)

### System Requirements
- **Memory**: Minimum 4GB RAM for local development
- **Disk Space**: At least 10GB free space
- **Network**: Stable internet connection for pulling dependencies

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

# The WAR file will be generated at: target/cargo-tracker.war
```

### 3. Run with Docker Compose
```bash
# Build and start the application
docker-compose up --build

# Access the application
# Open browser: http://localhost:8080/cargo-tracker/
```

### 4. Stop the Application
```bash
docker-compose down
```

### 5. View Logs
```bash
# View real-time logs
docker-compose logs -f cargo-tracker

# View logs from specific container
docker logs cargo-tracker-app
```

---

## Building and Pushing Docker Images

### Using the Build Script (Linux/macOS)

```bash
cd scripts
chmod +x build-push.sh
./build-push.sh
```

**Script Features:**
- Interactive registry selection (AWS ECR or Docker Hub)
- Automatic ECR repository creation
- Image tag sanitization
- Authentication handling
- Progress feedback

**Example Workflow:**
1. Select registry type (1 for ECR, 2 for Docker Hub)
2. Enter registry credentials/details
3. Enter image tag (default: latest)
4. Script builds and pushes the image

### Using the Build Script (Windows)

```cmd
cd scripts
build-push.bat
```

### Manual Docker Build

```bash
# Build the image
docker build -t cargo-tracker:latest .

# Tag for ECR
docker tag cargo-tracker:latest 123456789.dkr.ecr.us-east-1.amazonaws.com/cargo-tracker:latest

# Push to ECR
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin 123456789.dkr.ecr.us-east-1.amazonaws.com
docker push 123456789.dkr.ecr.us-east-1.amazonaws.com/cargo-tracker:latest
```

---

## AWS ECS Fargate Prerequisites

### 1. VPC Configuration

**Create or identify a VPC with:**
- At least 2 public subnets in different Availability Zones
- Internet Gateway attached
- Route tables configured for internet access

```bash
# List available VPCs
aws ec2 describe-vpcs --region us-east-1

# List subnets in a VPC
aws ec2 describe-subnets --filters "Name=vpc-id,Values=vpc-xxxxx" --region us-east-1
```

### 2. Security Group Configuration

**Create a security group with the following rules:**

**Inbound Rules:**
- Port 8080 (TCP) - Application port
- Port 80 (TCP) - Load balancer (if using ALB)
- Port 443 (TCP) - HTTPS (if using SSL)

**Outbound Rules:**
- All traffic (0.0.0.0/0) - For pulling images and external connections

```bash
# Create security group
aws ec2 create-security-group \
  --group-name cargo-tracker-sg \
  --description "Security group for Cargo Tracker ECS tasks" \
  --vpc-id vpc-xxxxx \
  --region us-east-1

# Add inbound rule for application port
aws ec2 authorize-security-group-ingress \
  --group-id sg-xxxxx \
  --protocol tcp \
  --port 8080 \
  --cidr 0.0.0.0/0 \
  --region us-east-1
```

### 3. IAM Roles

**Create ECS Task Execution Role:**

```json
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
```

**Attach policies:**
- `AmazonECSTaskExecutionRolePolicy`
- `CloudWatchLogsFullAccess`

```bash
# Create execution role
aws iam create-role \
  --role-name ecsTaskExecutionRole \
  --assume-role-policy-document file://trust-policy.json

# Attach policies
aws iam attach-role-policy \
  --role-name ecsTaskExecutionRole \
  --policy-arn arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy
```

**Create ECS Task Role (optional):**
- For application-specific AWS service access
- S3, DynamoDB, SQS, etc.

### 4. CloudWatch Log Group

```bash
# Create log group
aws logs create-log-group \
  --log-group-name /ecs/cargo-tracker \
  --region us-east-1

# Set retention policy (optional)
aws logs put-retention-policy \
  --log-group-name /ecs/cargo-tracker \
  --retention-in-days 7 \
  --region us-east-1
```

---

## ECS Fargate Setup

### 1. Create ECS Cluster

```bash
aws ecs create-cluster \
  --cluster-name cargo-tracker-cluster \
  --region us-east-1
```

### 2. Create ECR Repository

```bash
aws ecr create-repository \
  --repository-name cargo-tracker \
  --region us-east-1
```

### 3. Push Docker Image to ECR

```bash
# Authenticate Docker to ECR
aws ecr get-login-password --region us-east-1 | \
  docker login --username AWS --password-stdin 123456789.dkr.ecr.us-east-1.amazonaws.com

# Build and push
docker build -t cargo-tracker:latest .
docker tag cargo-tracker:latest 123456789.dkr.ecr.us-east-1.amazonaws.com/cargo-tracker:latest
docker push 123456789.dkr.ecr.us-east-1.amazonaws.com/cargo-tracker:latest
```

---

## ECS Task Definition Explained

The task definition (`ecs/task-definition.json`) defines how your container runs on ECS Fargate.

### Key Components

**1. Launch Type Configuration:**
```json
{
  "requiresCompatibilities": ["FARGATE"],
  "networkMode": "awsvpc"
}
```
- `FARGATE`: Serverless compute engine
- `awsvpc`: Each task gets its own ENI and private IP

**2. CPU and Memory:**
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

**3. IAM Roles:**
```json
{
  "executionRoleArn": "arn:aws:iam::ACCOUNT_ID:role/ecsTaskExecutionRole",
  "taskRoleArn": "arn:aws:iam::ACCOUNT_ID:role/ecsTaskRole"
}
```
- **executionRoleArn**: Allows ECS to pull images and write logs
- **taskRoleArn**: Allows application to access AWS services

**4. Container Definition:**
```json
{
  "name": "cargo-tracker",
  "image": "IMAGE_URI",
  "essential": true,
  "portMappings": [
    {
      "containerPort": 8080,
      "protocol": "tcp"
    }
  ]
}
```

**5. Environment Variables:**
```json
{
  "environment": [
    {
      "name": "JAVA_OPTS",
      "value": "-Xmx512m -Xms256m -XX:+UseContainerSupport"
    }
  ]
}
```

**6. Logging Configuration:**
```json
{
  "logConfiguration": {
    "logDriver": "awslogs",
    "options": {
      "awslogs-group": "/ecs/cargo-tracker",
      "awslogs-region": "us-east-1",
      "awslogs-stream-prefix": "ecs"
    }
  }
}
```

---

## ECS Service Configuration

The service definition (`ecs/service-definition.json`) manages task deployment and scaling.

### Key Components

**1. Service Configuration:**
```json
{
  "serviceName": "cargo-tracker-service",
  "cluster": "cargo-tracker-cluster",
  "taskDefinition": "cargo-tracker-task",
  "desiredCount": 2,
  "launchType": "FARGATE"
}
```

**2. Network Configuration:**
```json
{
  "networkConfiguration": {
    "awsvpcConfiguration": {
      "subnets": ["subnet-xxxxx", "subnet-yyyyy"],
      "securityGroups": ["sg-xxxxx"],
      "assignPublicIp": "ENABLED"
    }
  }
}
```

**3. Deployment Configuration:**
```json
{
  "deploymentConfiguration": {
    "maximumPercent": 200,
    "minimumHealthyPercent": 50
  }
}
```
- **maximumPercent**: Maximum tasks during deployment (200% = 2x desired)
- **minimumHealthyPercent**: Minimum healthy tasks (50% = half must be healthy)

**4. Load Balancer (Optional):**
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

**5. Tags:**
```json
{
  "tags": [
    {
      "key": "Environment",
      "value": "production"
    }
  ]
}
```

---

## ECS Fargate Deployment Walkthrough

### Using the Deployment Script (Linux/macOS)

```bash
cd scripts
chmod +x deploy-image.sh
./deploy-image.sh
```

**Script Workflow:**
1. Prompts for AWS region and cluster name
2. Retrieves AWS account ID
3. Creates cluster if it doesn't exist
4. Prompts for network configuration (VPC, subnets, security group)
5. Prompts for Docker image URI
6. Asks if load balancer is needed
7. Creates ALB and target group (if requested)
8. Creates CloudWatch log group
9. Registers task definition
10. Creates or updates ECS service
11. Waits for service to stabilize
12. Displays deployment status and URLs

### Using the Deployment Script (Windows)

```cmd
cd scripts
deploy-image.bat
```

### Manual Deployment Steps

**1. Register Task Definition:**
```bash
aws ecs register-task-definition \
  --cli-input-json file://ecs/task-definition.json \
  --region us-east-1
```

**2. Create Service:**
```bash
aws ecs create-service \
  --cli-input-json file://ecs/service-definition.json \
  --region us-east-1
```

**3. Update Service (for redeployment):**
```bash
aws ecs update-service \
  --cluster cargo-tracker-cluster \
  --service cargo-tracker-service \
  --task-definition cargo-tracker-task:2 \
  --force-new-deployment \
  --region us-east-1
```

**4. Check Service Status:**
```bash
aws ecs describe-services \
  --cluster cargo-tracker-cluster \
  --services cargo-tracker-service \
  --region us-east-1
```

---

## Configuration Management

### Environment Variables

**Application Configuration:**
- `JAVA_OPTS`: JVM memory and performance settings
- `DB_DRIVER_CLASS`: Database driver class
- `DB_JDBC_URL`: Database connection URL
- `DB_USER`: Database username
- `DB_PASSWORD`: Database password
- `GRAPH_TRAVERSAL_URL`: Internal API endpoint
- `TZ`: Timezone (default: UTC)

**Updating Environment Variables:**

1. Update task definition with new environment variables
2. Register new task definition revision
3. Update service to use new revision

```bash
# Edit task definition
vim ecs/task-definition.json

# Register new revision
aws ecs register-task-definition \
  --cli-input-json file://ecs/task-definition.json \
  --region us-east-1

# Update service
aws ecs update-service \
  --cluster cargo-tracker-cluster \
  --service cargo-tracker-service \
  --task-definition cargo-tracker-task:3 \
  --force-new-deployment \
  --region us-east-1
```

### Using AWS Systems Manager Parameter Store

**Store sensitive configuration:**
```bash
# Store database password
aws ssm put-parameter \
  --name /cargo-tracker/db-password \
  --value "your-password" \
  --type SecureString \
  --region us-east-1
```

**Reference in task definition:**
```json
{
  "secrets": [
    {
      "name": "DB_PASSWORD",
      "valueFrom": "arn:aws:ssm:us-east-1:123456789:parameter/cargo-tracker/db-password"
    }
  ]
}
```

---

## Monitoring and Logging

### CloudWatch Logs

**View logs:**
```bash
# List log streams
aws logs describe-log-streams \
  --log-group-name /ecs/cargo-tracker \
  --region us-east-1

# Tail logs
aws logs tail /ecs/cargo-tracker --follow --region us-east-1
```

**CloudWatch Console:**
1. Navigate to CloudWatch → Log groups
2. Select `/ecs/cargo-tracker`
3. View log streams by task ID

### CloudWatch Metrics

**ECS Service Metrics:**
- CPUUtilization
- MemoryUtilization
- RunningTaskCount
- DesiredTaskCount

**View metrics:**
```bash
aws cloudwatch get-metric-statistics \
  --namespace AWS/ECS \
  --metric-name CPUUtilization \
  --dimensions Name=ServiceName,Value=cargo-tracker-service Name=ClusterName,Value=cargo-tracker-cluster \
  --start-time 2024-01-01T00:00:00Z \
  --end-time 2024-01-01T23:59:59Z \
  --period 3600 \
  --statistics Average \
  --region us-east-1
```

### Application Performance Monitoring

**Jakarta EE Monitoring:**
- Payara Micro provides built-in monitoring endpoints
- Access metrics at: `/metrics` (if MicroProfile Metrics enabled)
- Health checks at: `/health`

**Custom Monitoring:**
- Integrate with AWS X-Ray for distributed tracing
- Use CloudWatch Application Insights
- Configure custom CloudWatch alarms

---

## Troubleshooting

### Common Issues and Solutions

#### 1. Task Fails to Start

**Symptoms:**
- Tasks transition from PENDING to STOPPED
- No running tasks in service

**Possible Causes:**
- Invalid CPU/memory combination
- Image pull errors
- Network configuration issues
- IAM permission issues

**Solutions:**
```bash
# Check stopped tasks
aws ecs describe-tasks \
  --cluster cargo-tracker-cluster \
  --tasks <task-id> \
  --region us-east-1

# Check stopped reason
aws ecs describe-tasks \
  --cluster cargo-tracker-cluster \
  --tasks <task-id> \
  --query 'tasks[0].stoppedReason' \
  --region us-east-1

# Verify IAM roles
aws iam get-role --role-name ecsTaskExecutionRole

# Test image pull
docker pull 123456789.dkr.ecr.us-east-1.amazonaws.com/cargo-tracker:latest
```

#### 2. Network Connectivity Issues

**Symptoms:**
- Cannot access application via load balancer
- Tasks cannot pull images
- Database connection failures

**Solutions:**
```bash
# Verify security group rules
aws ec2 describe-security-groups \
  --group-ids sg-xxxxx \
  --region us-east-1

# Check subnet route tables
aws ec2 describe-route-tables \
  --filters "Name=association.subnet-id,Values=subnet-xxxxx" \
  --region us-east-1

# Verify NAT Gateway (for private subnets)
aws ec2 describe-nat-gateways --region us-east-1

# Test connectivity from task
aws ecs execute-command \
  --cluster cargo-tracker-cluster \
  --task <task-id> \
  --container cargo-tracker \
  --interactive \
  --command "/bin/sh"
```

#### 3. Application Errors

**Symptoms:**
- Application starts but returns errors
- Health checks failing
- Database connection errors

**Solutions:**
```bash
# Check application logs
aws logs tail /ecs/cargo-tracker --follow --region us-east-1

# Verify environment variables
aws ecs describe-task-definition \
  --task-definition cargo-tracker-task \
  --query 'taskDefinition.containerDefinitions[0].environment' \
  --region us-east-1

# Check database connectivity
# Ensure database security group allows connections from ECS tasks
```

#### 4. Memory or CPU Issues

**Symptoms:**
- Tasks being killed (OOMKilled)
- High CPU utilization
- Slow application performance

**Solutions:**
```bash
# Check resource utilization
aws cloudwatch get-metric-statistics \
  --namespace AWS/ECS \
  --metric-name MemoryUtilization \
  --dimensions Name=ServiceName,Value=cargo-tracker-service \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 \
  --statistics Average Maximum \
  --region us-east-1

# Increase task resources
# Edit task definition: increase cpu and memory
# Register new revision and update service
```

#### 5. Load Balancer Issues

**Symptoms:**
- 502/503 errors from ALB
- Unhealthy targets
- Connection timeouts

**Solutions:**
```bash
# Check target health
aws elbv2 describe-target-health \
  --target-group-arn <target-group-arn> \
  --region us-east-1

# Verify health check configuration
aws elbv2 describe-target-groups \
  --target-group-arns <target-group-arn> \
  --region us-east-1

# Check ALB logs (if enabled)
aws s3 ls s3://alb-logs-bucket/

# Verify security group allows ALB to reach tasks
# ALB security group → ECS task security group on port 8080
```

### Debugging Commands

```bash
# List all tasks in cluster
aws ecs list-tasks \
  --cluster cargo-tracker-cluster \
  --region us-east-1

# Describe specific task
aws ecs describe-tasks \
  --cluster cargo-tracker-cluster \
  --tasks <task-id> \
  --region us-east-1

# View service events
aws ecs describe-services \
  --cluster cargo-tracker-cluster \
  --services cargo-tracker-service \
  --query 'services[0].events' \
  --region us-east-1

# Check task definition
aws ecs describe-task-definition \
  --task-definition cargo-tracker-task \
  --region us-east-1

# Execute command in running task (requires ECS Exec enabled)
aws ecs execute-command \
  --cluster cargo-tracker-cluster \
  --task <task-id> \
  --container cargo-tracker \
  --interactive \
  --command "/bin/bash"
```

---

## Scaling and Management

### Manual Scaling

**Update desired count:**
```bash
aws ecs update-service \
  --cluster cargo-tracker-cluster \
  --service cargo-tracker-service \
  --desired-count 4 \
  --region us-east-1
```

### Auto Scaling

**1. Create Auto Scaling Target:**
```bash
aws application-autoscaling register-scalable-target \
  --service-namespace ecs \
  --resource-id service/cargo-tracker-cluster/cargo-tracker-service \
  --scalable-dimension ecs:service:DesiredCount \
  --min-capacity 2 \
  --max-capacity 10 \
  --region us-east-1
```

**2. Create Scaling Policy (Target Tracking):**
```bash
aws application-autoscaling put-scaling-policy \
  --service-namespace ecs \
  --resource-id service/cargo-tracker-cluster/cargo-tracker-service \
  --scalable-dimension ecs:service:DesiredCount \
  --policy-name cpu-target-tracking \
  --policy-type TargetTrackingScaling \
  --target-tracking-scaling-policy-configuration file://scaling-policy.json \
  --region us-east-1
```

**scaling-policy.json:**
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

**Using AWS CodeDeploy:**

1. Create CodeDeploy application and deployment group
2. Configure task definition with multiple target groups
3. Deploy new version using CodeDeploy
4. Automatic traffic shifting and rollback

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
  --service-role-arn arn:aws:iam::123456789:role/CodeDeployServiceRole \
  --ecs-services clusterName=cargo-tracker-cluster,serviceName=cargo-tracker-service \
  --load-balancer-info targetGroupPairInfoList=[...] \
  --blue-green-deployment-configuration ... \
  --region us-east-1
```

### Rolling Updates

**Update service with new task definition:**
```bash
aws ecs update-service \
  --cluster cargo-tracker-cluster \
  --service cargo-tracker-service \
  --task-definition cargo-tracker-task:3 \
  --force-new-deployment \
  --region us-east-1
```

**Deployment configuration controls:**
- `maximumPercent`: 200 (allows 2x tasks during deployment)
- `minimumHealthyPercent`: 50 (keeps at least 50% healthy)

---

## Security Considerations

### 1. Network Security

**VPC Configuration:**
- Use private subnets for tasks (with NAT Gateway)
- Restrict security group rules to minimum required
- Use VPC endpoints for AWS services (ECR, CloudWatch, etc.)

**Security Group Best Practices:**
```bash
# Restrict inbound to ALB only
aws ec2 authorize-security-group-ingress \
  --group-id sg-task \
  --protocol tcp \
  --port 8080 \
  --source-group sg-alb
```

### 2. IAM Security

**Principle of Least Privilege:**
- Task execution role: Only ECR pull and CloudWatch write
- Task role: Only required AWS service permissions
- Avoid using root credentials

**Example Task Role Policy:**
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:PutObject"
      ],
      "Resource": "arn:aws:s3:::cargo-tracker-bucket/*"
    }
  ]
}
```

### 3. Secrets Management

**Use AWS Secrets Manager or Parameter Store:**
```bash
# Store secret
aws secretsmanager create-secret \
  --name cargo-tracker/db-password \
  --secret-string "your-password" \
  --region us-east-1

# Reference in task definition
{
  "secrets": [
    {
      "name": "DB_PASSWORD",
      "valueFrom": "arn:aws:secretsmanager:us-east-1:123456789:secret:cargo-tracker/db-password"
    }
  ]
}
```

### 4. Container Security

**Image Scanning:**
```bash
# Enable ECR image scanning
aws ecr put-image-scanning-configuration \
  --repository-name cargo-tracker \
  --image-scanning-configuration scanOnPush=true \
  --region us-east-1

# View scan results
aws ecr describe-image-scan-findings \
  --repository-name cargo-tracker \
  --image-id imageTag=latest \
  --region us-east-1
```

**Run as Non-Root User:**
- Dockerfile already creates and uses non-root user `payara`
- Reduces attack surface

### 5. Encryption

**Encryption at Rest:**
- Enable EFS encryption for persistent volumes
- Use encrypted EBS volumes for EC2 instances (if using EC2 launch type)

**Encryption in Transit:**
- Use HTTPS/TLS for ALB listeners
- Enable TLS for database connections

```bash
# Create HTTPS listener
aws elbv2 create-listener \
  --load-balancer-arn <alb-arn> \
  --protocol HTTPS \
  --port 443 \
  --certificates CertificateArn=<acm-cert-arn> \
  --default-actions Type=forward,TargetGroupArn=<tg-arn>
```

### 6. Compliance and Auditing

**Enable CloudTrail:**
```bash
aws cloudtrail create-trail \
  --name cargo-tracker-trail \
  --s3-bucket-name cloudtrail-logs-bucket \
  --region us-east-1

aws cloudtrail start-logging \
  --name cargo-tracker-trail \
  --region us-east-1
```

**Enable VPC Flow Logs:**
```bash
aws ec2 create-flow-logs \
  --resource-type VPC \
  --resource-ids vpc-xxxxx \
  --traffic-type ALL \
  --log-destination-type cloud-watch-logs \
  --log-group-name /aws/vpc/flowlogs \
  --deliver-logs-permission-arn <iam-role-arn> \
  --region us-east-1
```

---

## Technology-Specific Notes

### Jakarta EE 10 Considerations

**1. Application Server:**
- Uses Payara Micro 6.2025.3
- Embedded application server (no separate installation needed)
- Supports Jakarta EE 10 specifications

**2. JVM Configuration:**
```bash
# Recommended JVM options for containerized environment
JAVA_OPTS="-Xmx512m -Xms256m -XX:+UseContainerSupport -XX:MaxRAMPercentage=75.0 -XX:+UnlockExperimentalVMOptions"
```

**JVM Options Explained:**
- `-Xmx512m`: Maximum heap size 512MB
- `-Xms256m`: Initial heap size 256MB
- `-XX:+UseContainerSupport`: Enable container awareness
- `-XX:MaxRAMPercentage=75.0`: Use 75% of container memory for heap
- `-XX:+UnlockExperimentalVMOptions`: Enable experimental JVM features

**3. Database Configuration:**

**H2 Embedded (Default):**
- Suitable for development and testing
- Data stored in container filesystem (ephemeral)
- For persistence, mount EFS volume

**PostgreSQL (Production):**
- Use Amazon RDS for PostgreSQL
- Configure connection in environment variables
- Enable SSL/TLS for connections

**Example RDS Configuration:**
```bash
# Environment variables for PostgreSQL
DB_DRIVER_CLASS=org.postgresql.ds.PGPoolingDataSource
DB_JDBC_URL=jdbc:postgresql://cargo-tracker-db.xxxxx.us-east-1.rds.amazonaws.com:5432/cargotracker
DB_USER=cargotracker
DB_PASSWORD=<stored-in-secrets-manager>
```

**4. JMS Configuration:**
- Application uses JMS queues for event processing
- Payara Micro includes embedded JMS broker
- For production, consider Amazon MQ or Amazon SQS

**5. Health Checks:**
- Payara Micro provides `/health` endpoint
- MicroProfile Health specification support
- Configure ALB health checks to use application endpoint

**6. Monitoring:**
- Enable MicroProfile Metrics for application metrics
- Integrate with CloudWatch for centralized monitoring
- Use Payara Micro admin console for runtime management

**7. Performance Tuning:**

**Connection Pooling:**
```xml
<!-- In web.xml -->
<data-source>
  <name>java:app/jdbc/CargoTrackerDatabase</name>
  <max-pool-size>32</max-pool-size>
  <min-pool-size>2</min-pool-size>
</data-source>
```

**JPA Optimization:**
```xml
<!-- In persistence.xml -->
<property name="eclipselink.logging.level" value="WARNING"/>
<property name="eclipselink.cache.shared.default" value="true"/>
```

**8. Logging:**
- Application uses Java Util Logging (JUL)
- Logs sent to CloudWatch via awslogs driver
- Configure log levels via environment variables or logging.properties

**9. Deployment Profiles:**

**Development Profile:**
- H2 embedded database
- Verbose logging
- Schema auto-generation

**Production Profile:**
- PostgreSQL database
- Warning-level logging
- Manual schema management

**10. Troubleshooting Jakarta EE Issues:**

**Common Issues:**
- CDI bean discovery issues
- JPA entity mapping errors
- Transaction management problems
- Resource injection failures

**Debugging:**
```bash
# Enable verbose logging
JAVA_OPTS="$JAVA_OPTS -Djava.util.logging.config.file=/opt/app/logging.properties"

# Check Payara Micro logs
aws logs tail /ecs/cargo-tracker --follow --region us-east-1 | grep "Payara"

# Verify WAR deployment
# Check for deployment errors in logs
```

---

## Additional Resources

### AWS Documentation
- [ECS Fargate Documentation](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/AWS_Fargate.html)
- [ECS Task Definitions](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/task_definitions.html)
- [ECS Service Auto Scaling](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/service-auto-scaling.html)

### Jakarta EE Resources
- [Jakarta EE 10 Specification](https://jakarta.ee/specifications/platform/10/)
- [Payara Micro Documentation](https://docs.payara.fish/community/docs/documentation/payara-micro/payara-micro.html)
- [Eclipse Cargo Tracker](https://github.com/eclipse-ee4j/cargotracker)

### Docker Resources
- [Docker Best Practices](https://docs.docker.com/develop/dev-best-practices/)
- [Multi-stage Builds](https://docs.docker.com/build/building/multi-stage/)

---

## Support and Maintenance

### Regular Maintenance Tasks

**1. Update Docker Images:**
```bash
# Pull latest base images
docker pull maven:3.9.4-eclipse-temurin-11
docker pull eclipse-temurin:11-jdk

# Rebuild application image
docker build -t cargo-tracker:latest .
```

**2. Update Task Definitions:**
- Review and update resource allocations
- Update environment variables
- Rotate secrets and credentials

**3. Monitor Costs:**
```bash
# View ECS costs
aws ce get-cost-and-usage \
  --time-period Start=2024-01-01,End=2024-01-31 \
  --granularity MONTHLY \
  --metrics BlendedCost \
  --filter file://filter.json
```

**4. Security Updates:**
- Regularly scan images for vulnerabilities
- Update dependencies in pom.xml
- Apply security patches to base images

### Backup and Disaster Recovery

**1. Database Backups:**
```bash
# RDS automated backups
aws rds modify-db-instance \
  --db-instance-identifier cargo-tracker-db \
  --backup-retention-period 7 \
  --preferred-backup-window "03:00-04:00"
```

**2. Configuration Backups:**
- Version control all configuration files
- Store task definitions in Git
- Document infrastructure as code

**3. Disaster Recovery Plan:**
- Multi-region deployment strategy
- Regular backup testing
- Documented recovery procedures

---

## Conclusion

This guide provides comprehensive instructions for deploying the Eclipse Cargo Tracker application to AWS ECS Fargate. Follow the steps carefully, and refer to the troubleshooting section for common issues.

For additional support:
- Review AWS ECS documentation
- Check application logs in CloudWatch
- Consult Jakarta EE and Payara documentation
- Open issues in the project repository

**Happy Deploying! 🚀**
