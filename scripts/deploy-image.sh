#!/bin/bash
set -e
set -o pipefail

echo "========================================"
echo "AWS EKS Deployment Script"
echo "Cargo Tracker Application"
echo "========================================"
echo ""

# Prompt for AWS configuration
read -p "Enter AWS Region (e.g., us-east-1): " AWS_REGION
if [ -z "$AWS_REGION" ]; then
    echo "ERROR: AWS Region is required"
    exit 1
fi

read -p "Enter EKS Cluster Name: " CLUSTER_NAME
if [ -z "$CLUSTER_NAME" ]; then
    echo "ERROR: EKS Cluster Name is required"
    exit 1
fi

read -p "Enter Docker Image URI (e.g., 123456789.dkr.ecr.us-east-1.amazonaws.com/cargo-tracker:latest): " IMAGE_URI
if [ -z "$IMAGE_URI" ]; then
    echo "ERROR: Docker Image URI is required"
    exit 1
fi

echo ""
echo "=== Optional: Database Configuration ==="
read -p "Enter Database JDBC URL (or press Enter to use default H2): " DB_JDBC_URL
DB_JDBC_URL=${DB_JDBC_URL:-jdbc:h2:file:/opt/payara/cargo-tracker-data/cargo-tracker-database}

echo ""
echo "Configuration Summary:"
echo "  AWS Region: $AWS_REGION"
echo "  EKS Cluster: $CLUSTER_NAME"
echo "  Image URI: $IMAGE_URI"
echo "  Database URL: $DB_JDBC_URL"
echo ""
read -p "Continue with deployment? (y/n): " CONFIRM
if [ "$CONFIRM" != "y" ] && [ "$CONFIRM" != "Y" ]; then
    echo "Deployment cancelled"
    exit 0
fi

echo ""
echo "========================================"
echo "Step 1: Configure kubectl for EKS"
echo "========================================"
echo ""

aws eks update-kubeconfig --region $AWS_REGION --name $CLUSTER_NAME

if [ $? -ne 0 ]; then
    echo "ERROR: Failed to configure kubectl"
    exit 1
fi

echo "Verifying cluster connectivity..."
kubectl cluster-info || {
    echo "ERROR: Cannot connect to cluster"
    exit 1
}

echo ""
echo "========================================"
echo "Step 2: Update Kubernetes Manifests"
echo "========================================"
echo ""

# Create temporary directory for processed manifests
TMP_DIR=$(mktemp -d)
trap "rm -rf $TMP_DIR" EXIT

# Copy manifests to temp directory
cp -r kubernetes/* $TMP_DIR/

# Replace placeholders using pipe delimiter
sed -i 's|{{IMAGE_URI}}|'"$IMAGE_URI"'|g' $TMP_DIR/deployment.yaml
sed -i 's|{{DB_JDBC_URL}}|'"$DB_JDBC_URL"'|g' $TMP_DIR/deployment.yaml

echo "Manifests updated successfully"

echo ""
echo "========================================"
echo "Step 3: Apply Kubernetes Manifests"
echo "========================================"
echo ""

echo "Creating namespace..."
kubectl apply -f $TMP_DIR/namespace.yaml

echo ""
echo "Deploying application..."
kubectl apply -f $TMP_DIR/deployment.yaml

echo ""
echo "Creating service..."
kubectl apply -f $TMP_DIR/service.yaml

echo ""
echo "Creating ingress..."
kubectl apply -f $TMP_DIR/ingress.yaml

echo ""
echo "========================================"
echo "Step 4: Wait for Deployment Rollout"
echo "========================================"
echo ""

kubectl rollout status deployment/cargo-tracker -n cargo-tracker --timeout=5m

if [ $? -ne 0 ]; then
    echo "WARNING: Deployment rollout did not complete successfully"
    echo "Check pod status with: kubectl get pods -n cargo-tracker"
fi

echo ""
echo "========================================"
echo "Step 5: Verify Deployment"
echo "========================================"
echo ""

echo "Pods:"
kubectl get pods -n cargo-tracker -o wide

echo ""
echo "Services:"
kubectl get svc -n cargo-tracker

echo ""
echo "Ingress:"
kubectl get ingress -n cargo-tracker

echo ""
echo "========================================"
echo "Deployment Complete!"
echo "========================================"
echo ""

# Get ingress URL
INGRESS_URL=$(kubectl get ingress cargo-tracker-ingress -n cargo-tracker -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "pending")

if [ "$INGRESS_URL" != "pending" ] && [ -n "$INGRESS_URL" ]; then
    echo "Application URL: http://$INGRESS_URL/cargo-tracker/"
else
    echo "Ingress is being provisioned. Check status with:"
    echo "  kubectl get ingress -n cargo-tracker -w"
fi

echo ""
echo "Useful commands:"
echo "  View logs: kubectl logs -f deployment/cargo-tracker -n cargo-tracker"
echo "  Get pods: kubectl get pods -n cargo-tracker"
echo "  Describe pod: kubectl describe pod <pod-name> -n cargo-tracker"
echo "  Port forward: kubectl port-forward svc/cargo-tracker-service 8080:80 -n cargo-tracker"
echo ""