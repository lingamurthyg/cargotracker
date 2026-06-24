# Cargo Tracker - AWS EKS Deployment Guide

## Table of Contents
1. [Overview](#overview)
2. [Prerequisites](#prerequisites)
3. [Local Development Setup](#local-development-setup)
4. [Building and Pushing Docker Images](#building-and-pushing-docker-images)
5. [AWS EKS Prerequisites](#aws-eks-prerequisites)
6. [EKS Cluster Setup](#eks-cluster-setup)
7. [Deploying to AWS EKS](#deploying-to-aws-eks)
8. [Accessing the Application](#accessing-the-application)
9. [Monitoring and Troubleshooting](#monitoring-and-troubleshooting)
10. [Scaling and Management](#scaling-and-management)
11. [Configuration Management](#configuration-management)
12. [Security Considerations](#security-considerations)
13. [Technology-Specific Notes](#technology-specific-notes)

---

## Overview

Eclipse Cargo Tracker is a Jakarta EE 10 application that demonstrates Domain-Driven Design (DDD) principles. This guide covers containerization and deployment to AWS EKS (Elastic Kubernetes Service).

**Technology Stack:**
- **Framework**: Jakarta EE 10
- **Application Server**: Payara Micro 6.2025.3
- **Java Version**: 11
- **Build Tool**: Maven
- **Package Type**: WAR (Web Application Archive)
- **Database**: H2 (embedded) or PostgreSQL (production)
- **Container Runtime**: Docker
- **Orchestration**: Kubernetes (AWS EKS)

---

## Prerequisites

### Required Software
- **Docker**: Version 20.10 or higher
- **Docker Compose**: Version 2.0 or higher
- **AWS CLI**: Version 2.x
- **kubectl**: Version 1.28 or higher
- **eksctl**: Version 0.150 or higher (optional, for cluster creation)
- **Java**: JDK 11 (for local development)
- **Maven**: Version 3.9.x (for local builds)

### AWS Account Requirements
- Active AWS account with appropriate permissions
- IAM user with EKS, ECR, EC2, and VPC permissions
- AWS credentials configured (`aws configure`)

### System Requirements
- **Memory**: Minimum 8GB RAM (16GB recommended)
- **Disk Space**: Minimum 20GB free space
- **OS**: Linux, macOS, or Windows 10/11 with WSL2

---

## Local Development Setup

### 1. Clone the Repository
```bash
git clone <repository-url>
cd cargotrackerra
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

# Access the application at: http://localhost:8080/cargo-tracker/
```

### 4. Stop the Application
```bash
docker-compose down
```

---

## Building and Pushing Docker Images

### Option 1: Using the Build Script (Linux/macOS)

```bash
# Make the script executable
chmod +x scripts/build-push.sh

# Run the script
./scripts/build-push.sh
```

**Script Workflow:**
1. Prompts for image tag (default: `latest`)
2. Asks to select registry (AWS ECR or Docker Hub)
3. Collects registry credentials
4. Builds the Docker image
5. Pushes to the selected registry

### Option 2: Using the Build Script (Windows)

```cmd
# Run the batch script
scripts\build-push.bat
```

### Option 3: Manual Build and Push

#### For AWS ECR:
```bash
# Set variables
AWS_REGION=us-east-1
AWS_ACCOUNT_ID=123456789012
ECR_REPO=cargo-tracker
IMAGE_TAG=latest

# Authenticate with ECR
aws ecr get-login-password --region $AWS_REGION | \
  docker login --username AWS --password-stdin \
  $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com

# Create ECR repository (if not exists)
aws ecr create-repository --repository-name $ECR_REPO --region $AWS_REGION

# Build image
docker build -t $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/$ECR_REPO:$IMAGE_TAG .

# Push image
docker push $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/$ECR_REPO:$IMAGE_TAG
```

#### For Docker Hub:
```bash
# Set variables
DOCKER_USERNAME=your-username
IMAGE_TAG=latest

# Login to Docker Hub
docker login -u $DOCKER_USERNAME

# Build image
docker build -t $DOCKER_USERNAME/cargo-tracker:$IMAGE_TAG .

# Push image
docker push $DOCKER_USERNAME/cargo-tracker:$IMAGE_TAG
```

---

## AWS EKS Prerequisites

### 1. Install AWS CLI
```bash
# Linux/macOS
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install

# Verify installation
aws --version
```

### 2. Configure AWS Credentials
```bash
aws configure
# Enter: AWS Access Key ID, Secret Access Key, Region, Output format
```

### 3. Install kubectl
```bash
# Linux
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
chmod +x kubectl
sudo mv kubectl /usr/local/bin/

# macOS
brew install kubectl

# Windows (using Chocolatey)
choco install kubernetes-cli

# Verify installation
kubectl version --client
```

### 4. Install eksctl (Optional)
```bash
# Linux/macOS
curl --silent --location "https://github.com/weaveworks/eksctl/releases/latest/download/eksctl_$(uname -s)_amd64.tar.gz" | tar xz -C /tmp
sudo mv /tmp/eksctl /usr/local/bin

# Verify installation
eksctl version
```

### 5. Verify IAM Permissions
Ensure your IAM user/role has the following permissions:
- `AmazonEKSClusterPolicy`
- `AmazonEKSServicePolicy`
- `AmazonEC2ContainerRegistryFullAccess`
- `AmazonEKSWorkerNodePolicy`
- `AmazonEKS_CNI_Policy`
- `AmazonEC2ContainerRegistryReadOnly`

---

## EKS Cluster Setup

### Option 1: Create Cluster with eksctl (Recommended)

```bash
# Create EKS cluster
eksctl create cluster \
  --name cargo-tracker-cluster \
  --region us-east-1 \
  --nodegroup-name standard-workers \
  --node-type t3.medium \
  --nodes 2 \
  --nodes-min 1 \
  --nodes-max 4 \
  --managed

# This process takes 15-20 minutes
```

### Option 2: Create Cluster via AWS Console

1. Navigate to **EKS** in AWS Console
2. Click **Create cluster**
3. Configure cluster settings:
   - **Name**: cargo-tracker-cluster
   - **Kubernetes version**: 1.28 or higher
   - **Cluster service role**: Create or select existing
4. Configure networking (VPC, subnets, security groups)
5. Create the cluster
6. Add node group:
   - **Name**: standard-workers
   - **Instance type**: t3.medium
   - **Desired size**: 2 nodes

### Configure kubectl for EKS

```bash
# Update kubeconfig
aws eks update-kubeconfig --region us-east-1 --name cargo-tracker-cluster

# Verify connection
kubectl cluster-info
kubectl get nodes
```

### Install AWS Load Balancer Controller

The AWS Load Balancer Controller is required for Ingress resources:

```bash
# Create IAM policy
curl -o iam_policy.json https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v2.6.0/docs/install/iam_policy.json

aws iam create-policy \
  --policy-name AWSLoadBalancerControllerIAMPolicy \
  --policy-document file://iam_policy.json

# Create IAM service account
eksctl create iamserviceaccount \
  --cluster=cargo-tracker-cluster \
  --namespace=kube-system \
  --name=aws-load-balancer-controller \
  --attach-policy-arn=arn:aws:iam::<AWS_ACCOUNT_ID>:policy/AWSLoadBalancerControllerIAMPolicy \
  --approve

# Install the controller using Helm
helm repo add eks https://aws.github.io/eks-charts
helm repo update

helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName=cargo-tracker-cluster \
  --set serviceAccount.create=false \
  --set serviceAccount.name=aws-load-balancer-controller
```

---

## Deploying to AWS EKS

### Option 1: Using the Deployment Script (Linux/macOS)

```bash
# Make the script executable
chmod +x scripts/deploy-image.sh

# Run the script
./scripts/deploy-image.sh
```

**Script Workflow:**
1. Prompts for AWS region and EKS cluster name
2. Prompts for Docker image URI
3. Prompts for database configuration (optional)
4. Configures kubectl for EKS
5. Updates Kubernetes manifests with provided values
6. Applies manifests to the cluster
7. Waits for deployment to complete
8. Displays application access information

### Option 2: Using the Deployment Script (Windows)

```cmd
# Run the batch script
scripts\deploy-image.bat
```

### Option 3: Manual Deployment

#### Step 1: Configure kubectl
```bash
aws eks update-kubeconfig --region us-east-1 --name cargo-tracker-cluster
```

#### Step 2: Update Kubernetes Manifests

Edit `kubernetes/deployment.yaml` and replace placeholders:
- `{{IMAGE_URI}}`: Your Docker image URI
- `{{DB_DRIVER_CLASS}}`: Database driver class
- `{{DB_JDBC_URL}}`: Database JDBC URL
- `{{DB_USER}}`: Database username
- `{{DB_PASSWORD}}`: Database password

#### Step 3: Apply Manifests
```bash
# Create namespace
kubectl apply -f kubernetes/namespace.yaml

# Deploy application
kubectl apply -f kubernetes/deployment.yaml

# Create service
kubectl apply -f kubernetes/service.yaml

# Create ingress
kubectl apply -f kubernetes/ingress.yaml
```

#### Step 4: Verify Deployment
```bash
# Check deployment status
kubectl rollout status deployment/cargo-tracker -n cargo-tracker

# View resources
kubectl get all -n cargo-tracker

# View ingress
kubectl get ingress -n cargo-tracker
```

---

## Accessing the Application

### Get Ingress URL

```bash
# Get the Load Balancer hostname
kubectl get ingress cargo-tracker-ingress -n cargo-tracker -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
```

### Access the Application

Once the Load Balancer is provisioned (may take 5-10 minutes):

```
http://<LOAD_BALANCER_HOSTNAME>/cargo-tracker/
```

### Update DNS (Optional)

For production, create a CNAME record in Route 53:
- **Name**: cargo-tracker.yourdomain.com
- **Type**: CNAME
- **Value**: <LOAD_BALANCER_HOSTNAME>

Update `kubernetes/ingress.yaml` with your domain:
```yaml
spec:
  rules:
  - host: cargo-tracker.yourdomain.com
```

---

## Monitoring and Troubleshooting

### View Logs

```bash
# View deployment logs
kubectl logs -f deployment/cargo-tracker -n cargo-tracker

# View logs for a specific pod
kubectl logs <pod-name> -n cargo-tracker

# View previous logs (if pod crashed)
kubectl logs <pod-name> -n cargo-tracker --previous
```

### Check Pod Status

```bash
# List all pods
kubectl get pods -n cargo-tracker

# Describe a pod (detailed information)
kubectl describe pod <pod-name> -n cargo-tracker

# Get pod events
kubectl get events -n cargo-tracker --sort-by='.lastTimestamp'
```

### Common Issues and Solutions

#### Issue 1: Pods in CrashLoopBackOff
**Symptoms**: Pods continuously restart
**Solutions**:
- Check logs: `kubectl logs <pod-name> -n cargo-tracker`
- Verify image URI is correct
- Check resource limits (increase if needed)
- Verify database connectivity

#### Issue 2: ImagePullBackOff
**Symptoms**: Cannot pull Docker image
**Solutions**:
- Verify image URI is correct
- Check ECR permissions
- Ensure ECR repository exists
- Verify image tag exists

#### Issue 3: Service Not Accessible
**Symptoms**: Cannot access application via Load Balancer
**Solutions**:
- Check ingress status: `kubectl describe ingress -n cargo-tracker`
- Verify AWS Load Balancer Controller is running
- Check security groups allow traffic on port 80/443
- Verify target group health in AWS Console

#### Issue 4: Database Connection Errors
**Symptoms**: Application fails to connect to database
**Solutions**:
- Verify database credentials in deployment.yaml
- Check database URL format
- Ensure database is accessible from EKS cluster
- For RDS, verify security groups allow traffic from EKS nodes

### Health Checks

```bash
# Check liveness probe
kubectl exec -it <pod-name> -n cargo-tracker -- curl http://localhost:8080/cargo-tracker/

# Check readiness probe
kubectl get pods -n cargo-tracker -o wide
```

---

## Scaling and Management

### Manual Scaling

```bash
# Scale deployment to 3 replicas
kubectl scale deployment/cargo-tracker --replicas=3 -n cargo-tracker

# Verify scaling
kubectl get pods -n cargo-tracker
```

### Horizontal Pod Autoscaler (HPA)

```bash
# Create HPA (requires metrics-server)
kubectl autoscale deployment cargo-tracker \
  --cpu-percent=70 \
  --min=2 \
  --max=10 \
  -n cargo-tracker

# View HPA status
kubectl get hpa -n cargo-tracker
```

### Rolling Updates

```bash
# Update image
kubectl set image deployment/cargo-tracker \
  cargo-tracker=<NEW_IMAGE_URI> \
  -n cargo-tracker

# Monitor rollout
kubectl rollout status deployment/cargo-tracker -n cargo-tracker

# View rollout history
kubectl rollout history deployment/cargo-tracker -n cargo-tracker
```

### Rollback

```bash
# Rollback to previous version
kubectl rollout undo deployment/cargo-tracker -n cargo-tracker

# Rollback to specific revision
kubectl rollout undo deployment/cargo-tracker --to-revision=2 -n cargo-tracker
```

### Resource Management

```bash
# View resource usage
kubectl top pods -n cargo-tracker
kubectl top nodes

# Update resource limits
kubectl edit deployment cargo-tracker -n cargo-tracker
```

---

## Configuration Management

### Environment Variables

Update environment variables in `kubernetes/deployment.yaml`:

```yaml
env:
- name: DB_DRIVER_CLASS
  value: "org.postgresql.ds.PGPoolingDataSource"
- name: DB_JDBC_URL
  value: "jdbc:postgresql://db-host:5432/cargotracker"
- name: DB_USER
  value: "dbuser"
- name: DB_PASSWORD
  value: "dbpassword"
```

### Using ConfigMaps

Create a ConfigMap for non-sensitive configuration:

```bash
# Create ConfigMap
kubectl create configmap cargo-tracker-config \
  --from-literal=DB_DRIVER_CLASS=org.h2.jdbcx.JdbcDataSource \
  --from-literal=DB_JDBC_URL=jdbc:h2:file:/app/data/cargo-tracker-database \
  -n cargo-tracker

# Reference in deployment
env:
- name: DB_DRIVER_CLASS
  valueFrom:
    configMapKeyRef:
      name: cargo-tracker-config
      key: DB_DRIVER_CLASS
```

### Using Secrets

Create a Secret for sensitive data:

```bash
# Create Secret
kubectl create secret generic cargo-tracker-secrets \
  --from-literal=DB_USER=dbuser \
  --from-literal=DB_PASSWORD=dbpassword \
  -n cargo-tracker

# Reference in deployment
env:
- name: DB_USER
  valueFrom:
    secretKeyRef:
      name: cargo-tracker-secrets
      key: DB_USER
- name: DB_PASSWORD
  valueFrom:
    secretKeyRef:
      name: cargo-tracker-secrets
      key: DB_PASSWORD
```

---

## Security Considerations

### 1. Image Security
- Use official base images (Amazon Corretto)
- Regularly update base images for security patches
- Scan images for vulnerabilities using AWS ECR scanning
- Use specific image tags (avoid `latest` in production)

### 2. Network Security
- Use Network Policies to restrict pod-to-pod communication
- Configure security groups to allow only necessary traffic
- Use private subnets for EKS nodes
- Enable VPC Flow Logs for network monitoring

### 3. Access Control
- Use IAM roles for service accounts (IRSA)
- Implement RBAC for kubectl access
- Use AWS Secrets Manager or Parameter Store for sensitive data
- Enable audit logging in EKS

### 4. Application Security
- Run containers as non-root user (already configured)
- Set read-only root filesystem where possible
- Drop unnecessary Linux capabilities
- Use Pod Security Standards

### 5. Database Security
- Use RDS with encryption at rest
- Enable SSL/TLS for database connections
- Use IAM database authentication
- Regularly backup database

### Example Network Policy

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: cargo-tracker-netpol
  namespace: cargo-tracker
spec:
  podSelector:
    matchLabels:
      app: cargo-tracker
  policyTypes:
  - Ingress
  - Egress
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          name: ingress-nginx
    ports:
    - protocol: TCP
      port: 8080
  egress:
  - to:
    - namespaceSelector: {}
    ports:
    - protocol: TCP
      port: 5432  # PostgreSQL
```

---

## Technology-Specific Notes

### Jakarta EE / Payara Micro

**Application Server**: This application uses Payara Micro, a lightweight Jakarta EE runtime optimized for microservices and containerized deployments.

**Key Features**:
- Full Jakarta EE 10 support
- Embedded application server (no separate installation needed)
- Fast startup time
- Small footprint

**JVM Tuning**:
```yaml
env:
- name: JAVA_OPTS
  value: "-Xmx512m -Xms256m -XX:+UseContainerSupport -XX:MaxRAMPercentage=75.0 -XX:+UseG1GC"
```

**Recommended JVM Options**:
- `-Xmx512m -Xms256m`: Heap size (adjust based on workload)
- `-XX:+UseContainerSupport`: Enable container awareness
- `-XX:MaxRAMPercentage=75.0`: Use 75% of container memory
- `-XX:+UseG1GC`: Use G1 garbage collector (recommended for containers)

### Database Configuration

**H2 (Development)**:
```yaml
env:
- name: DB_DRIVER_CLASS
  value: "org.h2.jdbcx.JdbcDataSource"
- name: DB_JDBC_URL
  value: "jdbc:h2:file:/app/data/cargo-tracker-database"
```

**PostgreSQL (Production)**:
```yaml
env:
- name: DB_DRIVER_CLASS
  value: "org.postgresql.ds.PGPoolingDataSource"
- name: DB_JDBC_URL
  value: "jdbc:postgresql://cargo-tracker-db.xxxx.us-east-1.rds.amazonaws.com:5432/cargotracker"
- name: DB_USER
  valueFrom:
    secretKeyRef:
      name: cargo-tracker-secrets
      key: DB_USER
- name: DB_PASSWORD
  valueFrom:
    secretKeyRef:
      name: cargo-tracker-secrets
      key: DB_PASSWORD
```

### Health Checks

The application uses HTTP health checks on the root path:
- **Liveness Probe**: `/cargo-tracker/` (checks if application is running)
- **Readiness Probe**: `/cargo-tracker/` (checks if application is ready to serve traffic)

**Startup Time**: Jakarta EE applications typically take 60-90 seconds to start. The `initialDelaySeconds` is set accordingly.

### Persistent Storage

For H2 database persistence, mount a volume:

```yaml
volumeMounts:
- name: data
  mountPath: /app/data
volumes:
- name: data
  persistentVolumeClaim:
    claimName: cargo-tracker-data
```

Create PersistentVolumeClaim:
```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: cargo-tracker-data
  namespace: cargo-tracker
spec:
  accessModes:
  - ReadWriteOnce
  resources:
    requests:
      storage: 10Gi
  storageClassName: gp3
```

---

## Additional Resources

### Documentation
- [Jakarta EE Documentation](https://jakarta.ee/specifications/)
- [Payara Micro Documentation](https://docs.payara.fish/community/docs/documentation/payara-micro/payara-micro.html)
- [AWS EKS Documentation](https://docs.aws.amazon.com/eks/)
- [Kubernetes Documentation](https://kubernetes.io/docs/)

### Useful Commands Reference

```bash
# Cluster Management
kubectl cluster-info
kubectl get nodes
kubectl describe node <node-name>

# Namespace Management
kubectl get namespaces
kubectl describe namespace cargo-tracker

# Deployment Management
kubectl get deployments -n cargo-tracker
kubectl describe deployment cargo-tracker -n cargo-tracker
kubectl edit deployment cargo-tracker -n cargo-tracker

# Pod Management
kubectl get pods -n cargo-tracker
kubectl describe pod <pod-name> -n cargo-tracker
kubectl logs <pod-name> -n cargo-tracker
kubectl exec -it <pod-name> -n cargo-tracker -- /bin/bash

# Service Management
kubectl get services -n cargo-tracker
kubectl describe service cargo-tracker-service -n cargo-tracker

# Ingress Management
kubectl get ingress -n cargo-tracker
kubectl describe ingress cargo-tracker-ingress -n cargo-tracker

# Resource Monitoring
kubectl top pods -n cargo-tracker
kubectl top nodes

# Troubleshooting
kubectl get events -n cargo-tracker --sort-by='.lastTimestamp'
kubectl logs -f deployment/cargo-tracker -n cargo-tracker
kubectl port-forward service/cargo-tracker-service 8080:80 -n cargo-tracker
```

---

## Support and Troubleshooting

For issues or questions:
1. Check application logs: `kubectl logs -f deployment/cargo-tracker -n cargo-tracker`
2. Review Kubernetes events: `kubectl get events -n cargo-tracker`
3. Verify AWS resources in AWS Console (EKS, ECR, Load Balancers)
4. Consult Jakarta EE and Payara documentation
5. Review AWS EKS troubleshooting guide

---

## License

This deployment guide is provided as-is for the Eclipse Cargo Tracker application.
Refer to the main project LICENSE for application licensing information.
