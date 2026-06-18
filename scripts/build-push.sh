#!/bin/bash

# Build and Push Docker Image Script for Cargo Tracker
# Supports AWS ECR and Docker Hub registries

set -e
set -o pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "=========================================="
echo "  Cargo Tracker - Build & Push Script"
echo "=========================================="
echo ""

# Project name
PROJECT_NAME="cargo-tracker"

# Sanitize image name (lowercase, hyphenate spaces/specials, trim hyphens)
IMAGE_NAME=$(echo "$PROJECT_NAME" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' '-' | sed 's/^-*//;s/-*$//')

echo -e "${GREEN}Project:${NC} $PROJECT_NAME"
echo -e "${GREEN}Sanitized Image Name:${NC} $IMAGE_NAME"
echo ""

# Prompt for image tag
read -p "Enter image tag (default: latest): " IMAGE_TAG
IMAGE_TAG=${IMAGE_TAG:-latest}

# Sanitize tag
IMAGE_TAG=$(echo "$IMAGE_TAG" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9.-' '-' | sed 's/^-*//;s/-*$//')
echo -e "${GREEN}Image Tag:${NC} $IMAGE_TAG"
echo ""

# Select registry type
echo "Select Docker Registry:"
echo "1. AWS ECR (Elastic Container Registry)"
echo "2. Docker Hub"
read -p "Enter choice (1 or 2): " REGISTRY_CHOICE

if [ "$REGISTRY_CHOICE" == "1" ]; then
    echo ""
    echo -e "${YELLOW}=== AWS ECR Configuration ===${NC}"
    
    # AWS ECR Configuration
    read -p "Enter AWS Region (e.g., us-east-1): " AWS_REGION
    read -p "Enter AWS Account ID: " AWS_ACCOUNT_ID
    read -p "Enter ECR Repository Name (default: $IMAGE_NAME): " ECR_REPO
    ECR_REPO=${ECR_REPO:-$IMAGE_NAME}
    
    REGISTRY_URL="$AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com"
    FULL_IMAGE_NAME="$REGISTRY_URL/$ECR_REPO:$IMAGE_TAG"
    
    echo ""
    echo -e "${GREEN}Full Image Name:${NC} $FULL_IMAGE_NAME"
    echo ""
    
    # Login to AWS ECR
    echo -e "${YELLOW}Logging in to AWS ECR...${NC}"
    aws ecr get-login-password --region "$AWS_REGION" | docker login --username AWS --password-stdin "$REGISTRY_URL"
    
    if [ $? -ne 0 ]; then
        echo -e "${RED}ECR login failed. Please check your AWS credentials.${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}Successfully logged in to AWS ECR${NC}"
    
    # Check if ECR repository exists, create if not
    echo -e "${YELLOW}Checking ECR repository...${NC}"
    aws ecr describe-repositories --repository-names "$ECR_REPO" --region "$AWS_REGION" >/dev/null 2>&1 || {
        echo -e "${YELLOW}Repository does not exist. Creating ECR repository: $ECR_REPO${NC}"
        aws ecr create-repository --repository-name "$ECR_REPO" --region "$AWS_REGION"
        echo -e "${GREEN}ECR repository created successfully${NC}"
    }
    
elif [ "$REGISTRY_CHOICE" == "2" ]; then
    echo ""
    echo -e "${YELLOW}=== Docker Hub Configuration ===${NC}"
    
    # Docker Hub Configuration
    read -p "Enter Docker Hub Username: " DOCKER_USERNAME
    read -sp "Enter Docker Hub Password/Token: " DOCKER_PASSWORD
    echo ""
    read -p "Enter Docker Hub Repository (default: $IMAGE_NAME): " DOCKER_REPO
    DOCKER_REPO=${DOCKER_REPO:-$IMAGE_NAME}
    
    FULL_IMAGE_NAME="$DOCKER_USERNAME/$DOCKER_REPO:$IMAGE_TAG"
    
    echo ""
    echo -e "${GREEN}Full Image Name:${NC} $FULL_IMAGE_NAME"
    echo ""
    
    # Login to Docker Hub
    echo -e "${YELLOW}Logging in to Docker Hub...${NC}"
    echo "$DOCKER_PASSWORD" | docker login --username "$DOCKER_USERNAME" --password-stdin
    
    if [ $? -ne 0 ]; then
        echo -e "${RED}Docker Hub login failed. Please check your credentials.${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}Successfully logged in to Docker Hub${NC}"
    
else
    echo -e "${RED}Invalid choice. Exiting.${NC}"
    exit 1
fi

# Build Docker image
echo ""
echo -e "${YELLOW}Building Docker image...${NC}"
echo -e "${GREEN}Command:${NC} docker build -t $FULL_IMAGE_NAME ."
docker build -t "$FULL_IMAGE_NAME" .

if [ $? -ne 0 ]; then
    echo -e "${RED}Docker build failed. Please check the Dockerfile and build context.${NC}"
    exit 1
fi

echo -e "${GREEN}Docker image built successfully${NC}"

# Push Docker image
echo ""
echo -e "${YELLOW}Pushing Docker image to registry...${NC}"
docker push "$FULL_IMAGE_NAME"

if [ $? -ne 0 ]; then
    echo -e "${RED}Docker push failed. Please check your network and registry permissions.${NC}"
    exit 1
fi

echo ""
echo -e "${GREEN}=========================================="
echo -e "  Build and Push Completed Successfully!"
echo -e "==========================================${NC}"
echo ""
echo -e "${GREEN}Image:${NC} $FULL_IMAGE_NAME"
echo ""
echo "Next steps:"
echo "1. Use this image in your ECS task definition"
echo "2. Run the deploy-image.sh script to deploy to AWS ECS"
echo ""
