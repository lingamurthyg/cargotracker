#!/bin/bash

# ============================================================================
# Docker Build and Push Script for Cargo Tracker
# Supports AWS ECR and Docker Hub registries
# ============================================================================

set -e
set -o pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "============================================================================"
echo "Docker Build and Push Script for Cargo Tracker"
echo "============================================================================"
echo ""

# Project configuration
PROJECT_NAME="cargo-tracker"

# Sanitize project name for Docker tag (lowercase, hyphenate)
IMAGE_NAME=$(echo "$PROJECT_NAME" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' '-' | sed 's/^-*//;s/-*$//')

echo -e "${GREEN}Project: ${IMAGE_NAME}${NC}"
echo ""

# Prompt for image tag
echo "Enter Docker image tag (default: latest):"
read -r IMAGE_TAG
IMAGE_TAG=${IMAGE_TAG:-latest}

# Sanitize tag
IMAGE_TAG=$(echo "$IMAGE_TAG" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9.-' '-' | sed 's/^-*//;s/-*$//')
IMAGE_TAG=${IMAGE_TAG:-latest}

echo -e "${GREEN}Using tag: ${IMAGE_TAG}${NC}"
echo ""

# Registry selection
echo "Select Docker Registry:"
echo "1. AWS ECR (Elastic Container Registry)"
echo "2. Docker Hub"
read -r -p "Enter choice (1 or 2): " REGISTRY_CHOICE

if [ "$REGISTRY_CHOICE" = "1" ]; then
    # AWS ECR Configuration
    echo ""
    echo -e "${YELLOW}AWS ECR Configuration${NC}"
    echo "================================"
    
    read -r -p "Enter AWS Region (e.g., us-east-1): " AWS_REGION
    read -r -p "Enter AWS Account ID: " AWS_ACCOUNT_ID
    read -r -p "Enter ECR Repository Name (default: ${IMAGE_NAME}): " ECR_REPO
    ECR_REPO=${ECR_REPO:-$IMAGE_NAME}
    
    REGISTRY_URL="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
    FULL_IMAGE_NAME="${REGISTRY_URL}/${ECR_REPO}:${IMAGE_TAG}"
    
    echo ""
    echo -e "${GREEN}Authenticating with AWS ECR...${NC}"
    aws ecr get-login-password --region "$AWS_REGION" | docker login --username AWS --password-stdin "$REGISTRY_URL"
    
    if [ $? -ne 0 ]; then
        echo -e "${RED}ECR authentication failed!${NC}"
        exit 1
    fi
    
    # Check if repository exists, create if not
    echo -e "${GREEN}Checking ECR repository...${NC}"
    aws ecr describe-repositories --repository-names "$ECR_REPO" --region "$AWS_REGION" >/dev/null 2>&1 || {
        echo -e "${YELLOW}Repository does not exist. Creating...${NC}"
        aws ecr create-repository --repository-name "$ECR_REPO" --region "$AWS_REGION"
    }
    
elif [ "$REGISTRY_CHOICE" = "2" ]; then
    # Docker Hub Configuration
    echo ""
    echo -e "${YELLOW}Docker Hub Configuration${NC}"
    echo "================================"
    
    read -r -p "Enter Docker Hub Username: " DOCKER_USERNAME
    read -r -s -p "Enter Docker Hub Password: " DOCKER_PASSWORD
    echo ""
    
    FULL_IMAGE_NAME="${DOCKER_USERNAME}/${IMAGE_NAME}:${IMAGE_TAG}"
    
    echo ""
    echo -e "${GREEN}Authenticating with Docker Hub...${NC}"
    echo "$DOCKER_PASSWORD" | docker login --username "$DOCKER_USERNAME" --password-stdin
    
    if [ $? -ne 0 ]; then
        echo -e "${RED}Docker Hub authentication failed!${NC}"
        exit 1
    fi
else
    echo -e "${RED}Invalid choice. Exiting.${NC}"
    exit 1
fi

echo ""
echo -e "${GREEN}Building Docker image: ${FULL_IMAGE_NAME}${NC}"
echo "================================"

# Build Docker image
docker build -t "$FULL_IMAGE_NAME" .

if [ $? -ne 0 ]; then
    echo -e "${RED}Docker build failed!${NC}"
    exit 1
fi

echo ""
echo -e "${GREEN}Build successful!${NC}"
echo ""
echo -e "${GREEN}Pushing image to registry...${NC}"
echo "================================"

# Push Docker image
docker push "$FULL_IMAGE_NAME"

if [ $? -ne 0 ]; then
    echo -e "${RED}Docker push failed!${NC}"
    exit 1
fi

echo ""
echo -e "${GREEN}============================================================================${NC}"
echo -e "${GREEN}SUCCESS! Image pushed successfully${NC}"
echo -e "${GREEN}============================================================================${NC}"
echo ""
echo "Image: ${FULL_IMAGE_NAME}"
echo ""
echo "Next steps:"
echo "1. Update kubernetes/deployment.yaml with the image URI"
echo "2. Run deploy-image.sh to deploy to AWS EKS"
echo ""
