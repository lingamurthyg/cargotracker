#!/bin/bash
set -e
set -o pipefail

echo "=========================================="
echo "AWS EKS Deployment Script"
echo "=========================================="
echo ""

# Prompt for AWS configuration
read -p "Enter AWS Region (e.g., us-east-1): " AWS_REGION
read -p "Enter EKS Cluster Name: " CLUSTER_NAME
read -p "Enter Docker Image URI (full path with tag): " IMAGE_URI

if [ -z "$AWS_REGION" ] || [ -z "$CLUSTER_NAME" ] || [ -z "$IMAGE_URI" ]; then
    echo "ERROR: All fields are required"
    exit 1
fi

echo ""
echo "=== Optional Environment Variables ==="
echo "Press Enter to skip any optional configuration"
echo ""

# Optional database configuration
read -p "Enter Database Driver Class (or press Enter to skip): " DB_DRIVER_CLASS
read -p "Enter Database JDBC URL (or press Enter to skip): " DB_JDBC_URL
read -p "Enter Database User (or press Enter to skip): " DB_USER
read -sp "Enter Database Password (or press Enter to skip): " DB_PASSWORD
echo ""

echo ""
echo "=========================================="
echo "Configuring kubectl for EKS"
echo "=========================================="
echo ""

# Configure kubectl to use EKS cluster
aws eks update-kubeconfig --region "$AWS_REGION" --name "$CLUSTER_NAME"

if [ $? -ne 0 ]; then
    echo "ERROR: Failed to configure kubectl for EKS cluster"
    exit 1
fi

# Verify cluster connectivity
echo "Verifying cluster connectivity..."
kubectl cluster-info || {
    echo "ERROR: Cannot connect to Kubernetes cluster"
    exit 1
}

echo ""
echo "=========================================="
echo "Updating Kubernetes Manifests"
echo "=========================================="
echo ""

# Create temporary directory for modified manifests
TEMP_DIR=$(mktemp -d)
cp -r kubernetes/* "$TEMP_DIR/"

# Replace IMAGE_URI placeholder
echo "Updating image URI..."
sed -i "s|{{IMAGE_URI}}|$IMAGE_URI|g" "$TEMP_DIR/deployment.yaml"

# Replace optional database configuration if provided
if [ -n "$DB_DRIVER_CLASS" ]; then
    echo "Updating database driver class..."
    sed -i "s|{{DB_DRIVER_CLASS}}|$DB_DRIVER_CLASS|g" "$TEMP_DIR/deployment.yaml"
fi

if [ -n "$DB_JDBC_URL" ]; then
    echo "Updating database JDBC URL..."
    sed -i "s|{{DB_JDBC_URL}}|$DB_JDBC_URL|g" "$TEMP_DIR/deployment.yaml"
fi

if [ -n "$DB_USER" ]; then
    echo "Updating database user..."
    sed -i "s|{{DB_USER}}|$DB_USER|g" "$TEMP_DIR/deployment.yaml"
fi

# Create database secret if password provided
if [ -n "$DB_PASSWORD" ]; then
    echo "Creating database secret..."
    kubectl create secret generic cargo-tracker-db-secret \
        --from-literal=password="$DB_PASSWORD" \
        --namespace=cargo-tracker \
        --dry-run=client -o yaml | kubectl apply -f -
fi

echo ""
echo "=========================================="
echo "Deploying to AWS EKS"
echo "=========================================="
echo ""

# Apply Kubernetes manifests in order
echo "Creating namespace..."
kubectl apply -f "$TEMP_DIR/namespace.yaml"

echo "Deploying application..."
kubectl apply -f "$TEMP_DIR/deployment.yaml"

echo "Creating service..."
kubectl apply -f "$TEMP_DIR/service.yaml"

echo "Creating ingress..."
kubectl apply -f "$TEMP_DIR/ingress.yaml"

echo ""
echo "Waiting for deployment to complete..."
kubectl rollout status deployment/cargo-tracker -n cargo-tracker --timeout=5m

if [ $? -ne 0 ]; then
    echo "WARNING: Deployment rollout did not complete within timeout"
    echo "Check deployment status with: kubectl get pods -n cargo-tracker"
fi

echo ""
echo "=========================================="
echo "Deployment Status"
echo "=========================================="
echo ""

# Display deployment status
kubectl get pods,svc,ingress -n cargo-tracker

echo ""
echo "=========================================="
echo "Application Access Information"
echo "=========================================="
echo ""

# Get ingress URL
INGRESS_URL=$(kubectl get ingress cargo-tracker-ingress -n cargo-tracker -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "Pending...")

if [ "$INGRESS_URL" != "Pending..." ]; then
    echo "Application URL: http://$INGRESS_URL/cargo-tracker/"
    echo ""
    echo "Note: It may take a few minutes for the Load Balancer to become available."
else
    echo "Ingress is being provisioned. Check status with:"
    echo "kubectl get ingress -n cargo-tracker"
fi

echo ""
echo "=========================================="
echo "Useful Commands"
echo "=========================================="
echo ""
echo "View logs:           kubectl logs -f deployment/cargo-tracker -n cargo-tracker"
echo "View pods:           kubectl get pods -n cargo-tracker"
echo "Describe pod:        kubectl describe pod <pod-name> -n cargo-tracker"
echo "Scale deployment:    kubectl scale deployment/cargo-tracker --replicas=3 -n cargo-tracker"
echo "Delete deployment:   kubectl delete namespace cargo-tracker"
echo ""

# Cleanup temporary directory
rm -rf "$TEMP_DIR"

echo "Deployment completed successfully!"
echo ""
