#!/bin/bash

# ============================================================================
# AWS EKS Deployment Script for Cargo Tracker
# Deploys containerized application to Amazon EKS
# ============================================================================

set -e
set -o pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "============================================================================"
echo "AWS EKS Deployment Script for Cargo Tracker"
echo "============================================================================"
echo ""

# Check prerequisites
echo -e "${YELLOW}Checking prerequisites...${NC}"

if ! command -v aws &> /dev/null; then
    echo -e "${RED}ERROR: AWS CLI is not installed${NC}"
    echo "Please install AWS CLI: https://aws.amazon.com/cli/"
    exit 1
fi

if ! command -v kubectl &> /dev/null; then
    echo -e "${RED}ERROR: kubectl is not installed${NC}"
    echo "Please install kubectl: https://kubernetes.io/docs/tasks/tools/"
    exit 1
fi

echo -e "${GREEN}Prerequisites check passed${NC}"
echo ""

# AWS Configuration
echo -e "${YELLOW}AWS EKS Configuration${NC}"
echo "================================"
read -r -p "Enter AWS Region (e.g., us-east-1): " AWS_REGION
read -r -p "Enter EKS Cluster Name: " CLUSTER_NAME

echo ""
echo -e "${GREEN}Configuring kubectl for EKS cluster...${NC}"
aws eks update-kubeconfig --region "$AWS_REGION" --name "$CLUSTER_NAME"

if [ $? -ne 0 ]; then
    echo -e "${RED}Failed to configure kubectl for EKS cluster${NC}"
    exit 1
fi

echo ""
echo -e "${GREEN}Verifying cluster connectivity...${NC}"
kubectl cluster-info

if [ $? -ne 0 ]; then
    echo -e "${RED}Failed to connect to EKS cluster${NC}"
    exit 1
fi

echo ""
echo -e "${YELLOW}Docker Image Configuration${NC}"
echo "================================"
read -r -p "Enter Docker Image URI (e.g., 123456789.dkr.ecr.us-east-1.amazonaws.com/cargo-tracker:latest): " IMAGE_URI

echo ""
echo -e "${YELLOW}Database Configuration${NC}"
echo "================================"
echo "Configure database connection (press Enter to use H2 embedded database)"
read -r -p "Enter DB_DRIVER_CLASS (default: org.h2.jdbcx.JdbcDataSource): " DB_DRIVER_CLASS
DB_DRIVER_CLASS=${DB_DRIVER_CLASS:-org.h2.jdbcx.JdbcDataSource}

read -r -p "Enter DB_JDBC_URL (default: jdbc:h2:file:/app/data/cargo-tracker-database): " DB_JDBC_URL
DB_JDBC_URL=${DB_JDBC_URL:-jdbc:h2:file:/app/data/cargo-tracker-database}

read -r -p "Enter DB_USER (optional): " DB_USER
read -r -p "Enter DB_PASSWORD (optional): " DB_PASSWORD

echo ""
echo -e "${GREEN}Updating Kubernetes manifests...${NC}"

# Update deployment.yaml with image URI and environment variables
sed -i.bak "s|{{IMAGE_URI}}|$IMAGE_URI|g" kubernetes/deployment.yaml
sed -i.bak "s|{{DB_DRIVER_CLASS}}|$DB_DRIVER_CLASS|g" kubernetes/deployment.yaml
sed -i.bak "s|{{DB_JDBC_URL}}|$DB_JDBC_URL|g" kubernetes/deployment.yaml
sed -i.bak "s|{{DB_USER}}|$DB_USER|g" kubernetes/deployment.yaml
sed -i.bak "s|{{DB_PASSWORD}}|$DB_PASSWORD|g" kubernetes/deployment.yaml

echo ""
echo -e "${GREEN}Deploying to AWS EKS...${NC}"
echo "================================"

# Apply namespace
echo -e "${YELLOW}Creating namespace...${NC}"
kubectl apply -f kubernetes/namespace.yaml

# Apply deployment
echo -e "${YELLOW}Deploying application...${NC}"
kubectl apply -f kubernetes/deployment.yaml

# Apply service
echo -e "${YELLOW}Creating service...${NC}"
kubectl apply -f kubernetes/service.yaml

# Apply ingress
echo -e "${YELLOW}Creating ingress...${NC}"
kubectl apply -f kubernetes/ingress.yaml

echo ""
echo -e "${GREEN}Waiting for deployment to complete...${NC}"
kubectl rollout status deployment/cargo-tracker -n cargo-tracker --timeout=5m

if [ $? -ne 0 ]; then
    echo -e "${RED}Deployment rollout failed or timed out${NC}"
    echo "Check pod status with: kubectl get pods -n cargo-tracker"
    echo "Check logs with: kubectl logs -n cargo-tracker -l app=cargo-tracker"
    exit 1
fi

echo ""
echo -e "${GREEN}Verifying deployment...${NC}"
echo "================================"
kubectl get pods,svc,ingress -n cargo-tracker

echo ""
echo -e "${GREEN}============================================================================${NC}"
echo -e "${GREEN}SUCCESS! Application deployed to AWS EKS${NC}"
echo -e "${GREEN}============================================================================${NC}"
echo ""
echo "Deployment Details:"
echo "  Namespace: cargo-tracker"
echo "  Cluster: $CLUSTER_NAME"
echo "  Region: $AWS_REGION"
echo "  Image: $IMAGE_URI"
echo ""
echo "Access your application:"
echo "  1. Get the Load Balancer URL:"
echo "     kubectl get ingress cargo-tracker-ingress -n cargo-tracker"
echo ""
echo "  2. Monitor pods:"
echo "     kubectl get pods -n cargo-tracker -w"
echo ""
echo "  3. View logs:"
echo "     kubectl logs -n cargo-tracker -l app=cargo-tracker -f"
echo ""
echo "  4. Port forward for local access:"
echo "     kubectl port-forward -n cargo-tracker svc/cargo-tracker-service 8080:80"
echo ""

# Restore original manifests
mv kubernetes/deployment.yaml.bak kubernetes/deployment.yaml 2>/dev/null || true

echo -e "${YELLOW}Note: Manifest backup files have been restored${NC}"
echo ""
