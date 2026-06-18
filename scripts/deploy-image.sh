#!/bin/bash
set -e
set -o pipefail

echo "====================================="
echo "AWS EKS Deployment Script"
echo "Cargo Tracker Application"
echo "====================================="

# AWS Configuration
echo ""
echo "=== AWS EKS Configuration ==="
read -p "Enter AWS Region (e.g., us-east-1): " AWS_REGION
read -p "Enter EKS Cluster Name: " CLUSTER_NAME

if [ -z "$AWS_REGION" ] || [ -z "$CLUSTER_NAME" ]; then
    echo "Error: AWS Region and EKS Cluster Name are required"
    exit 1
fi

# Docker Image Configuration
echo ""
echo "=== Docker Image Configuration ==="
read -p "Enter Docker Image URI (with tag): " IMAGE_URI

if [ -z "$IMAGE_URI" ]; then
    echo "Error: Docker Image URI is required"
    exit 1
fi

# Application Environment Variables
echo ""
echo "=== Application Configuration ==="
echo "Configure environment variables (press Enter to use defaults)"

read -p "Enter Database URL [jdbc:h2:mem:testdb;DB_CLOSE_DELAY=-1]: " DB_URL
DB_URL=${DB_URL:-"jdbc:h2:mem:testdb;DB_CLOSE_DELAY=-1"}

read -p "Enter Database User [sa]: " DB_USER
DB_USER=${DB_USER:-"sa"}

read -sp "Enter Database Password (hidden) [empty]: " DB_PASSWORD
echo ""
DB_PASSWORD=${DB_PASSWORD:-""}

read -p "Enter Timer Database URL [jdbc:h2:mem:timerdb;DB_CLOSE_DELAY=-1]: " TIMER_DB_URL
TIMER_DB_URL=${TIMER_DB_URL:-"jdbc:h2:mem:timerdb;DB_CLOSE_DELAY=-1"}

read -p "Enter Timer Database User [sa]: " TIMER_DB_USER
TIMER_DB_USER=${TIMER_DB_USER:-"sa"}

read -sp "Enter Timer Database Password (hidden) [empty]: " TIMER_DB_PASSWORD
echo ""
TIMER_DB_PASSWORD=${TIMER_DB_PASSWORD:-""}

read -p "Enter Graph Traversal URL [http://localhost:8080/graph-traversal/]: " GRAPH_TRAVERSAL_URL
GRAPH_TRAVERSAL_URL=${GRAPH_TRAVERSAL_URL:-"http://localhost:8080/graph-traversal/"}

read -p "Enter Admin User [admin]: " ADMIN_USER
ADMIN_USER=${ADMIN_USER:-"admin"}

read -sp "Enter Admin Password (hidden) [admin]: " ADMIN_PASSWORD
echo ""
ADMIN_PASSWORD=${ADMIN_PASSWORD:-"admin"}

# Configure kubectl
echo ""
echo "====================================="
echo "Configuring kubectl for EKS..."
echo "====================================="

aws eks update-kubeconfig --region "$AWS_REGION" --name "$CLUSTER_NAME"

if [ $? -ne 0 ]; then
    echo "Error: Failed to configure kubectl for EKS cluster"
    exit 1
fi

# Verify cluster connectivity
echo ""
echo "Verifying cluster connectivity..."
kubectl cluster-info || {
    echo "Error: Unable to connect to Kubernetes cluster"
    exit 1
}

# Update Kubernetes manifests with actual values
echo ""
echo "====================================="
echo "Updating Kubernetes manifests..."
echo "====================================="

MANIFEST_DIR="kubernetes"

if [ ! -d "$MANIFEST_DIR" ]; then
    echo "Error: Kubernetes manifests directory not found: $MANIFEST_DIR"
    exit 1
fi

# Create temporary directory for processed manifests
TMP_DIR=$(mktemp -d)
trap "rm -rf $TMP_DIR" EXIT

cp -r "$MANIFEST_DIR"/* "$TMP_DIR/"

# Replace placeholders in all YAML files
for file in "$TMP_DIR"/*.yaml; do
    if [ -f "$file" ]; then
        sed -i "s|{{IMAGE_URI}}|$IMAGE_URI|g" "$file"
        sed -i "s|{{DB_URL}}|$DB_URL|g" "$file"
        sed -i "s|{{DB_USER}}|$DB_USER|g" "$file"
        sed -i "s|{{TIMER_DB_URL}}|$TIMER_DB_URL|g" "$file"
        sed -i "s|{{TIMER_DB_USER}}|$TIMER_DB_USER|g" "$file"
        sed -i "s|{{GRAPH_TRAVERSAL_URL}}|$GRAPH_TRAVERSAL_URL|g" "$file"
        sed -i "s|{{ADMIN_USER}}|$ADMIN_USER|g" "$file"
    fi
done

# Create Kubernetes secret for sensitive data
echo ""
echo "Creating Kubernetes secrets..."
kubectl create namespace cargo-tracker --dry-run=client -o yaml | kubectl apply -f -

kubectl create secret generic cargo-tracker-secrets \
    --from-literal=db-password="$DB_PASSWORD" \
    --from-literal=timer-db-password="$TIMER_DB_PASSWORD" \
    --from-literal=admin-password="$ADMIN_PASSWORD" \
    --namespace=cargo-tracker \
    --dry-run=client -o yaml | kubectl apply -f -

if [ $? -ne 0 ]; then
    echo "Warning: Failed to create secrets, they may already exist"
fi

# Apply Kubernetes manifests
echo ""
echo "====================================="
echo "Deploying to Kubernetes..."
echo "====================================="

echo "Applying namespace..."
kubectl apply -f "$TMP_DIR/namespace.yaml"

echo "Applying deployment..."
kubectl apply -f "$TMP_DIR/deployment.yaml"

echo "Applying service..."
kubectl apply -f "$TMP_DIR/service.yaml"

echo "Applying ingress..."
kubectl apply -f "$TMP_DIR/ingress.yaml"

# Wait for deployment rollout
echo ""
echo "====================================="
echo "Waiting for deployment to complete..."
echo "====================================="

kubectl rollout status deployment/cargo-tracker -n cargo-tracker --timeout=300s

if [ $? -ne 0 ]; then
    echo "Error: Deployment rollout failed or timed out"
    echo "Check pod status with: kubectl get pods -n cargo-tracker"
    echo "Check logs with: kubectl logs -n cargo-tracker -l app=cargo-tracker"
    exit 1
fi

# Verify deployment
echo ""
echo "====================================="
echo "Verifying deployment..."
echo "====================================="

kubectl get pods,svc,ingress -n cargo-tracker

# Get application URL
echo ""
echo "====================================="
echo "Deployment Complete!"
echo "====================================="

INGRESS_ADDRESS=$(kubectl get ingress cargo-tracker-ingress -n cargo-tracker -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "pending")

if [ "$INGRESS_ADDRESS" != "pending" ] && [ -n "$INGRESS_ADDRESS" ]; then
    echo "Application URL: http://$INGRESS_ADDRESS/cargo-tracker/"
else
    echo "Ingress is being provisioned. Check status with:"
    echo "kubectl get ingress cargo-tracker-ingress -n cargo-tracker"
fi

echo ""
echo "Useful commands:"
echo "  View pods:        kubectl get pods -n cargo-tracker"
echo "  View logs:        kubectl logs -n cargo-tracker -l app=cargo-tracker"
echo "  View services:    kubectl get svc -n cargo-tracker"
echo "  View ingress:     kubectl get ingress -n cargo-tracker"
echo "  Delete deployment: kubectl delete namespace cargo-tracker"
echo ""
echo "====================================="