#!/bin/bash
set -e
set -o pipefail

# Deploy to AWS EKS Script for Cargo Tracker
# This script deploys the containerized application to AWS EKS

echo "=========================================="
echo "AWS EKS Deployment Script"
echo "=========================================="
echo ""

# Prompt for AWS configuration
read -p "Enter AWS Region (e.g., us-east-1): " AWS_REGION
read -p "Enter EKS Cluster Name: " CLUSTER_NAME

echo ""
echo "AWS Region: $AWS_REGION"
echo "EKS Cluster: $CLUSTER_NAME"
echo ""

# Prompt for Docker image URI
read -p "Enter Docker Image URI (e.g., 123456789012.dkr.ecr.us-east-1.amazonaws.com/cargo-tracker:latest): " IMAGE_URI

echo ""
echo "Docker Image: $IMAGE_URI"
echo ""

# Prompt for database configuration
echo "=== Database Configuration ==="
echo "Enter database connection details (or press Enter to use defaults)"
read -p "Database Driver Class (default: org.h2.jdbcx.JdbcDataSource): " DB_DRIVER_CLASS
DB_DRIVER_CLASS=${DB_DRIVER_CLASS:-org.h2.jdbcx.JdbcDataSource}

read -p "Database JDBC URL (default: jdbc:h2:file:/app/data/cargo-tracker-database): " DB_JDBC_URL
DB_JDBC_URL=${DB_JDBC_URL:-jdbc:h2:file:/app/data/cargo-tracker-database}

read -p "Database User (optional): " DB_USER
read -sp "Database Password (optional): " DB_PASSWORD
echo ""

echo ""
echo "Database Driver: $DB_DRIVER_CLASS"
echo "Database URL: $DB_JDBC_URL"
echo ""

# Configure kubectl for EKS
echo "=========================================="
echo "Configuring kubectl for EKS..."
echo "=========================================="
aws eks update-kubeconfig --region $AWS_REGION --name $CLUSTER_NAME

if [ $? -ne 0 ]; then
    echo "ERROR: Failed to configure kubectl for EKS cluster"
    exit 1
fi

echo "kubectl configured successfully"
echo ""

# Verify cluster connectivity
echo "Verifying cluster connectivity..."
kubectl cluster-info || {
    echo "ERROR: Cannot connect to EKS cluster"
    exit 1
}

echo ""
echo "Cluster connectivity verified"
echo ""

# Update Kubernetes manifests with actual values
echo "=========================================="
echo "Updating Kubernetes manifests..."
echo "=========================================="

# Create temporary directory for processed manifests
TEMP_DIR=$(mktemp -d)
cp -r kubernetes/* $TEMP_DIR/

# Replace placeholders in deployment.yaml
sed -i "s|{{IMAGE_URI}}|$IMAGE_URI|g" $TEMP_DIR/deployment.yaml
sed -i "s|{{DB_DRIVER_CLASS}}|$DB_DRIVER_CLASS|g" $TEMP_DIR/deployment.yaml
sed -i "s|{{DB_JDBC_URL}}|$DB_JDBC_URL|g" $TEMP_DIR/deployment.yaml
sed -i "s|{{DB_USER}}|$DB_USER|g" $TEMP_DIR/deployment.yaml
sed -i "s|{{DB_PASSWORD}}|$DB_PASSWORD|g" $TEMP_DIR/deployment.yaml

echo "Manifests updated successfully"
echo ""

# Apply Kubernetes manifests
echo "=========================================="
echo "Deploying to EKS..."
echo "=========================================="

# Create namespace
echo "Creating namespace..."
kubectl apply -f $TEMP_DIR/namespace.yaml

# Apply deployment
echo "Applying deployment..."
kubectl apply -f $TEMP_DIR/deployment.yaml

# Apply service
echo "Applying service..."
kubectl apply -f $TEMP_DIR/service.yaml

# Apply ingress
echo "Applying ingress..."
kubectl apply -f $TEMP_DIR/ingress.yaml

echo ""
echo "Kubernetes resources applied successfully"
echo ""

# Wait for deployment rollout
echo "=========================================="
echo "Waiting for deployment to complete..."
echo "=========================================="
kubectl rollout status deployment/cargo-tracker -n cargo-tracker --timeout=5m

if [ $? -ne 0 ]; then
    echo "WARNING: Deployment rollout did not complete within timeout"
    echo "Check deployment status with: kubectl get pods -n cargo-tracker"
else
    echo "Deployment completed successfully"
fi

echo ""

# Verify deployment
echo "=========================================="
echo "Verifying deployment..."
echo "=========================================="
kubectl get pods,svc,ingress -n cargo-tracker

echo ""

# Get ingress URL
echo "=========================================="
echo "Application Access Information"
echo "=========================================="
INGRESS_ADDRESS=$(kubectl get ingress cargo-tracker-ingress -n cargo-tracker -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "Pending...")

echo "Ingress Address: $INGRESS_ADDRESS"
echo ""
echo "Note: It may take a few minutes for the Load Balancer to be provisioned."
echo "Once ready, access the application at: http://$INGRESS_ADDRESS/cargo-tracker/"
echo ""

# Cleanup temporary directory
rm -rf $TEMP_DIR

echo "=========================================="
echo "Deployment Complete!"
echo "=========================================="
echo ""
echo "Useful commands:"
echo "  View pods:        kubectl get pods -n cargo-tracker"
echo "  View logs:        kubectl logs -f deployment/cargo-tracker -n cargo-tracker"
echo "  View services:    kubectl get svc -n cargo-tracker"
echo "  View ingress:     kubectl get ingress -n cargo-tracker"
echo "  Describe pod:     kubectl describe pod <pod-name> -n cargo-tracker"
echo ""
echo "To rollback deployment:"
echo "  kubectl rollout undo deployment/cargo-tracker -n cargo-tracker"
echo "=========================================="
