# Cargo Tracker - Deployment Guide

## Table of Contents
1. [Overview](#overview)
2. [Prerequisites](#prerequisites)
3. [Local Development Setup](#local-development-setup)
4. [Docker Deployment](#docker-deployment)
5. [AWS ECS Fargate Deployment](#aws-ecs-fargate-deployment)
6. [Configuration Management](#configuration-management)
7. [Troubleshooting](#troubleshooting)
8. [Security Considerations](#security-considerations)
9. [Monitoring and Logging](#monitoring-and-logging)

---

## Overview

Eclipse Cargo Tracker is a Jakarta EE 10 application demonstrating Domain-Driven Design (DDD) principles. This guide covers containerization and deployment to AWS ECS Fargate.

**Technology Stack:**
- Java 11
- Jakarta EE 10
- Payara Micro (Application Server)
- Maven (Build Tool)
- H2 Database (Embedded)
- Docker & AWS ECS Fargate

---

## Prerequisites

### Required Software
- **Java Development Kit (JDK) 11+**
- **Maven 3.6+**
- **Docker 20.10+**
- **AWS CLI 2.x** (for ECS deployment)
- **Git** (for version control)

### AWS Requirements (for ECS Fargate)
- AWS Account with appropriate permissions
- AWS CLI configured with credentials
- VPC with at least 2 subnets in different availability zones
- Security group allowing inbound traffic on port 8080
- IAM roles:
  - `ecsTaskExecutionRole` - For ECS to pull images and write logs
  - `ecsTaskRole` - For application permissions (optional)

### Verify Prerequisites

```bash
# Check Java version
java -version

# Check Maven version
mvn -version

# Check Docker version
docker --version

# Check AWS CLI version
aws --version

# Verify AWS credentials
aws sts get-caller-identity
```

---

## Local Development Setup

### 1. Clone the Repository

```bash
git clone <repository-url>
cd CargoTrackerComp
```

### 2. Build the Application

```bash
# Build with Maven
mvn clean package

# The WAR file will be created at: target/cargo-tracker.war
```

### 3. Run Locally with Maven

```bash
# Run with Payara profile (default)
mvn cargo:run

# Access the application at: http://localhost:8080/cargo-tracker
```

### 4. Run with Docker Compose

```bash
# Build and start the application
docker-compose up --build

# Access the application at: http://localhost:8080/cargo-tracker

# Stop the application
docker-compose down
```

---

## Docker Deployment

### Build Docker Image

```bash
# Build the Docker image
docker build -t cargo-tracker:latest .

# Verify the image
docker images | grep cargo-tracker
```

### Run Docker Container

```bash
# Run the container
docker run -d \
  --name cargo-tracker \
  -p 8080:8080 \
  -e JAVA_OPTS="-Xmx512m -Xms256m" \
  -v $(pwd)/cargo-tracker-data:/opt/payara/cargo-tracker-data \
  cargo-tracker:latest

# Check container logs
docker logs -f cargo-tracker

# Stop the container
docker stop cargo-tracker
docker rm cargo-tracker
```

### Push to Container Registry

#### Option 1: AWS ECR

```bash
# Run the build-push script
./scripts/build-push.sh

# Follow the prompts:
# 1. Select AWS ECR
# 2. Enter AWS Region
# 3. Enter AWS Account ID
# 4. Enter ECR Repository Name
# 5. Enter Image Tag
```

#### Option 2: Docker Hub

```bash
# Run the build-push script
./scripts/build-push.sh

# Follow the prompts:
# 1. Select Docker Hub
# 2. Enter Docker Hub Username
# 3. Enter Docker Hub Password/Token
# 4. Enter Repository Name
# 5. Enter Image Tag
```

---

## AWS ECS Fargate Deployment

### Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                     AWS ECS Fargate                         │
│                                                             │
│  ┌──────────────┐         ┌──────────────┐                │
│  │   Internet   │         │   Internet   │                │
│  │   Gateway    │         │   Gateway    │                │
│  └──────┬───────┘         └──────┬───────┘                │
│         │                        │                         │
│  ┌──────▼──────────────────────▼───────┐                  │
│  │  Application Load Balancer (ALB)    │                  │
│  └──────┬──────────────────────┬───────┘                  │
│         │                      │                           │
│  ┌──────▼──────┐        ┌──────▼──────┐                  │
│  │   Subnet 1  │        │   Subnet 2  │                  │
│  │             │        │             │                  │
│  │  ┌────────┐ │        │  ┌────────┐ │                  │
│  │  │  ECS   │ │        │  │  ECS   │ │                  │
│  │  │  Task  │ │        │  │  Task  │ │                  │
│  │  │ (8080) │ │        │  │ (8080) │ │                  │
│  │  └────────┘ │        │  └────────┘ │                  │
│  └─────────────┘        └─────────────┘                  │
│                                                             │
│  ┌─────────────────────────────────────┐                  │
│  │      CloudWatch Logs                │                  │
│  │   /ecs/cargo-tracker                │                  │
│  └─────────────────────────────────────┘                  │
└─────────────────────────────────────────────────────────────┘
```

### Step 1: Prepare AWS Environment

#### Create VPC and Subnets (if not exists)

```bash
# Create VPC
aws ec2 create-vpc \
  --cidr-block 10.0.0.0/16 \
  --region us-east-1

# Create Subnets
aws ec2 create-subnet \
  --vpc-id <vpc-id> \
  --cidr-block 10.0.1.0/24 \
  --availability-zone us-east-1a

aws ec2 create-subnet \
  --vpc-id <vpc-id> \
  --cidr-block 10.0.2.0/24 \
  --availability-zone us-east-1b
```

#### Create Security Group

```bash
# Create security group
aws ec2 create-security-group \
  --group-name cargo-tracker-sg \
  --description "Security group for Cargo Tracker" \
  --vpc-id <vpc-id> \
  --region us-east-1

# Allow inbound traffic on port 8080
aws ec2 authorize-security-group-ingress \
  --group-id <security-group-id> \
  --protocol tcp \
  --port 8080 \
  --cidr 0.0.0.0/0 \
  --region us-east-1

# Allow inbound traffic on port 80 (for ALB)
aws ec2 authorize-security-group-ingress \
  --group-id <security-group-id> \
  --protocol tcp \
  --port 80 \
  --cidr 0.0.0.0/0 \
  --region us-east-1
```

#### Create IAM Roles

**ECS Task Execution Role:**

```bash
# Create trust policy file
cat > ecs-task-execution-trust-policy.json <<EOF
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

# Create the role
aws iam create-role \
  --role-name ecsTaskExecutionRole \
  --assume-role-policy-document file://ecs-task-execution-trust-policy.json

# Attach the managed policy
aws iam attach-role-policy \
  --role-name ecsTaskExecutionRole \
  --policy-arn arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy
```

### Step 2: Build and Push Docker Image

```bash
# Run the build-push script
./scripts/build-push.sh

# Select AWS ECR and provide:
# - AWS Region: us-east-1
# - AWS Account ID: 123456789012
# - ECR Repository Name: cargo-tracker
# - Image Tag: latest
```

### Step 3: Deploy to ECS Fargate

```bash
# Run the deployment script
./scripts/deploy-image.sh

# Provide the following information:
# - AWS Region: us-east-1
# - ECS Cluster Name: cargo-tracker-cluster
# - VPC ID: vpc-xxxxx
# - Subnet IDs: subnet-xxxxx,subnet-yyyyy
# - Security Group ID: sg-xxxxx
# - Docker Image URI: 123456789012.dkr.ecr.us-east-1.amazonaws.com/cargo-tracker:latest
# - Load Balancer: y (yes)
```

### Step 4: Verify Deployment

```bash
# Check service status
aws ecs describe-services \
  --cluster cargo-tracker-cluster \
  --services cargo-tracker-service \
  --region us-east-1

# Check running tasks
aws ecs list-tasks \
  --cluster cargo-tracker-cluster \
  --service-name cargo-tracker-service \
  --region us-east-1

# View logs
aws logs tail /ecs/cargo-tracker --follow --region us-east-1
```

### Step 5: Access the Application

```bash
# Get the ALB DNS name
aws elbv2 describe-load-balancers \
  --names cargo-tracker-alb \
  --region us-east-1 \
  --query 'LoadBalancers[0].DNSName' \
  --output text

# Access the application at:
# http://<alb-dns-name>/cargo-tracker
```

---

## Configuration Management

### Environment Variables

The application supports the following environment variables:

| Variable | Description | Default |
|----------|-------------|---------|
| `JAVA_OPTS` | JVM options | `-Xmx512m -Xms256m -XX:+UseContainerSupport` |
| `TZ` | Timezone | `UTC` |

### JVM Memory Configuration

For ECS Fargate, adjust memory settings based on task memory:

| Task Memory | Recommended JAVA_OPTS |
|-------------|----------------------|
| 512 MB | `-Xmx256m -Xms128m` |
| 1024 MB | `-Xmx512m -Xms256m` |
| 2048 MB | `-Xmx1024m -Xms512m` |

### Database Configuration

The default configuration uses H2 embedded database. For production, consider:

1. **Amazon RDS PostgreSQL**
2. **Amazon Aurora PostgreSQL**

Update the `web.xml` data source configuration:

```xml
<data-source>
  <name>java:app/jdbc/CargoTrackerDatabase</name>
  <class-name>org.postgresql.ds.PGPoolingDataSource</class-name>
  <url>jdbc:postgresql://rds-endpoint:5432/cargotracker</url>
  <user>dbuser</user>
  <password>dbpassword</password>
</data-source>
```

---

## Troubleshooting

### Common Issues

#### 1. Task Fails to Start

**Symptoms:**
- Tasks stop immediately after starting
- "Essential container exited" error

**Solutions:**
```bash
# Check task logs
aws logs tail /ecs/cargo-tracker --follow --region us-east-1

# Check task definition
aws ecs describe-task-definition \
  --task-definition cargo-tracker-task \
  --region us-east-1

# Verify IAM roles
aws iam get-role --role-name ecsTaskExecutionRole
```

#### 2. Cannot Pull Image from ECR

**Symptoms:**
- "CannotPullContainerError"
- "Access denied" errors

**Solutions:**
```bash
# Verify ECR repository exists
aws ecr describe-repositories --region us-east-1

# Check IAM permissions
aws iam get-role-policy \
  --role-name ecsTaskExecutionRole \
  --policy-name AmazonECSTaskExecutionRolePolicy

# Manually test ECR login
aws ecr get-login-password --region us-east-1 | \
  docker login --username AWS --password-stdin \
  <account-id>.dkr.ecr.us-east-1.amazonaws.com
```

#### 3. Health Check Failures

**Symptoms:**
- Tasks are replaced frequently
- "Unhealthy" status in target group

**Solutions:**
```bash
# Check application logs
aws logs tail /ecs/cargo-tracker --follow --region us-east-1

# Verify security group allows traffic
aws ec2 describe-security-groups \
  --group-ids <security-group-id> \
  --region us-east-1

# Test health endpoint
curl http://<task-ip>:8080/cargo-tracker
```

#### 4. Out of Memory Errors

**Symptoms:**
- Tasks stop with exit code 137
- "OutOfMemoryError" in logs

**Solutions:**
```bash
# Increase task memory in task-definition.json
# Update JAVA_OPTS to use less heap

# For 1024 MB task memory:
"environment": [
  {
    "name": "JAVA_OPTS",
    "value": "-Xmx512m -Xms256m -XX:MaxRAMPercentage=75.0"
  }
]
```

#### 5. Invalid CPU/Memory Combination

**Symptoms:**
- "Invalid CPU or memory value specified"

**Valid Fargate Combinations:**
```
CPU: 256  → Memory: 512, 1024, 2048
CPU: 512  → Memory: 1024, 2048, 3072, 4096
CPU: 1024 → Memory: 2048-8192 (increments of 1024)
CPU: 2048 → Memory: 4096-16384 (increments of 1024)
CPU: 4096 → Memory: 8192-30720 (increments of 1024)
```

---

## Security Considerations

### 1. Container Security

- **Non-root user**: Application runs as `payara` user (UID 1001)
- **Read-only filesystem**: Consider using read-only root filesystem
- **Secrets management**: Use AWS Secrets Manager for sensitive data

### 2. Network Security

- **Security groups**: Restrict inbound traffic to necessary ports only
- **Private subnets**: Deploy tasks in private subnets with NAT gateway
- **VPC endpoints**: Use VPC endpoints for AWS services (ECR, CloudWatch)

### 3. IAM Security

- **Least privilege**: Grant minimum required permissions
- **Task role**: Use separate task role for application permissions
- **Execution role**: Use execution role only for ECS operations

### 4. Application Security

- **HTTPS**: Use ALB with SSL/TLS certificate
- **Authentication**: Implement authentication and authorization
- **Input validation**: Validate all user inputs

---

## Monitoring and Logging

### CloudWatch Logs

```bash
# View real-time logs
aws logs tail /ecs/cargo-tracker --follow --region us-east-1

# Search logs
aws logs filter-log-events \
  --log-group-name /ecs/cargo-tracker \
  --filter-pattern "ERROR" \
  --region us-east-1

# Export logs to S3
aws logs create-export-task \
  --log-group-name /ecs/cargo-tracker \
  --from 1609459200000 \
  --to 1609545600000 \
  --destination s3-bucket-name \
  --region us-east-1
```

### CloudWatch Metrics

Key metrics to monitor:

- **CPUUtilization**: Target < 70%
- **MemoryUtilization**: Target < 80%
- **TargetResponseTime**: Target < 1000ms
- **HealthyHostCount**: Should equal desired count
- **UnHealthyHostCount**: Should be 0

### CloudWatch Alarms

```bash
# Create CPU alarm
aws cloudwatch put-metric-alarm \
  --alarm-name cargo-tracker-high-cpu \
  --alarm-description "Alert when CPU exceeds 80%" \
  --metric-name CPUUtilization \
  --namespace AWS/ECS \
  --statistic Average \
  --period 300 \
  --threshold 80 \
  --comparison-operator GreaterThanThreshold \
  --evaluation-periods 2 \
  --dimensions Name=ServiceName,Value=cargo-tracker-service \
               Name=ClusterName,Value=cargo-tracker-cluster \
  --region us-east-1
```

### Application Performance Monitoring

Consider integrating:
- **AWS X-Ray**: Distributed tracing
- **Amazon CloudWatch Container Insights**: Container-level metrics
- **Third-party APM**: New Relic, Datadog, Dynatrace

---

## Scaling and High Availability

### Auto Scaling

```bash
# Register scalable target
aws application-autoscaling register-scalable-target \
  --service-namespace ecs \
  --resource-id service/cargo-tracker-cluster/cargo-tracker-service \
  --scalable-dimension ecs:service:DesiredCount \
  --min-capacity 2 \
  --max-capacity 10 \
  --region us-east-1

# Create scaling policy
aws application-autoscaling put-scaling-policy \
  --service-namespace ecs \
  --resource-id service/cargo-tracker-cluster/cargo-tracker-service \
  --scalable-dimension ecs:service:DesiredCount \
  --policy-name cargo-tracker-cpu-scaling \
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

### Blue/Green Deployment

```bash
# Create new task definition revision
aws ecs register-task-definition \
  --cli-input-json file://ecs/task-definition.json \
  --region us-east-1

# Update service with new task definition
aws ecs update-service \
  --cluster cargo-tracker-cluster \
  --service cargo-tracker-service \
  --task-definition cargo-tracker-task:2 \
  --deployment-configuration maximumPercent=200,minimumHealthyPercent=100 \
  --region us-east-1
```

---

## Maintenance and Updates

### Update Application

```bash
# 1. Build new image with new tag
./scripts/build-push.sh
# Enter new tag: v1.1.0

# 2. Update task definition with new image
# Edit ecs/task-definition.json and update image URI

# 3. Deploy updated version
./scripts/deploy-image.sh
```

### Rollback

```bash
# List task definition revisions
aws ecs list-task-definitions \
  --family-prefix cargo-tracker-task \
  --region us-east-1

# Rollback to previous revision
aws ecs update-service \
  --cluster cargo-tracker-cluster \
  --service cargo-tracker-service \
  --task-definition cargo-tracker-task:1 \
  --force-new-deployment \
  --region us-east-1
```

---

## Cost Optimization

### Fargate Pricing

- **vCPU**: $0.04048 per vCPU per hour
- **Memory**: $0.004445 per GB per hour

**Example (512 CPU, 1024 MB):**
- Monthly cost: ~$30 per task (running 24/7)

### Cost Reduction Tips

1. **Right-size resources**: Use minimum required CPU/memory
2. **Use Fargate Spot**: Save up to 70% for fault-tolerant workloads
3. **Scale down during off-hours**: Reduce desired count
4. **Use reserved capacity**: For predictable workloads
5. **Optimize image size**: Smaller images = faster pulls = lower costs

---

## Additional Resources

- [Jakarta EE Documentation](https://jakarta.ee/)
- [Payara Micro Documentation](https://docs.payara.fish/community/docs/documentation/payara-micro/payara-micro.html)
- [AWS ECS Fargate Documentation](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/AWS_Fargate.html)
- [Docker Best Practices](https://docs.docker.com/develop/dev-best-practices/)
- [AWS Well-Architected Framework](https://aws.amazon.com/architecture/well-architected/)

---

## Support and Contribution

For issues, questions, or contributions:
- GitHub Issues: [Project Issues](https://github.com/eclipse-ee4j/cargotracker/issues)
- Documentation: [Project Wiki](https://github.com/eclipse-ee4j/cargotracker/wiki)

---

**Last Updated**: 2025
**Version**: 1.0.0
