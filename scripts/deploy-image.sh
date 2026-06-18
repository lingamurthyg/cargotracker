#!/bin/bash

# Deploy Cargo Tracker to AWS EKS
# This script deploys the containerized application to Amazon EKS

set -e
set -o pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Cargo Tracker - EKS Deployment Script${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

# Check prerequisites
echo -e "${YELLOW}Checking prerequisites...${NC}"

if ! command -v aws &> /dev/null; then
    echo -e "${RED}AWS CLI is not installed. Please install it first.${NC}"
    exit 1
fi

if ! command -v kubectl &> /dev/null; then
    echo -e "${RED}kubectl is not installed. Please install it first.${NC}"
    exit 1
fi

echo -e "${GREEN}Prerequisites check passed!${NC}"
echo ""

# Prompt for AWS configuration
read -p "Enter AWS Region (e.g., us-east-1): " AWS_REGION
read -p "Enter EKS Cluster Name: " CLUSTER_NAME

if [ -z "$AWS_REGION" ] || [ -z "$CLUSTER_NAME" ]; then
    echo -e "${RED}AWS Region and Cluster Name are required.${NC}"
    exit 1
fi

# Prompt for Docker image URI
echo ""
echo -e "${YELLOW}Enter the full Docker image URI${NC}"
echo "Example: 123456789012.dkr.ecr.us-east-1.amazonaws.com/cargo-tracker:latest"
read -p "Docker Image URI: " IMAGE_URI

if [ -z "$IMAGE_URI" ]; then
    echo -e "${RED}Docker Image URI is required.${NC}"
    exit 1
fi

# Configure kubectl for EKS
echo ""
echo -e "${YELLOW}Configuring kubectl for EKS cluster...${NC}"
aws eks update-kubeconfig --region ${AWS_REGION} --name ${CLUSTER_NAME}

if [ $? -ne 0 ]; then
    echo -e "${RED}Failed to configure kubectl. Please check your AWS credentials and cluster name.${NC}"
    exit 1
fi

# Verify cluster connectivity
echo -e "${YELLOW}Verifying cluster connectivity...${NC}"
kubectl cluster-info || {
    echo -e "${RED}Failed to connect to cluster.${NC}"
    exit 1
}

echo -e "${GREEN}Successfully connected to EKS cluster!${NC}"
echo ""

# Update deployment manifest with image URI
echo -e "${YELLOW}Updating Kubernetes manifests with image URI...${NC}"
cd "$(dirname "$0")/.."

# Create temporary directory for processed manifests
TEMP_DIR=$(mktemp -d)
trap "rm -rf ${TEMP_DIR}" EXIT

# Copy manifests to temp directory and replace placeholders
cp -r kubernetes/* ${TEMP_DIR}/
sed -i "s|{{IMAGE_URI}}|${IMAGE_URI}|g" ${TEMP_DIR}/deployment.yaml

echo -e "${GREEN}Manifests updated successfully!${NC}"
echo ""

# Apply Kubernetes manifests
echo -e "${YELLOW}Deploying to Kubernetes...${NC}"
echo ""

echo -e "${YELLOW}1. Creating namespace...${NC}"
kubectl apply -f ${TEMP_DIR}/namespace.yaml

echo ""
echo -e "${YELLOW}2. Deploying application...${NC}"
kubectl apply -f ${TEMP_DIR}/deployment.yaml

echo ""
echo -e "${YELLOW}3. Creating service...${NC}"
kubectl apply -f ${TEMP_DIR}/service.yaml

echo ""
echo -e "${YELLOW}4. Creating ingress...${NC}"
kubectl apply -f ${TEMP_DIR}/ingress.yaml

echo ""
echo -e "${YELLOW}Waiting for deployment to complete...${NC}"
kubectl rollout status deployment/cargo-tracker -n cargo-tracker --timeout=5m

if [ $? -ne 0 ]; then
    echo -e "${RED}Deployment rollout failed or timed out.${NC}"
    echo -e "${YELLOW}Checking pod status...${NC}"
    kubectl get pods -n cargo-tracker
    exit 1
fi

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Deployment Successful!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

# Display deployment information
echo -e "${YELLOW}Deployment Information:${NC}"
echo ""
kubectl get pods -n cargo-tracker
echo ""
kubectl get svc -n cargo-tracker
echo ""
kubectl get ingress -n cargo-tracker

echo ""
echo -e "${YELLOW}Application Access:${NC}"
INGRESS_HOST=$(kubectl get ingress cargo-tracker-ingress -n cargo-tracker -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "pending")

if [ "$INGRESS_HOST" != "pending" ] && [ -n "$INGRESS_HOST" ]; then
    echo -e "Application URL: ${GREEN}http://${INGRESS_HOST}/cargo-tracker${NC}"
else
    echo -e "${YELLOW}Ingress is being provisioned. Run the following command to get the URL:${NC}"
    echo "kubectl get ingress cargo-tracker-ingress -n cargo-tracker"
fi

echo ""
echo -e "${YELLOW}Useful Commands:${NC}"
echo "View logs: kubectl logs -f deployment/cargo-tracker -n cargo-tracker"
echo "View pods: kubectl get pods -n cargo-tracker"
echo "Describe pod: kubectl describe pod <pod-name> -n cargo-tracker"
echo "Scale deployment: kubectl scale deployment/cargo-tracker --replicas=3 -n cargo-tracker"
echo "Delete deployment: kubectl delete namespace cargo-tracker"
echo ""
