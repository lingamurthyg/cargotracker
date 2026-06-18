#!/bin/bash

# Build and Push Docker Image Script for Cargo Tracker
# This script builds the Docker image and pushes it to a container registry

set -e
set -o pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Cargo Tracker - Build and Push Script${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

# Project name
PROJECT_NAME="cargo-tracker"

# Sanitize image name (lowercase, replace special chars with hyphens)
IMAGE_NAME=$(echo "$PROJECT_NAME" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' '-' | sed 's/^-*//;s/-*$//')

echo -e "${YELLOW}Select Container Registry:${NC}"
echo "1. AWS ECR (Elastic Container Registry)"
echo "2. Docker Hub"
read -p "Enter your choice (1 or 2): " REGISTRY_CHOICE

if [ "$REGISTRY_CHOICE" == "1" ]; then
    echo -e "${GREEN}Selected: AWS ECR${NC}"
    
    # AWS ECR Configuration
    read -p "Enter AWS Region (e.g., us-east-1): " AWS_REGION
    read -p "Enter AWS Account ID: " AWS_ACCOUNT_ID
    read -p "Enter ECR Repository Name (default: ${IMAGE_NAME}): " ECR_REPO
    ECR_REPO=${ECR_REPO:-$IMAGE_NAME}
    
    # Construct ECR registry URL
    REGISTRY_URL="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
    FULL_IMAGE_NAME="${REGISTRY_URL}/${ECR_REPO}"
    
    echo -e "${YELLOW}Authenticating with AWS ECR...${NC}"
    aws ecr get-login-password --region ${AWS_REGION} | docker login --username AWS --password-stdin ${REGISTRY_URL}
    
    if [ $? -ne 0 ]; then
        echo -e "${RED}ECR authentication failed. Please check your AWS credentials.${NC}"
        exit 1
    fi
    
    # Check if ECR repository exists, create if it doesn't
    echo -e "${YELLOW}Checking if ECR repository exists...${NC}"
    aws ecr describe-repositories --repository-names ${ECR_REPO} --region ${AWS_REGION} >/dev/null 2>&1 || {
        echo -e "${YELLOW}Creating ECR repository: ${ECR_REPO}${NC}"
        aws ecr create-repository --repository-name ${ECR_REPO} --region ${AWS_REGION}
    }
    
elif [ "$REGISTRY_CHOICE" == "2" ]; then
    echo -e "${GREEN}Selected: Docker Hub${NC}"
    
    # Docker Hub Configuration
    read -p "Enter Docker Hub Username: " DOCKER_USERNAME
    read -sp "Enter Docker Hub Password/Token: " DOCKER_PASSWORD
    echo ""
    
    FULL_IMAGE_NAME="${DOCKER_USERNAME}/${IMAGE_NAME}"
    
    echo -e "${YELLOW}Authenticating with Docker Hub...${NC}"
    echo ${DOCKER_PASSWORD} | docker login --username ${DOCKER_USERNAME} --password-stdin
    
    if [ $? -ne 0 ]; then
        echo -e "${RED}Docker Hub authentication failed.${NC}"
        exit 1
    fi
    
else
    echo -e "${RED}Invalid choice. Exiting.${NC}"
    exit 1
fi

# Prompt for image tag
read -p "Enter image tag (default: latest): " IMAGE_TAG
IMAGE_TAG=${IMAGE_TAG:-latest}

# Sanitize tag
IMAGE_TAG=$(echo "$IMAGE_TAG" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9.-' '-' | sed 's/^-*//;s/-*$//')
[ -z "$IMAGE_TAG" ] && IMAGE_TAG="latest"

FULL_IMAGE_NAME="${FULL_IMAGE_NAME}:${IMAGE_TAG}"

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Build Configuration${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "Image Name: ${YELLOW}${FULL_IMAGE_NAME}${NC}"
echo -e "Build Context: ${YELLOW}$(pwd)${NC}"
echo ""

# Build Docker image
echo -e "${YELLOW}Building Docker image...${NC}"
docker build -t ${FULL_IMAGE_NAME} .

if [ $? -ne 0 ]; then
    echo -e "${RED}Docker build failed.${NC}"
    exit 1
fi

echo -e "${GREEN}Docker image built successfully!${NC}"
echo ""

# Push Docker image
echo -e "${YELLOW}Pushing Docker image to registry...${NC}"
docker push ${FULL_IMAGE_NAME}

if [ $? -ne 0 ]; then
    echo -e "${RED}Docker push failed.${NC}"
    exit 1
fi

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Success!${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "Image pushed successfully: ${YELLOW}${FULL_IMAGE_NAME}${NC}"
echo ""
echo -e "${YELLOW}Next Steps:${NC}"
echo "1. Update your Kubernetes deployment manifests with this image"
echo "2. Run the deployment script: ./scripts/deploy-image.sh"
echo ""
