#!/bin/bash

# Deploy Cargo Tracker to AWS ECS Fargate
# This script deploys the containerized application to AWS ECS

set -e
set -o pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo "=========================================="
echo "  Cargo Tracker - ECS Fargate Deployment"
echo "=========================================="
echo ""

# Check if AWS CLI is installed
if ! command -v aws &> /dev/null; then
    echo -e "${RED}AWS CLI is not installed. Please install it first.${NC}"
    exit 1
fi

# Prompt for AWS configuration
echo -e "${BLUE}=== AWS Configuration ===${NC}"
read -p "Enter AWS Region (e.g., us-east-1): " AWS_REGION
read -p "Enter ECS Cluster Name: " CLUSTER_NAME
echo ""

# Get AWS Account ID
echo -e "${YELLOW}Retrieving AWS Account ID...${NC}"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
if [ $? -ne 0 ]; then
    echo -e "${RED}Failed to retrieve AWS Account ID. Please check your AWS credentials.${NC}"
    exit 1
fi
echo -e "${GREEN}AWS Account ID: $ACCOUNT_ID${NC}"
echo ""

# Check/Create ECS Cluster
echo -e "${YELLOW}Checking ECS cluster...${NC}"
aws ecs describe-clusters --clusters "$CLUSTER_NAME" --region "$AWS_REGION" >/dev/null 2>&1 || {
    echo -e "${YELLOW}Cluster does not exist. Creating ECS cluster: $CLUSTER_NAME${NC}"
    aws ecs create-cluster --cluster-name "$CLUSTER_NAME" --region "$AWS_REGION"
    echo -e "${GREEN}ECS cluster created successfully${NC}"
}
echo ""

# Prompt for network configuration
echo -e "${BLUE}=== Network Configuration ===${NC}"
read -p "Enter VPC ID: " VPC_ID
read -p "Enter Subnet IDs (comma-separated, at least 2): " SUBNETS_INPUT
read -p "Enter Security Group ID: " SECURITY_GROUP
echo ""

# Parse subnets
IFS=',' read -ra SUBNETS <<< "$SUBNETS_INPUT"
SUBNET_1="${SUBNETS[0]}"
SUBNET_2="${SUBNETS[1]:-$SUBNET_1}"

# Trim whitespace
SUBNET_1=$(echo "$SUBNET_1" | xargs)
SUBNET_2=$(echo "$SUBNET_2" | xargs)

echo -e "${GREEN}VPC ID: $VPC_ID${NC}"
echo -e "${GREEN}Subnet 1: $SUBNET_1${NC}"
echo -e "${GREEN}Subnet 2: $SUBNET_2${NC}"
echo -e "${GREEN}Security Group: $SECURITY_GROUP${NC}"
echo ""

# Prompt for Docker image URI
echo -e "${BLUE}=== Docker Image Configuration ===${NC}"
read -p "Enter Docker Image URI (e.g., 123456789.dkr.ecr.us-east-1.amazonaws.com/cargo-tracker:latest): " IMAGE_URI
echo ""

# Load Balancer Configuration
echo -e "${BLUE}=== Load Balancer Configuration ===${NC}"
read -p "Do you need a load balancer for this service? (y/n): " NEED_LB

