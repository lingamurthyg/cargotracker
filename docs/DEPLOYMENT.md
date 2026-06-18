# Cargo Tracker - Deployment Guide

## Table of Contents
1. [Overview](#overview)
2. [Prerequisites](#prerequisites)
3. [Local Development with Docker](#local-development-with-docker)
4. [Building and Pushing Docker Images](#building-and-pushing-docker-images)
5. [AWS EKS Deployment](#aws-eks-deployment)
6. [Configuration Management](#configuration-management)
7. [Monitoring and Troubleshooting](#monitoring-and-troubleshooting)
8. [Security Considerations](#security-considerations)
9. [Scaling and Performance](#scaling-and-performance)

---

## Overview

Eclipse Cargo Tracker is a Jakarta EE 10 application demonstrating Domain-Driven Design (DDD) principles. This guide covers containerization and deployment to AWS EKS (Elastic Kubernetes Service).

### Technology Stack
- **Framework**: Jakarta EE 10
- **Application Server**: Payara Micro 6.2025.3
- **Java Version**: Java 11
- **Build Tool**: Maven 3.9.4
- **Package Type**: WAR (Web Application Archive)
- **Database**: H2 (embedded) or PostgreSQL (production)
- **Messaging**: JMS (embedded in Payara)

### Application Architecture
- **Port**: 8080 (HTTP)
- **Health Endpoints**: 
  - `/cargo-tracker/rest/health` - General health check
  - `/cargo-tracker/rest/health/live` - Liveness probe
  - `/cargo-tracker/rest/health/ready` - Readiness probe
- **Context Path**: `/cargo-tracker`

---

## Prerequisites

### Required Tools

#### For Local Development
- **Docker**: Version 20.10 or higher
  - Installation: https://docs.docker.com/get-docker/
- **Docker Compose**: Version 2.0 or higher
  - Included with Docker Desktop

#### For AWS EKS Deployment
- **AWS CLI**: Version 2.x
  ```bash
  # Linux/macOS
  curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
  unzip awscliv2.zip
  sudo ./aws/install
  
  # Windows
  # Download and run: https://awscli.amazonaws.com/AWSCLIV2.msi
  ```

- **kubectl**: Kubernetes command-line tool
  ```bash
  # Linux
  curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
  chmod +x kubectl
  sudo mv kubectl /usr/local/bin/
  
  # macOS
  brew install kubectl
  
  # Windows
  choco install kubernetes-cli
  ```

- **eksctl** (optional, for cluster creation):
  ```bash
  # Linux/macOS
  curl --silent --location "https://github.com/weaveworks/eksctl/releases/latest/download/eksctl_$(uname -s)_amd64.tar.gz" | tar xz -C /tmp
  sudo mv /tmp/eksctl /usr/local/bin
  
  # Windows
  choco install eksctl
  ```

### AWS Account Requirements
- Active AWS account with appropriate permissions
- IAM user with the following permissions:
  - EKS cluster access
  - ECR repository access (if using ECR)
  - EC2 and VPC permissions (for EKS node groups)
  - IAM permissions for role creation

### Configure AWS CLI
```bash
aws configure
# Enter your AWS Access Key ID
# Enter your AWS Secret Access Key
# Enter default region (e.g., us-east-1)
# Enter default output format (json)
```

---

## Local Development with Docker

### Quick Start with Docker Compose

1. **Clone the repository** (if not already done):
   ```bash
   cd /path/to/cargo-tracker
   ```

2. **Build and run with Docker Compose**:
   ```bash
   docker-compose up --build
   ```

3. **Access the application**:
   - Application: http://localhost:8080/cargo-tracker
   - Health Check: http://localhost:8080/cargo-tracker/rest/health

4. **Stop the application**:
   ```bash
   docker-compose down
   ```

### Manual Docker Build and Run

1. **Build the Docker image**:
   ```bash
   docker build -t cargo-tracker:latest .
   ```

2. **Run the container**:
   ```bash
   docker run -d \
     --name cargo-tracker \
     -p 8080:8080 \
     -e JAVA_OPTS="-Xmx512m -Xms256m" \
     cargo-tracker:latest
   ```

3. **View logs**:
   ```bash
   docker logs -f cargo-tracker
   ```

4. **Stop and remove container**:
   ```bash
   docker stop cargo-tracker
   docker rm cargo-tracker
   ```

### Using External PostgreSQL Database

Update `docker-compose.yml` environment variables:

```yaml
environment:
  - DB_DRIVER_CLASS=org.postgresql.ds.PGPoolingDataSource
  - DB_JDBC_URL=jdbc:postgresql://your-db-host:5432/cargotracker
  - DB_USER=your-db-user
  - DB_PASSWORD=your-db-password
```

---

## Building and Pushing Docker Images

### Option 1: Using Build Script (Recommended)

#### Linux/macOS
```bash
chmod +x scripts/build-push.sh
./scripts/build-push.sh
```

#### Windows
```cmd
scripts\build-push.bat
```

The script will prompt you for:
1. Registry type (AWS ECR or Docker Hub)
2. Registry credentials and details
3. Image tag (default: latest)

### Option 2: Manual Build and Push

#### AWS ECR

1. **Authenticate with ECR**:
   ```bash
   aws ecr get-login-password --region us-east-1 | \
     docker login --username AWS --password-stdin \
     123456789012.dkr.ecr.us-east-1.amazonaws.com
   ```

2. **Create ECR repository** (if not exists):
   ```bash
   aws ecr create-repository \
     --repository-name cargo-tracker \
     --region us-east-1
   ```

3. **Build and tag image**:
   ```bash
   docker build -t cargo-tracker:latest .
   docker tag cargo-tracker:latest \
     123456789012.dkr.ecr.us-east-1.amazonaws.com/cargo-tracker:latest
   ```

4. **Push to ECR**:
   ```bash
   docker push 123456789012.dkr.ecr.us-east-1.amazonaws.com/cargo-tracker:latest
   ```

#### Docker Hub

1. **Login to Docker Hub**:
   ```bash
   docker login -u your-username
   ```

2. **Build and tag image**:
   ```bash
   docker build -t your-username/cargo-tracker:latest .
   ```

3. **Push to Docker Hub**:
   ```bash
   docker push your-username/cargo-tracker:latest
   ```

---

## AWS EKS Deployment

### Step 1: Create EKS Cluster (if not exists)

#### Using eksctl (Recommended)
```bash
eksctl create cluster \
  --name cargo-tracker-cluster \
  --region us-east-1 \
  --nodegroup-name standard-workers \
  --node-type t3.medium \
  --nodes 2 \
  --nodes-min 1 \
  --nodes-max 4 \
  --managed
```

#### Using AWS Console
1. Navigate to EKS in AWS Console
2. Click "Create cluster"
3. Follow the wizard to configure cluster settings
4. Create node group with at least 2 nodes

### Step 2: Install AWS Load Balancer Controller

The AWS Load Balancer Controller is required for Ingress resources.

1. **Create IAM policy**:
   ```bash
   curl -o iam_policy.json https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v2.7.0/docs/install/iam_policy.json
   
   aws iam create-policy \
     --policy-name AWSLoadBalancerControllerIAMPolicy \
     --policy-document file://iam_policy.json
   ```

2. **Create IAM role and service account**:
   ```bash
   eksctl create iamserviceaccount \
     --cluster=cargo-tracker-cluster \
     --namespace=kube-system \
     --name=aws-load-balancer-controller \
     --attach-policy-arn=arn:aws:iam::ACCOUNT_ID:policy/AWSLoadBalancerControllerIAMPolicy \
     --approve
   ```

3. **Install the controller using Helm**:
   ```bash
   helm repo add eks https://aws.github.io/eks-charts
   helm repo update
   
   helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
     -n kube-system \
     --set clusterName=cargo-tracker-cluster \
     --set serviceAccount.create=false \
     --set serviceAccount.name=aws-load-balancer-controller
   ```

### Step 3: Deploy Application

#### Using Deployment Script (Recommended)

##### Linux/macOS
```bash
chmod +x scripts/deploy-image.sh
./scripts/deploy-image.sh
```

##### Windows
```cmd
scripts\deploy-image.bat
```

The script will prompt you for:
1. AWS Region
2. EKS Cluster Name
3. Docker Image URI

#### Manual Deployment

1. **Configure kubectl**:
   ```bash
   aws eks update-kubeconfig --region us-east-1 --name cargo-tracker-cluster
   ```

2. **Verify connectivity**:
   ```bash
   kubectl cluster-info
   kubectl get nodes
   ```

3. **Update deployment manifest**:
   Edit `kubernetes/deployment.yaml` and replace `{{IMAGE_URI}}` with your actual image URI:
   ```yaml
   image: 123456789012.dkr.ecr.us-east-1.amazonaws.com/cargo-tracker:latest
   ```

4. **Apply Kubernetes manifests**:
   ```bash
   kubectl apply -f kubernetes/namespace.yaml
   kubectl apply -f kubernetes/deployment.yaml
   kubectl apply -f kubernetes/service.yaml
   kubectl apply -f kubernetes/ingress.yaml
   ```

5. **Wait for deployment**:
   ```bash
   kubectl rollout status deployment/cargo-tracker -n cargo-tracker
   ```

6. **Verify deployment**:
   ```bash
   kubectl get pods -n cargo-tracker
   kubectl get svc -n cargo-tracker
   kubectl get ingress -n cargo-tracker
   ```

### Step 4: Access the Application

1. **Get the Load Balancer URL**:
   ```bash
   kubectl get ingress cargo-tracker-ingress -n cargo-tracker
   ```

2. **Wait for the Load Balancer to be provisioned** (may take 2-3 minutes)

3. **Access the application**:
   ```
   http://<load-balancer-dns>/cargo-tracker
   ```

### Step 5: Configure Custom Domain (Optional)

1. **Get the Load Balancer DNS name**:
   ```bash
   kubectl get ingress cargo-tracker-ingress -n cargo-tracker -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
   ```

2. **Create a CNAME record** in your DNS provider:
   - Name: `cargo-tracker.yourdomain.com`
   - Type: CNAME
   - Value: `<load-balancer-dns>`

3. **Update ingress.yaml** with your domain:
   ```yaml
   spec:
     rules:
     - host: cargo-tracker.yourdomain.com
   ```

4. **Reapply ingress**:
   ```bash
   kubectl apply -f kubernetes/ingress.yaml
   ```

---

## Configuration Management

### Environment Variables

The application supports the following environment variables:

| Variable | Description | Default |
|----------|-------------|---------|
| `JAVA_OPTS` | JVM options | `-Xmx512m -Xms256m` |
| `TZ` | Timezone | `UTC` |
| `GRAPH_TRAVERSAL_URL` | Graph traversal service URL | `http://localhost:8080/cargo-tracker/rest/graph-traversal/shortest-path` |
| `DB_DRIVER_CLASS` | Database driver class | `org.h2.jdbcx.JDBCDataSource` |
| `DB_JDBC_URL` | Database JDBC URL | `jdbc:h2:file:/app/data/cargo-tracker-database` |
| `DB_USER` | Database username | (empty) |
| `DB_PASSWORD` | Database password | (empty) |

### Using Kubernetes Secrets

For sensitive data like database credentials:

1. **Create a secret**:
   ```bash
   kubectl create secret generic cargo-tracker-db-secret \
     --from-literal=jdbc-url='jdbc:postgresql://db-host:5432/cargotracker' \
     --from-literal=username='dbuser' \
     --from-literal=password='dbpassword' \
     -n cargo-tracker
   ```

2. **Update deployment.yaml** to use the secret:
   ```yaml
   env:
   - name: DB_JDBC_URL
     valueFrom:
       secretKeyRef:
         name: cargo-tracker-db-secret
         key: jdbc-url
   - name: DB_USER
     valueFrom:
       secretKeyRef:
         name: cargo-tracker-db-secret
         key: username
   - name: DB_PASSWORD
     valueFrom:
       secretKeyRef:
         name: cargo-tracker-db-secret
         key: password
   ```

### Using ConfigMaps

For non-sensitive configuration:

1. **Create a ConfigMap**:
   ```bash
   kubectl create configmap cargo-tracker-config \
     --from-literal=graph.traversal.url='http://api.example.com/path' \
     -n cargo-tracker
   ```

2. **Reference in deployment**:
   ```yaml
   env:
   - name: GRAPH_TRAVERSAL_URL
     valueFrom:
       configMapKeyRef:
         name: cargo-tracker-config
         key: graph.traversal.url
   ```

---

## Monitoring and Troubleshooting

### Health Checks

The application provides three health check endpoints:

1. **General Health**: `/cargo-tracker/rest/health`
   ```bash
   curl http://<app-url>/cargo-tracker/rest/health
   ```

2. **Liveness Probe**: `/cargo-tracker/rest/health/live`
   - Used by Kubernetes to determine if the pod should be restarted

3. **Readiness Probe**: `/cargo-tracker/rest/health/ready`
   - Used by Kubernetes to determine if the pod can receive traffic

### Viewing Logs

```bash
# View logs from all pods
kubectl logs -f deployment/cargo-tracker -n cargo-tracker

# View logs from a specific pod
kubectl logs -f <pod-name> -n cargo-tracker

# View logs from previous container instance
kubectl logs <pod-name> -n cargo-tracker --previous
```

### Debugging Pods

```bash
# Describe pod to see events and status
kubectl describe pod <pod-name> -n cargo-tracker

# Get pod details
kubectl get pod <pod-name> -n cargo-tracker -o yaml

# Execute commands in a pod
kubectl exec -it <pod-name> -n cargo-tracker -- /bin/bash
```

### Common Issues and Solutions

#### Issue: Pods are in CrashLoopBackOff

**Symptoms**: Pods continuously restart

**Solutions**:
1. Check logs: `kubectl logs <pod-name> -n cargo-tracker`
2. Verify image URI is correct in deployment.yaml
3. Check resource limits (CPU/memory)
4. Verify database connectivity if using external database

#### Issue: Ingress not getting an address

**Symptoms**: `kubectl get ingress` shows no ADDRESS

**Solutions**:
1. Verify AWS Load Balancer Controller is installed:
   ```bash
   kubectl get deployment -n kube-system aws-load-balancer-controller
   ```
2. Check controller logs:
   ```bash
   kubectl logs -n kube-system deployment/aws-load-balancer-controller
   ```
3. Verify IAM permissions for the controller

#### Issue: Application not accessible

**Symptoms**: Cannot access application via Load Balancer URL

**Solutions**:
1. Verify pods are running: `kubectl get pods -n cargo-tracker`
2. Check service: `kubectl get svc -n cargo-tracker`
3. Verify security groups allow traffic on port 80/443
4. Check ingress configuration: `kubectl describe ingress -n cargo-tracker`

#### Issue: Database connection errors

**Symptoms**: Application logs show database connection failures

**Solutions**:
1. Verify database credentials in secrets
2. Check database connectivity from pod:
   ```bash
   kubectl exec -it <pod-name> -n cargo-tracker -- /bin/bash
   # Try connecting to database
   ```
3. Verify database security groups allow traffic from EKS nodes

---

## Security Considerations

### Container Security

1. **Non-root User**: The Dockerfile creates and uses a non-root user (`payara`)
2. **Minimal Base Image**: Uses Amazon Corretto 11 (as specified)
3. **No Unnecessary Tools**: Dockerfile doesn't install curl, wget, or other tools

### Kubernetes Security

1. **Network Policies**: Implement network policies to restrict pod-to-pod communication
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

2. **Pod Security Standards**: Apply pod security standards
   ```yaml
   apiVersion: v1
   kind: Namespace
   metadata:
     name: cargo-tracker
     labels:
       pod-security.kubernetes.io/enforce: restricted
       pod-security.kubernetes.io/audit: restricted
       pod-security.kubernetes.io/warn: restricted
   ```

3. **Secrets Management**: Use AWS Secrets Manager or HashiCorp Vault for sensitive data

4. **RBAC**: Implement Role-Based Access Control
   ```bash
   kubectl create role cargo-tracker-role \
     --verb=get,list,watch \
     --resource=pods,services \
     -n cargo-tracker
   ```

### AWS Security

1. **IAM Roles**: Use IAM roles for service accounts (IRSA)
2. **Security Groups**: Configure security groups to allow only necessary traffic
3. **VPC**: Deploy EKS in a private VPC with proper subnet configuration
4. **Encryption**: Enable encryption at rest for EBS volumes and secrets

---

## Scaling and Performance

### Horizontal Pod Autoscaling (HPA)

1. **Install Metrics Server** (if not already installed):
   ```bash
   kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
   ```

2. **Create HPA**:
   ```bash
   kubectl autoscale deployment cargo-tracker \
     --cpu-percent=70 \
     --min=2 \
     --max=10 \
     -n cargo-tracker
   ```

3. **Verify HPA**:
   ```bash
   kubectl get hpa -n cargo-tracker
   ```

### Manual Scaling

```bash
# Scale to 5 replicas
kubectl scale deployment/cargo-tracker --replicas=5 -n cargo-tracker

# Verify scaling
kubectl get pods -n cargo-tracker
```

### Resource Optimization

Current resource configuration:
- **Requests**: CPU: 250m, Memory: 512Mi
- **Limits**: CPU: 500m, Memory: 1Gi

Adjust based on your workload:

```yaml
resources:
  requests:
    cpu: "500m"
    memory: "1Gi"
  limits:
    cpu: "1000m"
    memory: "2Gi"
```

### Performance Tuning

#### JVM Tuning

Adjust `JAVA_OPTS` in deployment.yaml:

```yaml
env:
- name: JAVA_OPTS
  value: "-Xmx1024m -Xms512m -XX:+UseG1GC -XX:MaxGCPauseMillis=200 -XX:+UseContainerSupport -XX:MaxRAMPercentage=75.0"
```

#### Database Connection Pooling

For production with PostgreSQL, configure connection pool in `web.xml`:

```xml
<data-source>
  <name>java:app/jdbc/CargoTrackerDatabase</name>
  <class-name>org.postgresql.ds.PGPoolingDataSource</class-name>
  <url>${db.jdbcUrl}</url>
  <user>${db.user}</user>
  <password>${db.password}</password>
  <max-pool-size>50</max-pool-size>
  <min-pool-size>10</min-pool-size>
</data-source>
```

---

## Rolling Updates and Rollbacks

### Performing a Rolling Update

1. **Update the image**:
   ```bash
   kubectl set image deployment/cargo-tracker \
     cargo-tracker=123456789012.dkr.ecr.us-east-1.amazonaws.com/cargo-tracker:v2.0 \
     -n cargo-tracker
   ```

2. **Monitor the rollout**:
   ```bash
   kubectl rollout status deployment/cargo-tracker -n cargo-tracker
   ```

### Rolling Back

```bash
# Rollback to previous version
kubectl rollout undo deployment/cargo-tracker -n cargo-tracker

# Rollback to specific revision
kubectl rollout undo deployment/cargo-tracker --to-revision=2 -n cargo-tracker

# View rollout history
kubectl rollout history deployment/cargo-tracker -n cargo-tracker
```

---

## Cleanup

### Delete Application

```bash
# Delete entire namespace (removes all resources)
kubectl delete namespace cargo-tracker
```

### Delete EKS Cluster

```bash
# Using eksctl
eksctl delete cluster --name cargo-tracker-cluster --region us-east-1
```

### Delete ECR Repository

```bash
aws ecr delete-repository \
  --repository-name cargo-tracker \
  --region us-east-1 \
  --force
```

---

## Additional Resources

- [Jakarta EE Documentation](https://jakarta.ee/)
- [Payara Documentation](https://docs.payara.fish/)
- [AWS EKS Documentation](https://docs.aws.amazon.com/eks/)
- [Kubernetes Documentation](https://kubernetes.io/docs/)
- [Docker Documentation](https://docs.docker.com/)

---

## Support and Contribution

For issues and contributions, please refer to the project repository:
- GitHub: https://github.com/eclipse-ee4j/cargotracker

---

**Last Updated**: 2025
**Version**: 1.0
