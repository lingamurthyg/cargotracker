# Cargo Tracker - AWS EKS Deployment Guide

## Table of Contents
1. [Overview](#overview)
2. [Prerequisites](#prerequisites)
3. [Local Development Setup](#local-development-setup)
4. [Building and Pushing Docker Images](#building-and-pushing-docker-images)
5. [AWS EKS Setup](#aws-eks-setup)
6. [Deploying to AWS EKS](#deploying-to-aws-eks)
7. [Configuration Management](#configuration-management)
8. [Monitoring and Troubleshooting](#monitoring-and-troubleshooting)
9. [Scaling and Management](#scaling-and-management)
10. [Security Considerations](#security-considerations)

---

## Overview

Eclipse Cargo Tracker is a Jakarta EE 10 application demonstrating Domain-Driven Design (DDD) principles. This guide covers containerization and deployment to AWS EKS (Elastic Kubernetes Service).

**Technology Stack:**
- Java 11
- Jakarta EE 10
- Payara Server 6.2025.3
- Maven 3.9.4
- H2 Database (embedded) or PostgreSQL (production)

**Deployment Architecture:**
- Container Platform: Docker
- Orchestration: Kubernetes (AWS EKS)
- Load Balancing: AWS Application Load Balancer (ALB)
- Container Registry: AWS ECR or Docker Hub

---

## Prerequisites

### Required Tools

1. **Docker** (version 20.10+)
   - Download: https://www.docker.com/products/docker-desktop
   - Verify: `docker --version`

2. **AWS CLI** (version 2.x)
   - Download: https://aws.amazon.com/cli/
   - Verify: `aws --version`
   - Configure: `aws configure`

3. **kubectl** (version 1.28+)
   - Download: https://kubernetes.io/docs/tasks/tools/
   - Verify: `kubectl version --client`

4. **eksctl** (optional, for cluster creation)
   - Download: https://eksctl.io/
   - Verify: `eksctl version`

### AWS Requirements

1. **AWS Account** with appropriate permissions
2. **IAM Permissions** for:
   - EKS cluster management
   - ECR repository access
   - VPC and networking
   - IAM role creation
   - CloudWatch logs

3. **EKS Cluster** (if not already created)
   - Kubernetes version 1.28+
   - Worker nodes with sufficient resources
   - AWS Load Balancer Controller installed

### System Requirements

- **Development Machine:**
  - 8GB RAM minimum
  - 20GB free disk space
  - Internet connectivity

- **EKS Worker Nodes:**
  - t3.medium or larger
  - 2+ nodes recommended for high availability

---

## Local Development Setup

### 1. Clone the Repository

```bash
git clone https://github.com/eclipse-ee4j/cargotracker.git
cd cargotracker
```

### 2. Build with Maven

```bash
# Build the WAR file
mvn clean package -DskipTests

# The WAR file will be created at: target/cargo-tracker.war
```

### 3. Run with Docker Compose

```bash
# Build and start the application
docker-compose up --build

# Access the application
# Web UI: http://localhost:8080/cargo-tracker
# Health Check: http://localhost:8080/cargo-tracker/rest/health
# Admin Console: http://localhost:4848
```

### 4. Stop the Application

```bash
docker-compose down

# Remove volumes (database data)
docker-compose down -v
```

---

## Building and Pushing Docker Images

### Option 1: Using build-push.sh (Linux/macOS)

```bash
cd scripts
chmod +x build-push.sh
./build-push.sh
```

**Interactive Prompts:**
1. Enter Docker image tag (default: latest)
2. Select registry (1: AWS ECR, 2: Docker Hub)
3. Enter registry credentials

**AWS ECR Example:**
```
Enter Docker image tag: v1.0.0
Select Docker Registry: 1
Enter AWS Region: us-east-1
Enter AWS Account ID: 123456789012
Enter ECR Repository Name: cargo-tracker
```

**Docker Hub Example:**
```
Enter Docker image tag: v1.0.0
Select Docker Registry: 2
Enter Docker Hub Username: myusername
Enter Docker Hub Password: ********
```

### Option 2: Using build-push.bat (Windows)

```cmd
cd scripts
build-push.bat
```

Follow the same interactive prompts as above.

### Manual Build and Push

```bash
# Build the image
docker build -t cargo-tracker:latest .

# Tag for ECR
docker tag cargo-tracker:latest 123456789012.dkr.ecr.us-east-1.amazonaws.com/cargo-tracker:latest

# Login to ECR
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin 123456789012.dkr.ecr.us-east-1.amazonaws.com

# Push to ECR
docker push 123456789012.dkr.ecr.us-east-1.amazonaws.com/cargo-tracker:latest
```

---

## AWS EKS Setup

### 1. Create EKS Cluster (if needed)

Using eksctl:

```bash
eksctl create cluster \
  --name cargo-tracker-cluster \
  --region us-east-1 \
  --nodegroup-name standard-workers \
  --node-type t3.medium \
  --nodes 2 \
  --nodes-min 2 \
  --nodes-max 4 \
  --managed
```

Using AWS Console:
1. Navigate to EKS service
2. Click "Create cluster"
3. Configure cluster settings
4. Create node group
5. Wait for cluster to be ready

### 2. Configure kubectl

```bash
aws eks update-kubeconfig --region us-east-1 --name cargo-tracker-cluster

# Verify connection
kubectl cluster-info
kubectl get nodes
```

### 3. Install AWS Load Balancer Controller

```bash
# Create IAM policy
curl -o iam_policy.json https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v2.7.0/docs/install/iam_policy.json

aws iam create-policy \
  --policy-name AWSLoadBalancerControllerIAMPolicy \
  --policy-document file://iam_policy.json

# Create IAM role and service account
eksctl create iamserviceaccount \
  --cluster=cargo-tracker-cluster \
  --namespace=kube-system \
  --name=aws-load-balancer-controller \
  --attach-policy-arn=arn:aws:iam::123456789012:policy/AWSLoadBalancerControllerIAMPolicy \
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

### Option 1: Using deploy-image.sh (Linux/macOS)

```bash
cd scripts
chmod +x deploy-image.sh
./deploy-image.sh
```

**Interactive Prompts:**
1. Enter AWS Region
2. Enter EKS Cluster Name
3. Enter Docker Image URI
4. Enter Database Configuration (optional)

**Example:**
```
Enter AWS Region: us-east-1
Enter EKS Cluster Name: cargo-tracker-cluster
Enter Docker Image URI: 123456789012.dkr.ecr.us-east-1.amazonaws.com/cargo-tracker:latest
Enter DB_DRIVER_CLASS: org.h2.jdbcx.JdbcDataSource
Enter DB_JDBC_URL: jdbc:h2:file:/app/data/cargo-tracker-database
Enter DB_USER: 
Enter DB_PASSWORD: 
```

### Option 2: Using deploy-image.bat (Windows)

```cmd
cd scripts
deploy-image.bat
```

Follow the same interactive prompts as above.

### Option 3: Manual Deployment

```bash
# Update deployment.yaml with your image URI
sed -i 's|{{IMAGE_URI}}|123456789012.dkr.ecr.us-east-1.amazonaws.com/cargo-tracker:latest|g' kubernetes/deployment.yaml

# Apply manifests
kubectl apply -f kubernetes/namespace.yaml
kubectl apply -f kubernetes/deployment.yaml
kubectl apply -f kubernetes/service.yaml
kubectl apply -f kubernetes/ingress.yaml

# Wait for deployment
kubectl rollout status deployment/cargo-tracker -n cargo-tracker

# Verify deployment
kubectl get pods,svc,ingress -n cargo-tracker
```

---

## Configuration Management

### Environment Variables

The application supports the following environment variables:

| Variable | Description | Default |
|----------|-------------|---------|
| `DB_DRIVER_CLASS` | JDBC driver class | `org.h2.jdbcx.JdbcDataSource` |
| `DB_JDBC_URL` | Database JDBC URL | `jdbc:h2:file:/app/data/cargo-tracker-database` |
| `DB_USER` | Database username | (empty) |
| `DB_PASSWORD` | Database password | (empty) |
| `GRAPH_TRAVERSAL_URL` | Graph traversal service URL | Internal service URL |
| `JAVA_OPTS` | JVM options | `-Xmx512m -Xms256m` |
| `TZ` | Timezone | `UTC` |

### Database Configuration

#### H2 Embedded Database (Default)

```yaml
env:
- name: DB_DRIVER_CLASS
  value: "org.h2.jdbcx.JdbcDataSource"
- name: DB_JDBC_URL
  value: "jdbc:h2:file:/app/data/cargo-tracker-database"
```

#### PostgreSQL (Production)

```yaml
env:
- name: DB_DRIVER_CLASS
  value: "org.postgresql.ds.PGPoolingDataSource"
- name: DB_JDBC_URL
  value: "jdbc:postgresql://postgres-host:5432/cargotracker"
- name: DB_USER
  value: "postgres"
- name: DB_PASSWORD
  valueFrom:
    secretKeyRef:
      name: db-credentials
      key: password
```

Create secret:
```bash
kubectl create secret generic db-credentials \
  --from-literal=password=your-password \
  -n cargo-tracker
```

### Kubernetes ConfigMap

For complex configurations:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: cargo-tracker-config
  namespace: cargo-tracker
data:
  application.properties: |
    db.driver=org.postgresql.ds.PGPoolingDataSource
    db.url=jdbc:postgresql://postgres:5432/cargotracker
```

Mount in deployment:
```yaml
volumeMounts:
- name: config
  mountPath: /app/config
volumes:
- name: config
  configMap:
    name: cargo-tracker-config
```

---

## Monitoring and Troubleshooting

### Health Checks

The application exposes health check endpoints:

- **Liveness Probe:** `/cargo-tracker/rest/health/live`
  - Checks if application is running
  - Used by Kubernetes to restart unhealthy pods

- **Readiness Probe:** `/cargo-tracker/rest/health/ready`
  - Checks if application is ready to serve traffic
  - Includes database connectivity check

- **General Health:** `/cargo-tracker/rest/health`
  - Comprehensive health status

### Viewing Logs

```bash
# View logs for all pods
kubectl logs -n cargo-tracker -l app=cargo-tracker

# Follow logs in real-time
kubectl logs -n cargo-tracker -l app=cargo-tracker -f

# View logs for specific pod
kubectl logs -n cargo-tracker <pod-name>

# View previous container logs (after restart)
kubectl logs -n cargo-tracker <pod-name> --previous
```

### Checking Pod Status

```bash
# List all pods
kubectl get pods -n cargo-tracker

# Describe pod (detailed information)
kubectl describe pod -n cargo-tracker <pod-name>

# Get pod events
kubectl get events -n cargo-tracker --sort-by='.lastTimestamp'
```

### Common Issues

#### 1. Pod CrashLoopBackOff

**Symptoms:** Pod keeps restarting

**Diagnosis:**
```bash
kubectl logs -n cargo-tracker <pod-name> --previous
kubectl describe pod -n cargo-tracker <pod-name>
```

**Common Causes:**
- Database connection failure
- Insufficient memory
- Application startup errors
- Missing environment variables

**Solutions:**
- Check database connectivity
- Increase memory limits
- Review application logs
- Verify environment variables

#### 2. ImagePullBackOff

**Symptoms:** Cannot pull Docker image

**Diagnosis:**
```bash
kubectl describe pod -n cargo-tracker <pod-name>
```

**Common Causes:**
- Incorrect image URI
- Missing ECR permissions
- Image doesn't exist

**Solutions:**
- Verify image URI in deployment.yaml
- Check ECR repository exists
- Verify IAM permissions for ECR access

#### 3. Service Not Accessible

**Symptoms:** Cannot access application via LoadBalancer

**Diagnosis:**
```bash
kubectl get svc -n cargo-tracker
kubectl get ingress -n cargo-tracker
kubectl describe ingress cargo-tracker-ingress -n cargo-tracker
```

**Common Causes:**
- ALB not provisioned
- Security group rules
- Ingress misconfiguration

**Solutions:**
- Wait for ALB provisioning (5-10 minutes)
- Check security group allows traffic
- Verify AWS Load Balancer Controller is running

#### 4. Database Connection Errors

**Symptoms:** Application starts but cannot connect to database

**Diagnosis:**
```bash
kubectl logs -n cargo-tracker -l app=cargo-tracker | grep -i database
```

**Solutions:**
- Verify database credentials
- Check database host/port
- Ensure database is accessible from EKS
- Check security groups and network policies

### Debugging Commands

```bash
# Execute command in pod
kubectl exec -it -n cargo-tracker <pod-name> -- /bin/bash

# Port forward to local machine
kubectl port-forward -n cargo-tracker svc/cargo-tracker-service 8080:80

# Check resource usage
kubectl top pods -n cargo-tracker
kubectl top nodes

# View deployment status
kubectl rollout status deployment/cargo-tracker -n cargo-tracker
kubectl rollout history deployment/cargo-tracker -n cargo-tracker
```

---

## Scaling and Management

### Manual Scaling

```bash
# Scale to 3 replicas
kubectl scale deployment cargo-tracker -n cargo-tracker --replicas=3

# Verify scaling
kubectl get pods -n cargo-tracker
```

### Horizontal Pod Autoscaler (HPA)

Create HPA:

```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: cargo-tracker-hpa
  namespace: cargo-tracker
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: cargo-tracker
  minReplicas: 2
  maxReplicas: 10
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 70
  - type: Resource
    resource:
      name: memory
      target:
        type: Utilization
        averageUtilization: 80
```

Apply:
```bash
kubectl apply -f hpa.yaml
kubectl get hpa -n cargo-tracker
```

### Rolling Updates

```bash
# Update image
kubectl set image deployment/cargo-tracker \
  cargo-tracker=123456789012.dkr.ecr.us-east-1.amazonaws.com/cargo-tracker:v2.0.0 \
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
kubectl rollout undo deployment/cargo-tracker -n cargo-tracker --to-revision=2

# Verify rollback
kubectl rollout status deployment/cargo-tracker -n cargo-tracker
```

### Resource Management

Update resource limits:

```yaml
resources:
  requests:
    cpu: "500m"
    memory: "1Gi"
  limits:
    cpu: "2000m"
    memory: "2Gi"
```

Apply changes:
```bash
kubectl apply -f kubernetes/deployment.yaml
```

---

## Security Considerations

### 1. Container Security

- **Non-root User:** Application runs as `payara` user (UID 1001)
- **Read-only Filesystem:** Consider mounting root filesystem as read-only
- **Security Context:**

```yaml
securityContext:
  runAsNonRoot: true
  runAsUser: 1001
  allowPrivilegeEscalation: false
  capabilities:
    drop:
    - ALL
```

### 2. Network Security

- **Network Policies:** Restrict pod-to-pod communication
- **Security Groups:** Configure AWS security groups for EKS nodes
- **TLS/SSL:** Enable HTTPS for ingress

Example Network Policy:

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

### 3. Secrets Management

Use Kubernetes Secrets or AWS Secrets Manager:

```bash
# Create secret
kubectl create secret generic db-credentials \
  --from-literal=username=dbuser \
  --from-literal=password=dbpass \
  -n cargo-tracker

# Use in deployment
env:
- name: DB_USER
  valueFrom:
    secretKeyRef:
      name: db-credentials
      key: username
- name: DB_PASSWORD
  valueFrom:
    secretKeyRef:
      name: db-credentials
      key: password
```

### 4. Image Security

- **Scan Images:** Use AWS ECR image scanning
- **Minimal Base Images:** Use slim/alpine variants
- **Regular Updates:** Keep base images and dependencies updated

Enable ECR scanning:
```bash
aws ecr put-image-scanning-configuration \
  --repository-name cargo-tracker \
  --image-scanning-configuration scanOnPush=true \
  --region us-east-1
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

## Jakarta EE Specific Notes

### Payara Server Configuration

The application uses Payara Server 6.2025.3 with Jakarta EE 10:

- **Domain:** domain1 (default)
- **Auto-deploy:** Enabled for WAR files
- **Admin Console:** Port 4848 (optional, can be disabled in production)

### JMS Configuration

The application uses JMS queues for event processing:
- CargoHandledQueue
- MisdirectedCargoQueue
- DeliveredCargoQueue
- RejectedRegistrationAttemptsQueue
- HandlingEventRegistrationAttemptQueue

These are configured in `web.xml` and automatically created by Payara.

### Data Source Configuration

JDBC data source is configured via environment variables and injected into `web.xml`:

```xml
<data-source>
  <name>java:app/jdbc/CargoTrackerDatabase</name>
  <class-name>${db.driverClass}</class-name>
  <url>${db.jdbcUrl}</url>
  <user>${db.user}</user>
  <password>${db.password}</password>
</data-source>
```

### Performance Tuning

JVM Options for containerized environment:

```bash
JAVA_OPTS="-Xmx512m -Xms256m \
  -XX:+UseContainerSupport \
  -XX:MaxRAMPercentage=75.0 \
  -XX:+UseG1GC \
  -XX:MaxGCPauseMillis=200 \
  -Djava.awt.headless=true"
```

---

## Additional Resources

### Documentation
- [Eclipse Cargo Tracker](https://eclipse-ee4j.github.io/cargotracker/)
- [Jakarta EE 10](https://jakarta.ee/specifications/platform/10/)
- [Payara Server](https://docs.payara.fish/)
- [AWS EKS](https://docs.aws.amazon.com/eks/)
- [Kubernetes](https://kubernetes.io/docs/)

### Support
- GitHub Issues: https://github.com/eclipse-ee4j/cargotracker/issues
- Jakarta EE Community: https://jakarta.ee/connect/

### Best Practices
- Use persistent volumes for production databases
- Implement proper backup strategies
- Monitor application metrics with Prometheus/Grafana
- Set up centralized logging with ELK or CloudWatch
- Implement CI/CD pipelines for automated deployments
- Use infrastructure as code (Terraform/CloudFormation)

---

## Conclusion

This guide provides comprehensive instructions for containerizing and deploying Eclipse Cargo Tracker to AWS EKS. For production deployments, ensure you:

1. Use external databases (PostgreSQL/MySQL)
2. Implement proper monitoring and alerting
3. Configure backup and disaster recovery
4. Enable TLS/SSL for all communications
5. Follow security best practices
6. Implement CI/CD pipelines
7. Document your specific configuration

For questions or issues, refer to the project documentation or open an issue on GitHub.