if [[ "$NEED_LB" =~ ^[Yy]$ ]]; then
    echo -e "${YELLOW}Creating Application Load Balancer and Target Group...${NC}"
    
    # Create ALB
    ALB_NAME="cargo-tracker-alb"
    echo -e "${YELLOW}Creating ALB: $ALB_NAME${NC}"
    ALB_ARN=$(aws elbv2 create-load-balancer \
        --name "$ALB_NAME" \
        --subnets "$SUBNET_1" "$SUBNET_2" \
        --security-groups "$SECURITY_GROUP" \
        --scheme internet-facing \
        --type application \
        --ip-address-type ipv4 \
        --region "$AWS_REGION" \
        --query 'LoadBalancers[0].LoadBalancerArn' \
        --output text 2>/dev/null || echo "")
    
    if [ -z "$ALB_ARN" ]; then
        echo -e "${YELLOW}ALB may already exist, retrieving existing ALB...${NC}"
        ALB_ARN=$(aws elbv2 describe-load-balancers \
            --names "$ALB_NAME" \
            --region "$AWS_REGION" \
            --query 'LoadBalancers[0].LoadBalancerArn' \
            --output text 2>/dev/null || echo "")
    fi
    
    if [ -z "$ALB_ARN" ]; then
        echo -e "${RED}Failed to create or retrieve ALB${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}ALB ARN: $ALB_ARN${NC}"
    
    # Get ALB DNS Name
    ALB_DNS=$(aws elbv2 describe-load-balancers \
        --load-balancer-arns "$ALB_ARN" \
        --region "$AWS_REGION" \
        --query 'LoadBalancers[0].DNSName' \
        --output text)
    
    # Create Target Group
    TG_NAME="cargo-tracker-tg"
    echo -e "${YELLOW}Creating Target Group: $TG_NAME${NC}"
    TARGET_GROUP_ARN=$(aws elbv2 create-target-group \
        --name "$TG_NAME" \
        --protocol HTTP \
        --port 8080 \
        --vpc-id "$VPC_ID" \
        --target-type ip \
        --health-check-enabled \
        --health-check-protocol HTTP \
        --health-check-path "/" \
        --health-check-interval-seconds 30 \
        --health-check-timeout-seconds 5 \
        --healthy-threshold-count 2 \
        --unhealthy-threshold-count 3 \
        --region "$AWS_REGION" \
        --query 'TargetGroups[0].TargetGroupArn' \
        --output text 2>/dev/null || echo "")
    
    if [ -z "$TARGET_GROUP_ARN" ]; then
        echo -e "${YELLOW}Target Group may already exist, retrieving existing TG...${NC}"
        TARGET_GROUP_ARN=$(aws elbv2 describe-target-groups \
            --names "$TG_NAME" \
            --region "$AWS_REGION" \
            --query 'TargetGroups[0].TargetGroupArn' \
            --output text 2>/dev/null || echo "")
    fi
    
    if [ -z "$TARGET_GROUP_ARN" ]; then
        echo -e "${RED}Failed to create or retrieve Target Group${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}Target Group ARN: $TARGET_GROUP_ARN${NC}"
    
    # Create Listener
    echo -e "${YELLOW}Creating ALB Listener...${NC}"
    aws elbv2 create-listener \
        --load-balancer-arn "$ALB_ARN" \
        --protocol HTTP \
        --port 80 \
        --default-actions Type=forward,TargetGroupArn="$TARGET_GROUP_ARN" \
        --region "$AWS_REGION" >/dev/null 2>&1 || echo -e "${YELLOW}Listener may already exist${NC}"
    
    echo -e "${GREEN}Load Balancer setup completed${NC}"
    echo ""
else
    echo -e "${YELLOW}Skipping load balancer creation${NC}"
    TARGET_GROUP_ARN=""
    
    # Remove loadBalancers section from service definition
    sed -i.bak '/"loadBalancers":/,/],/d' ecs/service-definition.json
    sed -i.bak '/"healthCheckGracePeriodSeconds":/d' ecs/service-definition.json
    echo ""
fi

# Create CloudWatch Log Group
echo -e "${YELLOW}Creating CloudWatch Log Group...${NC}"
aws logs create-log-group --log-group-name "/ecs/cargo-tracker" --region "$AWS_REGION" 2>/dev/null || echo -e "${YELLOW}Log group already exists${NC}"
echo ""

# Replace placeholders in task definition
echo -e "${YELLOW}Preparing task definition...${NC}"
sed "s|{{IMAGE_URI}}|$IMAGE_URI|g; s|{{AWS_REGION}}|$AWS_REGION|g; s|{{ACCOUNT_ID}}|$ACCOUNT_ID|g" \
    ecs/task-definition.json > ecs/task-definition-resolved.json

