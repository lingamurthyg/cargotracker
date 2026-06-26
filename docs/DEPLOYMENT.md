# Cargo Tracker - AWS EKS Deployment Guide

## Table of Contents
1. [Overview](#overview)
2. [Prerequisites](#prerequisites)
3. [Local Development with Docker](#local-development-with-docker)
4. [Building and Pushing Docker Images](#building-and-pushing-docker-images)
5. [AWS EKS Deployment](#aws-eks-deployment)
6. [Configuration Management](#configuration-management)
7. [Monitoring and Troubleshooting](#monitoring-and-troubleshooting)
8. [Scaling and Management](#scaling-and-management)
9. [Security Considerations](#security-considerations)
10. [Technology-Specific Notes](#technology-specific-notes)

---

## Overview

This guide provides comprehensive instructions for containerizing and deploying the Eclipse Cargo Tracker application (Jakarta EE 10) to AWS EKS (Elastic Kubernetes Service).

**Application Details:**
- **Technology Stack**: Jakarta EE 10, Java 11
- **Build Tool**: Maven
- **Application Server**: Payara Micro
- **Packaging**: WAR file
- **Default Port**: 8080
- **Database**: H2 (embedded) or PostgreSQL (cloud)

---

## Prerequisites

### Required Software

#### For Local Development:
- **Docker**: Version 20.10 or higher
  - Installation: https://docs.docker.com/get-docker/
- **Docker Compose**: Version 2.0 or higher
  - Installation: https://docs.docker.com/compose/install/

#### For AWS EKS Deployment:
- **AWS CLI**: Version 2.x
  ```bash
  # Install AWS CLI
  curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
  unzip awscliv2.zip
  sudo ./aws/install
  
  # Verify installation
  aws --version
  ```

- **kubectl**: Kubernetes command-line tool
  ```bash
  # Install kubectl
  curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
  chmod +x kubectl
  sudo mv kubectl /usr/local/bin/
  
  # Verify installation
  kubectl version --client
  ```

- **eksctl** (optional but recommended): EKS cluster management tool
  ```bash
  # Install eksctl
  curl --silent --location "https://github.com/weksctl-io/eksctl/releases/latest/download/eksctl_$(uname -s)_amd64.tar.gz" | tar xz -C /tmp
  sudo mv /tmp/eksctl /usr/local/bin
  
  # Verify installation
  eksctl version
  ```

### AWS Account Requirements

1. **IAM Permissions**: Your AWS user/role needs permissions for:
   - EKS cluster management
   - ECR repository access
   - VPC and networking resources
   - IAM role creation (for EKS service roles)

2. **AWS Configuration**:
   ```bash
   # Configure AWS credentials
   aws configure
   # Enter: AWS Access Key ID, Secret Access Key, Region, Output format
   ```

3. **Container Registry**:
   - **Option 1**: AWS ECR (Elastic Container Registry)
   - **Option 2**: Docker Hub account

---

## Local Development with Docker

### Step 1: Build the Application Locally

```bash
# Navigate to project directory
cd /path/to/cargo-tracker

# Build with Maven (optional - Docker will build it)
mvn clean package -DskipTests
```

### Step 2: Build Docker Image

```bash
# Build the Docker image
docker build -t cargo-tracker:latest .

# Verify the image
docker images | grep cargo-tracker
```

### Step 3: Run with Docker Compose

```bash
# Start the application
docker-compose up -d

# View logs
docker-compose logs -f

# Access the application
# Open browser: http://localhost:8080/cargo-tracker/
```

### Step 4: Stop the Application

```bash
# Stop and remove containers
docker-compose down

# Stop and remove containers with volumes
docker-compose down -v
```

---

## Building and Pushing Docker Images

### Using the Build-Push Script (Recommended)

#### Linux/macOS:

```bash
# Make script executable
chmod +x scripts/build-push.sh

# Run the script
./scripts/build-push.sh
```

#### Windows:

```cmd
# Run the batch script
scripts\build-push.bat
```

### Script Workflow:

1. **Select Registry Type**:
   - Option 1: AWS ECR
   - Option 2: Docker Hub

2. **For AWS ECR**:
   - Enter AWS Region (e.g., us-east-1)
   - Enter AWS Account ID
   - Enter ECR Repository Name (default: cargo-tracker)
   - Script will authenticate and create repository if needed

3. **For Docker Hub**:
   - Enter Docker Hub username
   - Enter Docker Hub password/token

4. **Enter Image Tag**:
   - Default: latest
   - Custom: v1.0.0, dev, staging, etc.

5. **Build and Push**:
   - Script builds the Docker image
   - Pushes to selected registry
   - Displays final image URI

### Manual Build and Push

#### AWS ECR:

```bash
# Authenticate with ECR
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin <account-id>.dkr.ecr.us-east-1.amazonaws.com

# Create ECR repository (if not exists)
aws ecr create-repository --repository-name cargo-tracker --region us-east-1

# Build and tag image
docker build -t cargo-tracker:latest .
docker tag cargo-tracker:latest <account-id>.dkr.ecr.us-east-1.amazonaws.com/cargo-tracker:latest

# Push image
docker push <account-id>.dkr.ecr.us-east-1.amazonaws.com/cargo-tracker:latest
```

#### Docker Hub:

```bash
# Login to Docker Hub
docker login -u <username>

# Build and tag image
docker build -t cargo-tracker:latest .
docker tag cargo-tracker:latest <username>/cargo-tracker:latest

# Push image
docker push <username>/cargo-tracker:latest
```

---

## AWS EKS Deployment

### Step 1: Create EKS Cluster (if not exists)

#### Using eksctl (Recommended):

```bash
# Create EKS cluster with managed node group
eksctl create cluster \
  --name cargo-tracker-cluster \
  --region us-east-1 \
  --nodegroup-name cargo-tracker-nodes \
  --node-type t3.medium \
  --nodes 2 \
  --nodes-min 1 \
  --nodes-max 4 \
  --managed

# This takes 15-20 minutes
```

#### Using AWS Console:
1. Navigate to EKS service
2. Click "Create cluster"
3. Follow the wizard to configure cluster
4. Create node group after cluster is ready

### Step 2: Configure kubectl

```bash
# Update kubeconfig for EKS cluster
aws eks update-kubeconfig --region us-east-1 --name cargo-tracker-cluster

# Verify connection
kubectl cluster-info
kubectl get nodes
```

### Step 3: Install AWS Load Balancer Controller

The AWS Load Balancer Controller is required for Ingress resources:

```bash
# Create IAM OIDC provider
eksctl utils associate-iam-oidc-provider \
  --region us-east-1 \
  --cluster cargo-tracker-cluster \
  --approve

# Download IAM policy
curl -o iam_policy.json https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v2.4.7/docs/install/iam_policy.json

# Create IAM policy
aws iam create-policy \
  --policy-name AWSLoadBalancerControllerIAMPolicy \
  --policy-document file://iam_policy.json

# Create service account
eksctl create iamserviceaccount \
  --cluster=cargo-tracker-cluster \
  --namespace=kube-system \
  --name=aws-load-balancer-controller \
  --attach-policy-arn=arn:aws:iam::<account-id>:policy/AWSLoadBalancerControllerIAMPolicy \
  --override-existing-serviceaccounts \
  --approve

# Install AWS Load Balancer Controller using Helm
helm repo add eks https://aws.github.io/eks-charts
helm repo update
helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName=cargo-tracker-cluster \
  --set serviceAccount.create=false \
  --set serviceAccount.name=aws-load-balancer-controller
```

### Step 4: Deploy Application

#### Using the Deploy Script (Recommended):

**Linux/macOS:**
```bash
# Make script executable
chmod +x scripts/deploy-image.sh

# Run deployment script
./scripts/deploy-image.sh
```

**Windows:**
```cmd
# Run deployment script
scripts\deploy-image.bat
```

#### Script Prompts:
1. AWS Region (e.g., us-east-1)
2. EKS Cluster Name
3. Docker Image URI (full path with tag)
4. Optional: Database configuration (if using external database)

#### Manual Deployment:

```bash
# Update deployment.yaml with your image URI
sed -i 's|{{IMAGE_URI}}|<your-image-uri>|g' kubernetes/deployment.yaml

# Apply Kubernetes manifests
kubectl apply -f kubernetes/namespace.yaml
kubectl apply -f kubernetes/deployment.yaml
kubectl apply -f kubernetes/service.yaml
kubectl apply -f kubernetes/ingress.yaml

# Wait for deployment
kubectl rollout status deployment/cargo-tracker -n cargo-tracker

# Check status
kubectl get pods,svc,ingress -n cargo-tracker
```

### Step 5: Access the Application

```bash
# Get the Load Balancer URL
kubectl get ingress cargo-tracker-ingress -n cargo-tracker

# Output will show the ALB hostname
# Access: http://<alb-hostname>/cargo-tracker/
```

**Note**: It may take 2-3 minutes for the ALB to become fully available.

---

## Configuration Management

### Environment Variables

The application supports the following environment variables:

#### Java/JVM Configuration:
- `JAVA_OPTS`: JVM options (default: `-Xmx512m -Xms256m -XX:+UseContainerSupport -XX:MaxRAMPercentage=75.0`)
- `TZ`: Timezone (default: `UTC`)

#### Database Configuration (for external database):
- `DB_DRIVER_CLASS`: JDBC driver class (e.g., `org.postgresql.ds.PGPoolingDataSource`)
- `DB_JDBC_URL`: JDBC connection URL
- `DB_USER`: Database username
- `DB_PASSWORD`: Database password (use Kubernetes secrets)

#### Application Configuration:
- `GRAPH_TRAVERSAL_URL`: URL for graph traversal service

### Using Kubernetes Secrets

For sensitive data like database passwords:

```bash
# Create secret
kubectl create secret generic cargo-tracker-db-secret \
  --from-literal=password='your-secure-password' \
  --namespace=cargo-tracker

# Reference in deployment.yaml (already configured)
# env:
# - name: DB_PASSWORD
#   valueFrom:
#     secretKeyRef:
#       name: cargo-tracker-db-secret
#       key: password
```

### Using ConfigMaps

For non-sensitive configuration:

```bash
# Create ConfigMap
kubectl create configmap cargo-tracker-config \
  --from-literal=graph.traversal.url='http://localhost:8080/cargo-tracker/rest/graph-traversal/shortest-path' \
  --namespace=cargo-tracker

# Reference in deployment.yaml
# env:
# - name: GRAPH_TRAVERSAL_URL
#   valueFrom:
#     configMapKeyRef:
#       name: cargo-tracker-config
#       key: graph.traversal.url
```

---

## Monitoring and Troubleshooting

### View Application Logs

```bash
# View logs from all pods
kubectl logs -f deployment/cargo-tracker -n cargo-tracker

# View logs from specific pod
kubectl logs -f <pod-name> -n cargo-tracker

# View previous container logs (if pod restarted)
kubectl logs --previous <pod-name> -n cargo-tracker
```

### Check Pod Status

```bash
# List all pods
kubectl get pods -n cargo-tracker

# Describe pod (detailed information)
kubectl describe pod <pod-name> -n cargo-tracker

# Get pod events
kubectl get events -n cargo-tracker --sort-by='.lastTimestamp'
```

### Common Issues and Solutions

#### 1. Pod in CrashLoopBackOff

**Symptoms**: Pod keeps restarting
```bash
kubectl describe pod <pod-name> -n cargo-tracker
kubectl logs <pod-name> -n cargo-tracker
```

**Common Causes**:
- Application startup failure
- Insufficient memory/CPU
- Missing environment variables
- Database connection issues

**Solutions**:
- Check application logs for errors
- Increase resource limits in deployment.yaml
- Verify environment variables are set correctly
- Ensure database is accessible

#### 2. ImagePullBackOff

**Symptoms**: Cannot pull Docker image
```bash
kubectl describe pod <pod-name> -n cargo-tracker
```

**Common Causes**:
- Incorrect image URI
- Missing ECR permissions
- Image doesn't exist

**Solutions**:
- Verify image URI is correct
- Check ECR repository exists
- Ensure EKS nodes have ECR pull permissions
- For private Docker Hub images, create image pull secret

#### 3. Service Not Accessible

**Symptoms**: Cannot access application via Load Balancer

**Solutions**:
```bash
# Check service
kubectl get svc -n cargo-tracker

# Check ingress
kubectl get ingress -n cargo-tracker
kubectl describe ingress cargo-tracker-ingress -n cargo-tracker

# Check AWS Load Balancer Controller logs
kubectl logs -n kube-system deployment/aws-load-balancer-controller
```

#### 4. Health Check Failures

**Symptoms**: Pods marked as not ready

**Solutions**:
- Increase `initialDelaySeconds` in liveness/readiness probes
- Verify health check endpoint is accessible
- Check application startup time
- Review application logs for startup errors

### Debug Pod Issues

```bash
# Execute shell in running pod
kubectl exec -it <pod-name> -n cargo-tracker -- /bin/sh

# Check application files
ls -la /opt/payara/deployments/

# Test health endpoint
curl http://localhost:8080/cargo-tracker/
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
# Create HPA based on CPU utilization
kubectl autoscale deployment cargo-tracker \
  --cpu-percent=70 \
  --min=2 \
  --max=10 \
  -n cargo-tracker

# Check HPA status
kubectl get hpa -n cargo-tracker

# Describe HPA
kubectl describe hpa cargo-tracker -n cargo-tracker
```

### Rolling Updates

```bash
# Update image to new version
kubectl set image deployment/cargo-tracker \
  cargo-tracker=<new-image-uri> \
  -n cargo-tracker

# Monitor rollout
kubectl rollout status deployment/cargo-tracker -n cargo-tracker

# Check rollout history
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

Update resource limits in `kubernetes/deployment.yaml`:

```yaml
resources:
  requests:
    cpu: "500m"      # Increase for better performance
    memory: "1Gi"    # Increase if OOM errors occur
  limits:
    cpu: "1000m"     # Maximum CPU
    memory: "2Gi"    # Maximum memory
```

Apply changes:
```bash
kubectl apply -f kubernetes/deployment.yaml
```

---

## Security Considerations

### 1. Container Security

- **Non-root User**: Application runs as non-root user (payara:1001)
- **Read-only Root Filesystem**: Consider adding to deployment:
  ```yaml
  securityContext:
    readOnlyRootFilesystem: true
    runAsNonRoot: true
    runAsUser: 1001
  ```

### 2. Network Security

- **Network Policies**: Restrict pod-to-pod communication
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
  ```

### 3. Secrets Management

- **Never commit secrets to Git**
- Use Kubernetes Secrets for sensitive data
- Consider AWS Secrets Manager integration:
  ```bash
  # Install External Secrets Operator
  helm repo add external-secrets https://charts.external-secrets.io
  helm install external-secrets external-secrets/external-secrets -n external-secrets-system --create-namespace
  ```

### 4. Image Security

- **Scan images for vulnerabilities**:
  ```bash
  # Using AWS ECR image scanning
  aws ecr start-image-scan --repository-name cargo-tracker --image-id imageTag=latest
  
  # Get scan results
  aws ecr describe-image-scan-findings --repository-name cargo-tracker --image-id imageTag=latest
  ```

### 5. RBAC (Role-Based Access Control)

Create service account with limited permissions:

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: cargo-tracker-sa
  namespace: cargo-tracker
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: cargo-tracker-role
  namespace: cargo-tracker
rules:
- apiGroups: [""]
  resources: ["configmaps", "secrets"]
  verbs: ["get", "list"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: cargo-tracker-rolebinding
  namespace: cargo-tracker
subjects:
- kind: ServiceAccount
  name: cargo-tracker-sa
roleRef:
  kind: Role
  name: cargo-tracker-role
  apiGroup: rbac.authorization.k8s.io
```

---

## Technology-Specific Notes

### Jakarta EE 10 / Payara Micro

#### Application Server Configuration

- **Payara Micro Version**: 6.2025.3
- **Jakarta EE Version**: 10.0.0
- **Java Version**: 11

#### JVM Tuning for Containers

The Dockerfile includes optimized JVM settings:

```bash
JAVA_OPTS="-Xmx512m -Xms256m -XX:+UseContainerSupport -XX:MaxRAMPercentage=75.0"
```

**Explanation**:
- `-Xmx512m`: Maximum heap size
- `-Xms256m`: Initial heap size
- `-XX:+UseContainerSupport`: Enable container awareness
- `-XX:MaxRAMPercentage=75.0`: Use 75% of container memory limit

**Adjust for your needs**:
- For memory-intensive applications, increase heap size
- Monitor with: `kubectl top pods -n cargo-tracker`

#### Database Configuration

**H2 Embedded (Default)**:
- Data persisted in `/opt/payara/cargo-tracker-data`
- Suitable for development/testing
- Not recommended for production

**PostgreSQL (Production)**:
1. Update deployment.yaml environment variables:
   ```yaml
   - name: DB_DRIVER_CLASS
     value: "org.postgresql.ds.PGPoolingDataSource"
   - name: DB_JDBC_URL
     value: "jdbc:postgresql://postgres-host:5432/cargotracker"
   - name: DB_USER
     value: "postgres"
   - name: DB_PASSWORD
     valueFrom:
       secretKeyRef:
         name: cargo-tracker-db-secret
         key: password
   ```

2. Ensure PostgreSQL JDBC driver is included in WAR (already configured in pom.xml cloud profile)

#### JMS Configuration

The application uses JMS queues for event processing:
- CargoHandledQueue
- MisdirectedCargoQueue
- DeliveredCargoQueue
- RejectedRegistrationAttemptsQueue
- HandlingEventRegistrationAttemptQueue

Payara Micro includes embedded JMS broker (OpenMQ).

#### Monitoring with JMX

To enable JMX monitoring, add to deployment.yaml:

```yaml
env:
- name: JAVA_OPTS
  value: "-Xmx512m -Xms256m -XX:+UseContainerSupport -XX:MaxRAMPercentage=75.0 -Dcom.sun.management.jmxremote -Dcom.sun.management.jmxremote.port=9010 -Dcom.sun.management.jmxremote.authenticate=false -Dcom.sun.management.jmxremote.ssl=false"
ports:
- containerPort: 9010
  name: jmx
  protocol: TCP
```

#### Application Profiles

The application supports multiple Maven profiles:
- **payara** (default): Payara with H2
- **glassfish**: GlassFish with H2
- **cloud**: Payara with PostgreSQL
- **openliberty**: Open Liberty with HSQLDB

For cloud deployment, build with cloud profile:
```bash
mvn clean package -Pcloud -DpostgreSqlJdbcUrl="jdbc:postgresql://host:5432/db" -DpostgreSqlUsername="user" -DpostgreSqlPassword="pass"
```

---

## Additional Resources

### Documentation
- [Jakarta EE 10 Documentation](https://jakarta.ee/specifications/platform/10/)
- [Payara Micro Documentation](https://docs.payara.fish/community/docs/documentation/payara-micro/payara-micro.html)
- [AWS EKS Documentation](https://docs.aws.amazon.com/eks/)
- [Kubernetes Documentation](https://kubernetes.io/docs/)

### Useful Commands Reference

```bash
# Kubernetes
kubectl get all -n cargo-tracker                    # List all resources
kubectl describe deployment cargo-tracker -n cargo-tracker  # Deployment details
kubectl logs -f deployment/cargo-tracker -n cargo-tracker   # Follow logs
kubectl exec -it <pod> -n cargo-tracker -- /bin/sh  # Shell access
kubectl port-forward svc/cargo-tracker-service 8080:80 -n cargo-tracker  # Port forward

# Docker
docker ps                                           # List running containers
docker logs -f cargo-tracker                        # Follow container logs
docker exec -it cargo-tracker /bin/sh               # Shell access
docker system prune -a                              # Clean up unused images

# AWS
aws eks list-clusters --region us-east-1            # List EKS clusters
aws ecr describe-repositories --region us-east-1    # List ECR repositories
aws eks describe-cluster --name <cluster> --region us-east-1  # Cluster details
```

---

## Support and Troubleshooting

If you encounter issues:

1. **Check application logs**: `kubectl logs -f deployment/cargo-tracker -n cargo-tracker`
2. **Check pod status**: `kubectl describe pod <pod-name> -n cargo-tracker`
3. **Verify configuration**: Review environment variables and secrets
4. **Check resource usage**: `kubectl top pods -n cargo-tracker`
5. **Review events**: `kubectl get events -n cargo-tracker --sort-by='.lastTimestamp'`

For Jakarta EE specific issues, refer to the [Cargo Tracker GitHub repository](https://github.com/eclipse-ee4j/cargotracker).

---

## Cleanup

To remove all deployed resources:

```bash
# Delete namespace (removes all resources)
kubectl delete namespace cargo-tracker

# Delete EKS cluster (if no longer needed)
eksctl delete cluster --name cargo-tracker-cluster --region us-east-1

# Delete ECR repository
aws ecr delete-repository --repository-name cargo-tracker --region us-east-1 --force
```

---

**Last Updated**: 2025
**Version**: 1.0
