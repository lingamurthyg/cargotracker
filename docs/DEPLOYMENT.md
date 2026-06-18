# Cargo Tracker - AWS EKS Deployment Guide

## Table of Contents
1. [Prerequisites](#prerequisites)
2. [Project Overview](#project-overview)
3. [Local Development Setup](#local-development-setup)
4. [Docker Deployment](#docker-deployment)
5. [AWS EKS Deployment](#aws-eks-deployment)
6. [Configuration Management](#configuration-management)
7. [Troubleshooting](#troubleshooting)
8. [Security Considerations](#security-considerations)
9. [Technology-Specific Notes](#technology-specific-notes)

---

## Prerequisites

### Required Tools
- **Docker**: Version 20.10 or higher
- **Docker Compose**: Version 2.0 or higher
- **AWS CLI**: Version 2.x
- **kubectl**: Version 1.28 or higher
- **Java**: JDK 11 (for local development)
- **Maven**: Version 3.9.x (for local builds)
- **Git**: For version control

### AWS Requirements
- Active AWS account with appropriate IAM permissions
- EKS cluster provisioned (or eksctl to create one)
- ECR repository access (or Docker Hub account)
- AWS Load Balancer Controller installed in EKS cluster

### IAM Permissions Required
- ECR: `ecr:GetAuthorizationToken`, `ecr:BatchCheckLayerAvailability`, `ecr:PutImage`, `ecr:CreateRepository`, `ecr:DescribeRepositories`
- EKS: `eks:DescribeCluster`, `eks:ListClusters`
- STS: `sts:GetCallerIdentity`

---

## Project Overview

**Cargo Tracker** is a Jakarta EE 10 application demonstrating Domain-Driven Design (DDD) principles. It's packaged as a WAR file and runs on Open Liberty application server.

### Technology Stack
- **Framework**: Jakarta EE 10
- **Application Server**: Open Liberty 24.x
- **Build Tool**: Maven 3.9.x
- **Java Version**: 11 (builder), 8 (runtime)
- **Database**: H2 (development), PostgreSQL (production)
- **Packaging**: WAR

### Application Architecture
- **Port 8080**: HTTP endpoint
- **Port 8081**: HTTPS endpoint
- **Port 7276**: JMS messaging
- **Port 9100**: JMS SSL
- **Context Root**: `/cargo-tracker/`

---

## Local Development Setup

### 1. Clone Repository
```bash
git clone <repository-url>
cd cargo-tracker
```

### 2. Build Locally with Maven
```bash
# Using default profile (Payara with H2)
mvn clean package

# Using cloud profile with PostgreSQL
mvn clean package -Pcloud \
    -DpostgreSqlJdbcUrl="jdbc:postgresql://localhost:5432/cargotracker" \
    -DpostgreSqlUsername="postgres" \
    -DpostgreSqlPassword="postgres"
```

### 3. Run with Docker Compose
```bash
# Start application
docker-compose up -d

# View logs
docker-compose logs -f

# Stop application
docker-compose down
```

### 4. Access Application
- Application URL: `http://localhost:8080/cargo-tracker/`
- Default credentials: admin/admin (if authentication is enabled)

---

## Docker Deployment

### Build Docker Image

#### Option 1: Manual Build
```bash
# Build image
docker build -t cargo-tracker:latest .

# Run container
docker run -d \
  -p 8080:8080 \
  -p 8081:8081 \
  -e DB_URL="jdbc:h2:mem:testdb;DB_CLOSE_DELAY=-1" \
  -e DB_USER="sa" \
  -e DB_PASSWORD="" \
  --name cargo-tracker-app \
  cargo-tracker:latest
```

#### Option 2: Using Build Script

**Linux/macOS:**
```bash
chmod +x scripts/build-push.sh
./scripts/build-push.sh
```

**Windows:**
```cmd
scripts\build-push.bat
```

The script will prompt for:
- Registry type (AWS ECR or Docker Hub)
- Registry credentials and details
- Image tag (default: latest)

### Push to Registry

The build script automatically pushes to the selected registry. Manual push:

**AWS ECR:**
```bash
# Authenticate
aws ecr get-login-password --region us-east-1 | \
  docker login --username AWS --password-stdin <account-id>.dkr.ecr.us-east-1.amazonaws.com

# Tag and push
docker tag cargo-tracker:latest <account-id>.dkr.ecr.us-east-1.amazonaws.com/cargo-tracker:latest
docker push <account-id>.dkr.ecr.us-east-1.amazonaws.com/cargo-tracker:latest
```

**Docker Hub:**
```bash
docker login
docker tag cargo-tracker:latest <username>/cargo-tracker:latest
docker push <username>/cargo-tracker:latest
```

---

## AWS EKS Deployment

### Step 1: Create EKS Cluster (if not exists)

```bash
# Using eksctl
eksctl create cluster \
  --name cargo-tracker-cluster \
  --region us-east-1 \
  --nodegroup-name standard-workers \
  --node-type t3.medium \
  --nodes 2 \
  --nodes-min 1 \
  --nodes-max 4 \
  --managed

# Verify cluster
kubectl cluster-info
kubectl get nodes
```

### Step 2: Install AWS Load Balancer Controller

```bash
# Create IAM policy
curl -o iam-policy.json https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/main/docs/install/iam_policy.json

aws iam create-policy \
  --policy-name AWSLoadBalancerControllerIAMPolicy \
  --policy-document file://iam-policy.json

# Create service account
eksctl create iamserviceaccount \
  --cluster=cargo-tracker-cluster \
  --namespace=kube-system \
  --name=aws-load-balancer-controller \
  --attach-policy-arn=arn:aws:iam::<account-id>:policy/AWSLoadBalancerControllerIAMPolicy \
  --approve

# Install controller using Helm
helm repo add eks https://aws.github.io/eks-charts
helm repo update

helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName=cargo-tracker-cluster \
  --set serviceAccount.create=false \
  --set serviceAccount.name=aws-load-balancer-controller
```

### Step 3: Deploy Application

#### Option 1: Using Deployment Script (Recommended)

**Linux/macOS:**
```bash
chmod +x scripts/deploy-image.sh
./scripts/deploy-image.sh
```

**Windows:**
```cmd
scripts\deploy-image.bat
```

The script will prompt for:
- AWS region
- EKS cluster name
- Docker image URI
- Environment variables (database URLs, credentials, etc.)

#### Option 2: Manual Deployment

```bash
# Configure kubectl
aws eks update-kubeconfig --region us-east-1 --name cargo-tracker-cluster

# Create namespace
kubectl apply -f kubernetes/namespace.yaml

# Create secrets
kubectl create secret generic cargo-tracker-secrets \
  --from-literal=db-password="your-password" \
  --from-literal=timer-db-password="your-timer-password" \
  --from-literal=admin-password="your-admin-password" \
  --namespace=cargo-tracker

# Update deployment.yaml with your image URI
sed -i 's|{{IMAGE_URI}}|<account-id>.dkr.ecr.us-east-1.amazonaws.com/cargo-tracker:latest|g' kubernetes/deployment.yaml

# Apply manifests
kubectl apply -f kubernetes/deployment.yaml
kubectl apply -f kubernetes/service.yaml
kubectl apply -f kubernetes/ingress.yaml

# Wait for deployment
kubectl rollout status deployment/cargo-tracker -n cargo-tracker

# Verify deployment
kubectl get pods,svc,ingress -n cargo-tracker
```

### Step 4: Access Application

```bash
# Get ingress URL
kubectl get ingress cargo-tracker-ingress -n cargo-tracker

# Access application
# http://<alb-dns-name>/cargo-tracker/
```

---

## Configuration Management

### Environment Variables

The application requires the following environment variables:

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `HTTP_PORT` | HTTP port | 8080 | No |
| `HTTPS_PORT` | HTTPS port | 8081 | No |
| `JMS_PORT` | JMS messaging port | 7276 | No |
| `JMS_SSL_PORT` | JMS SSL port | 9100 | No |
| `DB_URL` | Database JDBC URL | jdbc:h2:mem:testdb | Yes |
| `DB_USER` | Database username | sa | Yes |
| `DB_PASSWORD` | Database password | (empty) | Yes |
| `TIMER_DB_URL` | Timer database URL | jdbc:h2:mem:timerdb | Yes |
| `TIMER_DB_USER` | Timer database user | sa | Yes |
| `TIMER_DB_PASSWORD` | Timer database password | (empty) | Yes |
| `GRAPH_TRAVERSAL_URL` | Graph API URL | http://localhost:8080/graph-traversal/ | No |
| `ADMIN_USER` | Admin username | admin | Yes |
| `ADMIN_PASSWORD` | Admin password | admin | Yes |

### Database Configuration

#### Development (H2 In-Memory)
```bash
DB_URL="jdbc:h2:mem:testdb;DB_CLOSE_DELAY=-1"
DB_USER="sa"
DB_PASSWORD=""
```

#### Production (PostgreSQL)
```bash
DB_URL="jdbc:postgresql://postgres-host:5432/cargotracker"
DB_USER="cargotracker_user"
DB_PASSWORD="secure-password"
```

**Note**: For PostgreSQL, you need to:
1. Mount PostgreSQL JDBC driver to `/opt/ol/wlp/usr/shared/resources/`
2. Update server.xml to reference `postgresql*.jar`

### Secrets Management

For production, use Kubernetes secrets:

```bash
# Create from file
kubectl create secret generic cargo-tracker-secrets \
  --from-file=db-password=./secrets/db-password.txt \
  --from-file=admin-password=./secrets/admin-password.txt \
  --namespace=cargo-tracker

# Or use AWS Secrets Manager with External Secrets Operator
# Install External Secrets Operator
helm repo add external-secrets https://charts.external-secrets.io
helm install external-secrets external-secrets/external-secrets -n external-secrets-system --create-namespace
```

---

## Troubleshooting

### Common Issues

#### 1. Pod Not Starting

```bash
# Check pod status
kubectl get pods -n cargo-tracker

# View pod events
kubectl describe pod <pod-name> -n cargo-tracker

# Check logs
kubectl logs <pod-name> -n cargo-tracker

# Check previous container logs
kubectl logs <pod-name> -n cargo-tracker --previous
```

**Common causes:**
- Image pull errors (check ECR permissions)
- Insufficient resources (check node capacity)
- Configuration errors (check environment variables)
- Database connection failures

#### 2. Service Not Accessible

```bash
# Check service endpoints
kubectl get endpoints -n cargo-tracker

# Test service internally
kubectl run -it --rm debug --image=curlimages/curl --restart=Never -- \
  curl http://cargo-tracker-service.cargo-tracker.svc.cluster.local/cargo-tracker/

# Check ingress
kubectl describe ingress cargo-tracker-ingress -n cargo-tracker
```

#### 3. Application Startup Slow

Open Liberty with Jakarta EE applications can take 90-120 seconds to start. Adjust probe timings if needed:

```yaml
startupProbe:
  httpGet:
    path: /cargo-tracker/
    port: 8080
  initialDelaySeconds: 30
  periodSeconds: 10
  failureThreshold: 12  # 120 seconds total
```

#### 4. Database Connection Issues

```bash
# Check database connectivity from pod
kubectl exec -it <pod-name> -n cargo-tracker -- bash
# Inside pod:
telnet postgres-host 5432
```

### Rollback Deployment

```bash
# View deployment history
kubectl rollout history deployment/cargo-tracker -n cargo-tracker

# Rollback to previous version
kubectl rollout undo deployment/cargo-tracker -n cargo-tracker

# Rollback to specific revision
kubectl rollout undo deployment/cargo-tracker -n cargo-tracker --to-revision=2
```

### Clean Up Resources

```bash
# Delete application
kubectl delete namespace cargo-tracker

# Delete EKS cluster
eksctl delete cluster --name cargo-tracker-cluster --region us-east-1
```

---

## Security Considerations

### 1. Container Security
- ✅ Running as non-root user (liberty)
- ✅ Minimal base image (eclipse-temurin)
- ✅ No unnecessary tools installed
- ⚠️ Consider using distroless images for production

### 2. Secrets Management
- ✅ Secrets stored in Kubernetes Secrets
- ✅ Never commit secrets to version control
- 🔒 Use AWS Secrets Manager for production
- 🔒 Enable encryption at rest for EKS secrets

### 3. Network Security
- Configure security groups to restrict access
- Use private subnets for EKS nodes
- Enable network policies in Kubernetes

### 4. HTTPS/TLS
Configure HTTPS termination at ALB:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  annotations:
    alb.ingress.kubernetes.io/certificate-arn: arn:aws:acm:region:account:certificate/xxx
    alb.ingress.kubernetes.io/listen-ports: '[{"HTTP": 80}, {"HTTPS": 443}]'
    alb.ingress.kubernetes.io/ssl-redirect: '443'
```

### 5. Resource Limits
Always set resource limits to prevent resource exhaustion:

```yaml
resources:
  requests:
    cpu: "500m"
    memory: "1Gi"
  limits:
    cpu: "1000m"
    memory: "2Gi"
```

---

## Technology-Specific Notes

### Jakarta EE and Open Liberty

#### Server Configuration
The server.xml configuration is embedded in the image at:
`/opt/ol/wlp/usr/servers/defaultServer/server.xml`

To customize, mount a ConfigMap:

```yaml
volumes:
- name: liberty-config
  configMap:
    name: liberty-server-config
volumeMounts:
- name: liberty-config
  mountPath: /opt/ol/wlp/usr/servers/defaultServer/server.xml
  subPath: server.xml
```

#### JMS Messaging
The application uses internal Open Liberty messaging engine. For distributed deployments, consider:
- External JMS provider (ActiveMQ, RabbitMQ)
- Update server.xml to use remote connection factories

#### Database Drivers
For PostgreSQL in production:

1. Create init container to download driver:
```yaml
initContainers:
- name: download-jdbc-driver
  image: curlimages/curl:latest
  command:
  - sh
  - -c
  - |
    curl -o /shared/postgresql.jar https://jdbc.postgresql.org/download/postgresql-42.7.5.jar
  volumeMounts:
  - name: shared-libs
    mountPath: /shared
```

2. Mount to runtime container:
```yaml
volumeMounts:
- name: shared-libs
  mountPath: /opt/ol/wlp/usr/shared/resources
```

#### Batch Processing
The application includes Jakarta Batch support. Monitor batch jobs:

```bash
# Access admin console (if enabled)
http://<ingress-url>:9080/adminCenter/

# Or use JMX with port-forward
kubectl port-forward <pod-name> 9443:9443 -n cargo-tracker
```

### Maven Multi-Stage Build

The Dockerfile uses Maven dependency caching:

```dockerfile
# Copy POM first
COPY pom.xml .
RUN mvn dependency:go-offline -B

# Then copy source
COPY src ./src
RUN mvn clean package -DskipTests -B
```

This ensures dependencies are cached and only rebuilt when pom.xml changes.

### Health Checks

**Liveness Probe**: Uses Liberty server status command
```bash
/opt/ol/wlp/bin/server status defaultServer
```

**Readiness Probe**: HTTP check on application context root
```
GET http://localhost:8080/cargo-tracker/
```

---

## Additional Resources

- [Open Liberty Documentation](https://openliberty.io/docs/)
- [Jakarta EE 10 Specification](https://jakarta.ee/specifications/platform/10/)
- [AWS EKS Best Practices](https://aws.github.io/aws-eks-best-practices/)
- [Kubernetes Documentation](https://kubernetes.io/docs/)
- [Cargo Tracker GitHub](https://github.com/eclipse-ee4j/cargotracker)

---

## Support and Contribution

For issues and questions:
- Project Issues: [GitHub Issues](https://github.com/eclipse-ee4j/cargotracker/issues)
- AWS Support: [AWS Support Center](https://console.aws.amazon.com/support/)
- Kubernetes: [Kubernetes Slack](https://kubernetes.slack.com/)

---

**Last Updated**: 2026-06-18  
**Version**: 3.1-SNAPSHOT  
**Maintained By**: Cargo Tracker Team