# Register task definition
echo -e "${YELLOW}Registering ECS task definition...${NC}"
TASK_DEF_ARN=$(aws ecs register-task-definition \
    --cli-input-json file://ecs/task-definition-resolved.json \
    --region "$AWS_REGION" \
    --query 'taskDefinition.taskDefinitionArn' \
    --output text)

if [ $? -ne 0 ]; then
    echo -e "${RED}Failed to register task definition${NC}"
    exit 1
fi

echo -e "${GREEN}Task definition registered: $TASK_DEF_ARN${NC}"
echo ""

# Replace placeholders in service definition
echo -e "${YELLOW}Preparing service definition...${NC}"
if [ -n "$TARGET_GROUP_ARN" ]; then
    sed "s|{{CLUSTER_NAME}}|$CLUSTER_NAME|g; s|{{SUBNET_1}}|$SUBNET_1|g; s|{{SUBNET_2}}|$SUBNET_2|g; s|{{SECURITY_GROUP}}|$SECURITY_GROUP|g; s|{{TARGET_GROUP_ARN}}|$TARGET_GROUP_ARN|g" \
        ecs/service-definition.json > ecs/service-definition-resolved.json
else
    sed "s|{{CLUSTER_NAME}}|$CLUSTER_NAME|g; s|{{SUBNET_1}}|$SUBNET_1|g; s|{{SUBNET_2}}|$SUBNET_2|g; s|{{SECURITY_GROUP}}|$SECURITY_GROUP|g" \
        ecs/service-definition.json > ecs/service-definition-resolved.json
fi

# Check if service exists
echo -e "${YELLOW}Checking if service exists...${NC}"
SERVICE_EXISTS=$(aws ecs describe-services \
    --cluster "$CLUSTER_NAME" \
    --services "cargo-tracker-service" \
    --region "$AWS_REGION" \
    --query 'services[0].serviceName' \
    --output text 2>/dev/null)

if [ "$SERVICE_EXISTS" == "cargo-tracker-service" ]; then
    echo -e "${YELLOW}Service exists. Updating service...${NC}"
    aws ecs update-service \
        --cluster "$CLUSTER_NAME" \
        --service "cargo-tracker-service" \
        --task-definition "$TASK_DEF_ARN" \
        --desired-count 2 \
        --region "$AWS_REGION" \
        --force-new-deployment
    
    if [ $? -ne 0 ]; then
        echo -e "${RED}Failed to update service${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}Service updated successfully${NC}"
else
    echo -e "${YELLOW}Service does not exist. Creating service...${NC}"
    aws ecs create-service \
        --cli-input-json file://ecs/service-definition-resolved.json \
        --region "$AWS_REGION"
    
    if [ $? -ne 0 ]; then
        echo -e "${RED}Failed to create service${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}Service created successfully${NC}"
fi

echo ""
echo -e "${YELLOW}Waiting for service to become stable...${NC}"
aws ecs wait services-stable \
    --cluster "$CLUSTER_NAME" \
    --services "cargo-tracker-service" \
    --region "$AWS_REGION"

echo ""
echo -e "${GREEN}=========================================="
echo -e "  Deployment Completed Successfully!"
echo -e "==========================================${NC}"
echo ""
echo -e "${GREEN}Cluster:${NC} $CLUSTER_NAME"
echo -e "${GREEN}Service:${NC} cargo-tracker-service"
echo -e "${GREEN}Task Definition:${NC} $TASK_DEF_ARN"
echo -e "${GREEN}CloudWatch Logs:${NC} /ecs/cargo-tracker"
echo ""

if [ -n "$ALB_DNS" ]; then
    echo -e "${GREEN}Application URL:${NC} http://$ALB_DNS"
    echo ""
fi

echo "To view service details:"
echo "  aws ecs describe-services --cluster $CLUSTER_NAME --services cargo-tracker-service --region $AWS_REGION"
echo ""
echo "To view logs:"
echo "  aws logs tail /ecs/cargo-tracker --follow --region $AWS_REGION"
echo ""
