# Eclipse Cargo Tracker - Deployment Guide

## Table of Contents
1. [Prerequisites](#prerequisites)
2. [Local Development with Docker Compose](#local-development-with-docker-compose)
3. [Building and Pushing Docker Images](#building-and-pushing-docker-images)
4. [AWS EKS Deployment](#aws-eks-deployment)
5. [Configuration Management](#configuration-management)
6. [Monitoring and Troubleshooting](#monitoring-and-troubleshooting)
7. [Security Considerations](#security-considerations)
8. [Jakarta EE Specific Notes](#jakarta-ee-specific-notes)

---

## Prerequisites

### Required Tools

1. **Docker** (version 20.10+)
   - Download: https://www.docker.com/products/docker-desktop
   - Verify: `docker --version`

2. **Docker Compose** (version 2.0+)
   - Included with Docker Desktop
   - Verify: `docker-compose --version`

3. **AWS CLI** (version 2.x)
   - Download: https://aws.amazon.com/cli/
   - Verify: `aws --version`
   - Configure: `aws configure`

4. **kubectl** (version 1.28+)
   - Download: https://kubernetes.io/docs/tasks/tools/
   - Verify: `kubectl version --client`

5. **Java Development Kit** (JDK 11+) - for local builds
   - Download: https://adoptium.net/
   - Verify: `java -version`

6. **Maven** (version 3.9+) - for local builds
   - Download: https://maven.apache.org/download.cgi
   - Verify: `mvn -version`

### AWS Prerequisites

1. **AWS Account** with appropriate permissions:
   - ECR: `ecr:CreateRepository`, `ecr:GetAuthorizationToken`, `ecr:BatchCheckLayerAvailability`, `ecr:PutImage`
   - EKS: `eks:DescribeCluster`, `eks:ListClusters`
   - IAM: Permissions to assume EKS cluster roles

2. **EKS Cluster** (version 1.28+)
   - Create cluster: https://docs.aws.amazon.com/eks/latest/userguide/create-cluster.html
   - Install AWS Load Balancer Controller: https://docs.aws.amazon.com/eks/latest/userguide/aws-load-balancer-controller.html

3. **IAM Roles and Policies**
   - EKS Cluster Role
   - Node Group Role with ECR read permissions

---

## Local Development with Docker Compose

### Quick Start

1. **Clone the repository**:
   ```bash
   cd /path/to/cargo-tracker
   ```

2. **Build and run with Docker Compose**:
   ```bash
   docker-compose up --build
   ```

3. **Access the application**:
   - Application: http://localhost:8080/cargo-tracker/
   - Admin Console: http://localhost:4848 (Payara admin/admin)

4. **Stop the application**:
   ```bash
   docker-compose down
   ```

5. **View logs**:
   ```bash
   docker-compose logs -f cargo-tracker
   ```

### Configuration

Edit `docker-compose.yml` to customize:

- **Ports**: Change `8080:8080` to use different host port
- **Memory**: Adjust `JAVA_OPTS` for heap size (`-Xmx1024m`)
- **Database**: Set `DB_JDBC_URL` for external database
- **Volumes**: Persist data across restarts

---

## Building and Pushing Docker Images

### Option 1: Using Build Scripts (Recommended)

#### Linux/macOS:
```bash
cd /path/to/cargo-tracker
chmod +x scripts/build-push.sh
./scripts/build-push.sh
```

#### Windows:
```cmd
cd \path\to\cargo-tracker
scripts\build-push.bat
```

**The script will prompt for**:
1. Registry type (AWS ECR or Docker Hub)
2. Registry credentials and configuration
3. Image tag (default: `latest`)

### Option 2: Manual Build and Push

#### AWS ECR

1. **Authenticate with ECR**:
   ```bash
   aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin 123456789.dkr.ecr.us-east-1.amazonaws.com
   ```

2. **Create ECR repository** (if not exists):
   ```bash
   aws ecr create-repository --repository-name cargo-tracker --region us-east-1
   ```

3. **Build image**:
   ```bash
   docker build -t cargo-tracker:latest .
   ```

4. **Tag image**:
   ```bash
   docker tag cargo-tracker:latest 123456789.dkr.ecr.us-east-1.amazonaws.com/cargo-tracker:latest
   ```

5. **Push image**:
   ```bash
   docker push 123456789.dkr.ecr.us-east-1.amazonaws.com/cargo-tracker:latest
   ```

#### Docker Hub

1. **Login to Docker Hub**:
   ```bash
   docker login -u your-username
   ```

2. **Build and tag**:
   ```bash
   docker build -t your-username/cargo-tracker:latest .
   ```

3. **Push**:
   ```bash
   docker push your-username/cargo-tracker:latest
   ```

---

## AWS EKS Deployment

### Step 1: Prepare EKS Cluster

1. **Create EKS cluster** (if not exists):
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

2. **Configure kubectl**:
   ```bash
   aws eks update-kubeconfig --region us-east-1 --name cargo-tracker-cluster
   ```

3. **Verify connectivity**:
   ```bash
   kubectl cluster-info
   kubectl get nodes
   ```

### Step 2: Install AWS Load Balancer Controller

1. **Create IAM policy**:
   ```bash
   curl -o iam_policy.json https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/main/docs/install/iam_policy.json
   aws iam create-policy --policy-name AWSLoadBalancerControllerIAMPolicy --policy-document file://iam_policy.json
   ```

2. **Create service account**:
   ```bash
   eksctl create iamserviceaccount \
     --cluster=cargo-tracker-cluster \
     --namespace=kube-system \
     --name=aws-load-balancer-controller \
     --attach-policy-arn=arn:aws:iam::123456789:policy/AWSLoadBalancerControllerIAMPolicy \
     --approve
   ```

3. **Install controller**:
   ```bash
   helm repo add eks https://aws.github.io/eks-charts
   helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
     -n kube-system \
     --set clusterName=cargo-tracker-cluster \
     --set serviceAccount.create=false \
     --set serviceAccount.name=aws-load-balancer-controller
   ```

### Step 3: Deploy Application

#### Using Deployment Script (Recommended)

**Linux/macOS**:
```bash
chmod +x scripts/deploy-image.sh
./scripts/deploy-image.sh
```

**Windows**:
```cmd
scripts\deploy-image.bat
```

**The script will prompt for**:
- AWS Region
- EKS Cluster Name
- Docker Image URI
- Optional: Database JDBC URL

#### Manual Deployment

1. **Update manifests** with your image URI:
   ```bash
   sed -i 's|{{IMAGE_URI}}|123456789.dkr.ecr.us-east-1.amazonaws.com/cargo-tracker:latest|g' kubernetes/deployment.yaml
   sed -i 's|{{DB_JDBC_URL}}|jdbc:h2:file:/opt/payara/cargo-tracker-data/cargo-tracker-database|g' kubernetes/deployment.yaml
   ```

2. **Apply manifests**:
   ```bash
   kubectl apply -f kubernetes/namespace.yaml
   kubectl apply -f kubernetes/deployment.yaml
   kubectl apply -f kubernetes/service.yaml
   kubectl apply -f kubernetes/ingress.yaml
   ```

3. **Wait for deployment**:
   ```bash
   kubectl rollout status deployment/cargo-tracker -n cargo-tracker
   ```

4. **Get ingress URL**:
   ```bash
   kubectl get ingress -n cargo-tracker
   ```

### Step 4: Verify Deployment

```bash
# Check pods
kubectl get pods -n cargo-tracker

# Check services
kubectl get svc -n cargo-tracker

# Check ingress
kubectl get ingress -n cargo-tracker

# View logs
kubectl logs -f deployment/cargo-tracker -n cargo-tracker

# Describe pod (if issues)
kubectl describe pod <pod-name> -n cargo-tracker
```

---

## Configuration Management

### Environment Variables

Key environment variables in `kubernetes/deployment.yaml`:

| Variable | Description | Default |
|----------|-------------|----------|
| `JAVA_OPTS` | JVM memory and GC settings | `-Xms512m -Xmx1024m` |
| `DB_JDBC_URL` | Database JDBC connection URL | H2 file database |
| `GRAPH_TRAVERSAL_URL` | Internal route calculation service | Auto-configured |
| `TZ` | Container timezone | `UTC` |

### Database Configuration

#### Using H2 (Default)
No additional configuration required. Data persists in pod volume.

#### Using PostgreSQL

1. **Update deployment**:
   ```yaml
   env:
   - name: DB_JDBC_URL
     value: "jdbc:postgresql://postgres-host:5432/cargotracker"
   ```

2. **Rebuild with cloud profile** (if needed):
   ```bash
   docker build --build-arg MAVEN_PROFILE=cloud -t cargo-tracker:cloud .
   ```

#### Using External Database

For production, use Amazon RDS:

1. **Create RDS PostgreSQL instance**
2. **Update deployment with RDS endpoint**:
   ```yaml
   env:
   - name: DB_JDBC_URL
     value: "jdbc:postgresql://mydb.abc123.us-east-1.rds.amazonaws.com:5432/cargotracker"
   ```

3. **Store credentials in Kubernetes Secret**:
   ```bash
   kubectl create secret generic db-credentials \
     --from-literal=username=admin \
     --from-literal=password=yourpassword \
     -n cargo-tracker
   ```

### Resource Limits

Adjust in `kubernetes/deployment.yaml`:

```yaml
resources:
  requests:
    cpu: "500m"      # Minimum CPU
    memory: "1Gi"    # Minimum memory
  limits:
    cpu: "2000m"     # Maximum CPU
    memory: "2Gi"    # Maximum memory
```

### Scaling

**Manual scaling**:
```bash
kubectl scale deployment cargo-tracker --replicas=3 -n cargo-tracker
```

**Horizontal Pod Autoscaler (HPA)**:
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
```

Apply:
```bash
kubectl apply -f hpa.yaml
```

---

## Monitoring and Troubleshooting

### Common Issues

#### 1. Pods Not Starting

**Check pod status**:
```bash
kubectl get pods -n cargo-tracker
kubectl describe pod <pod-name> -n cargo-tracker
```

**Common causes**:
- Image pull errors (ECR permissions)
- Insufficient resources
- Configuration errors

**Solution**:
```bash
# Check events
kubectl get events -n cargo-tracker --sort-by='.lastTimestamp'

# Check logs
kubectl logs <pod-name> -n cargo-tracker
```

#### 2. Application Not Accessible

**Check ingress**:
```bash
kubectl get ingress -n cargo-tracker
kubectl describe ingress cargo-tracker-ingress -n cargo-tracker
```

**Verify Load Balancer Controller**:
```bash
kubectl get deployment -n kube-system aws-load-balancer-controller
```

**Port forward for testing**:
```bash
kubectl port-forward svc/cargo-tracker-service 8080:80 -n cargo-tracker
# Access: http://localhost:8080/cargo-tracker/
```

#### 3. Database Connection Errors

**Check database URL**:
```bash
kubectl get deployment cargo-tracker -n cargo-tracker -o yaml | grep DB_JDBC_URL
```

**Test connectivity** (from pod):
```bash
kubectl exec -it <pod-name> -n cargo-tracker -- /bin/bash
telnet postgres-host 5432
```

#### 4. Memory Issues (OOMKilled)

**Check pod status**:
```bash
kubectl get pods -n cargo-tracker
# Look for "OOMKilled" status
```

**Solution**: Increase memory limits in deployment.yaml

### Logging

**View real-time logs**:
```bash
kubectl logs -f deployment/cargo-tracker -n cargo-tracker
```

**View logs for specific pod**:
```bash
kubectl logs <pod-name> -n cargo-tracker --tail=100
```

**Previous pod logs** (if crashed):
```bash
kubectl logs <pod-name> -n cargo-tracker --previous
```

### Health Checks

**Test liveness probe**:
```bash
kubectl exec -it <pod-name> -n cargo-tracker -- curl http://localhost:8080/cargo-tracker/
```

**Check probe configuration**:
```bash
kubectl get deployment cargo-tracker -n cargo-tracker -o yaml | grep -A 10 livenessProbe
```

---

## Security Considerations

### Container Security

1. **Non-root user**: Application runs as `payara` user (UID 1000)
2. **Read-only filesystem**: Consider adding `readOnlyRootFilesystem: true`
3. **Security context**:
   ```yaml
   securityContext:
     runAsNonRoot: true
     runAsUser: 1000
     allowPrivilegeEscalation: false
   ```

### Network Security

1. **Network Policies**: Restrict pod-to-pod communication
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

2. **TLS/HTTPS**: Configure ALB with SSL certificate
   ```yaml
   annotations:
     alb.ingress.kubernetes.io/certificate-arn: arn:aws:acm:region:account:certificate/id
     alb.ingress.kubernetes.io/listen-ports: '[{"HTTP": 80}, {"HTTPS": 443}]'
     alb.ingress.kubernetes.io/ssl-redirect: '443'
   ```

### Secrets Management

1. **Use Kubernetes Secrets** for sensitive data:
   ```bash
   kubectl create secret generic cargo-tracker-secrets \
     --from-literal=db-password=yourpassword \
     -n cargo-tracker
   ```

2. **Mount secrets as environment variables**:
   ```yaml
   env:
   - name: DB_PASSWORD
     valueFrom:
       secretKeyRef:
         name: cargo-tracker-secrets
         key: db-password
   ```

3. **Consider AWS Secrets Manager** with External Secrets Operator

### Image Security

1. **Scan images for vulnerabilities**:
   ```bash
   docker scan cargo-tracker:latest
   aws ecr start-image-scan --repository-name cargo-tracker --image-id imageTag=latest
   ```

2. **Use specific tags** (not `latest`)
3. **Enable image signing** (Docker Content Trust)

---

## Jakarta EE Specific Notes

### Payara Server Configuration

**Admin Console Access** (development only):
```bash
kubectl port-forward svc/cargo-tracker-service 4848:4848 -n cargo-tracker
# Access: http://localhost:4848 (admin/admin)
```

**Domain Configuration**:
- Domain name: `domain1`
- Configuration: `/opt/payara/glassfish/domains/domain1/config/domain.xml`
- Logs: `/opt/payara/glassfish/domains/domain1/logs/server.log`

### JMS Configuration

The application uses built-in JMS queues:
- `CargoHandledQueue`
- `MisdirectedCargoQueue`
- `DeliveredCargoQueue`
- `RejectedRegistrationAttemptsQueue`
- `HandlingEventRegistrationAttemptQueue`

No external message broker required (embedded in Payara).

### JPA and Database Schema

**Auto-generation enabled** (development):
- `jakarta.persistence.schema-generation.database.action=create`

**For production**, consider:
1. Pre-create schema using SQL scripts
2. Set `schema-generation.database.action=none`
3. Use database migration tools (Flyway, Liquibase)

### Performance Tuning

**JVM Options** (adjust in deployment.yaml):
```yaml
env:
- name: JAVA_OPTS
  value: >
    -Xms1024m
    -Xmx2048m
    -XX:+UseG1GC
    -XX:MaxGCPauseMillis=200
    -XX:+UseContainerSupport
    -XX:MaxRAMPercentage=75.0
    -Djava.net.preferIPv4Stack=true
```

**Connection Pool** (web.xml):
- Max pool size: 32 connections
- Min pool size: 2 connections

Adjust based on load.

### Monitoring Jakarta EE Metrics

Payara supports MicroProfile Metrics:

**Enable metrics endpoint** in Payara admin console

**Access metrics**:
```bash
kubectl port-forward svc/cargo-tracker-service 8080:80 -n cargo-tracker
curl http://localhost:8080/metrics
```

**Integrate with Prometheus**:
```yaml
apiVersion: v1
kind: ServiceMonitor
metadata:
  name: cargo-tracker-metrics
  namespace: cargo-tracker
spec:
  selector:
    matchLabels:
      app: cargo-tracker
  endpoints:
  - port: http
    path: /metrics
```

---

## Additional Resources

- **Eclipse Cargo Tracker**: https://eclipse-ee4j.github.io/cargotracker/
- **Jakarta EE**: https://jakarta.ee/
- **Payara Server**: https://www.payara.fish/
- **AWS EKS Documentation**: https://docs.aws.amazon.com/eks/
- **Kubernetes Documentation**: https://kubernetes.io/docs/

---

## Support

For issues or questions:
1. Check application logs: `kubectl logs -f deployment/cargo-tracker -n cargo-tracker`
2. Review Kubernetes events: `kubectl get events -n cargo-tracker`
3. Consult AWS EKS troubleshooting: https://docs.aws.amazon.com/eks/latest/userguide/troubleshooting.html
4. Open issue on GitHub: https://github.com/eclipse-ee4j/cargotracker/issues
