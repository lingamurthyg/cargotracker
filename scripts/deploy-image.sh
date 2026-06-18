#!/bin/bash
set -e
set -o pipefail

# Deploy Docker Image to AWS ECS Fargate
# This script deploys the Cargo Tracker application to AWS ECS

echo "=========================================="
echo "AWS ECS Fargate Deployment Script"
echo "=========================================="
echo ""

# Configuration
SERVICE_NAME="cargo-tracker-service"
TASK_FAMILY="cargo-tracker-task"
CONTAINER_NAME="cargo-tracker"

# Prompt for AWS configuration
echo "=== AWS Configuration ==="
read -p "Enter AWS Region (e.g., us-east-1): " AWS_REGION
read -p "Enter ECS Cluster Name: " CLUSTER_NAME
read -p "Enter Docker Image URI: " IMAGE_URI

echo ""
echo "=== Network Configuration ==="
read -p "Enter VPC ID: " VPC_ID
read -p "Enter Subnet IDs (comma-separated, at least 2): " SUBNETS_INPUT
read -p "Enter Security Group ID: " SECURITY_GROUP

# Convert comma-separated subnets to array
IFS=',' read -ra SUBNETS <<< "$SUBNETS_INPUT"
SUBNET_1="${SUBNETS[0]}"
SUBNET_2="${SUBNETS[1]}"

# Trim whitespace
SUBNET_1=$(echo "$SUBNET_1" | xargs)
SUBNET_2=$(echo "$SUBNET_2" | xargs)

echo ""
echo "=== Load Balancer Configuration ==="
read -p "Do you need a load balancer for this service? (y/n): " NEED_LB

TARGET_GROUP_ARN=""
if [ "$NEED_LB" = "y" ] || [ "$NEED_LB" = "Y" ]; then
    echo "Creating Application Load Balancer and Target Group..."
    
    # Create Target Group
    TG_NAME="cargo-tracker-tg-$(date +%s)"
    TARGET_GROUP_ARN=$(aws elbv2 create-target-group \
        --name "$TG_NAME" \
        --protocol HTTP \
        --port 8080 \
        --vpc-id "$VPC_ID" \
        --target-type ip \
        --health-check-enabled \
        --health-check-path "/cargo-tracker/" \
        --health-check-interval-seconds 30 \
        --health-check-timeout-seconds 5 \
        --healthy-threshold-count 2 \
        --unhealthy-threshold-count 3 \
        --region "$AWS_REGION" \
        --query 'TargetGroups[0].TargetGroupArn' \
        --output text)
    
    echo "Target Group created: $TARGET_GROUP_ARN"
    
    # Create Application Load Balancer
    ALB_NAME="cargo-tracker-alb-$(date +%s)"
    ALB_ARN=$(aws elbv2 create-load-balancer \
        --name "$ALB_NAME" \
        --subnets "$SUBNET_1" "$SUBNET_2" \
        --security-groups "$SECURITY_GROUP" \
        --scheme internet-facing \
        --type application \
        --ip-address-type ipv4 \
        --region "$AWS_REGION" \
        --query 'LoadBalancers[0].LoadBalancerArn' \
        --output text)
    
    echo "Application Load Balancer created: $ALB_ARN"
    
    # Create Listener
    LISTENER_ARN=$(aws elbv2 create-listener \
        --load-balancer-arn "$ALB_ARN" \
        --protocol HTTP \
        --port 80 \
        --default-actions Type=forward,TargetGroupArn="$TARGET_GROUP_ARN" \
        --region "$AWS_REGION" \
        --query 'Listeners[0].ListenerArn' \
        --output text)
    
    echo "Listener created: $LISTENER_ARN"
    
    # Get ALB DNS name
    ALB_DNS=$(aws elbv2 describe-load-balancers \
        --load-balancer-arns "$ALB_ARN" \
        --region "$AWS_REGION" \
        --query 'LoadBalancers[0].DNSName' \
        --output text)
    
    echo "Load Balancer DNS: $ALB_DNS"
fi

echo ""
echo "=== Getting AWS Account ID ==="
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
echo "Account ID: $ACCOUNT_ID"

echo ""
echo "=== Checking ECS Cluster ==="
aws ecs describe-clusters --clusters "$CLUSTER_NAME" --region "$AWS_REGION" >/dev/null 2>&1 || {
    echo "Cluster does not exist. Creating cluster: $CLUSTER_NAME"
    aws ecs create-cluster --cluster-name "$CLUSTER_NAME" --region "$AWS_REGION"
}

echo ""
echo "=== Creating CloudWatch Log Group ==="
aws logs create-log-group --log-group-name "/ecs/cargo-tracker" --region "$AWS_REGION" 2>/dev/null || echo "Log group already exists"

echo ""
echo "=== Preparing Task Definition ==="
# Create temporary task definition with replaced values
TEMP_TASK_DEF=$(mktemp)
sed "s|{{IMAGE_URI}}|$IMAGE_URI|g; s|{{AWS_REGION}}|$AWS_REGION|g; s|{{ACCOUNT_ID}}|$ACCOUNT_ID|g" \
    ecs/task-definition.json > "$TEMP_TASK_DEF"

echo "Registering task definition..."
TASK_DEF_ARN=$(aws ecs register-task-definition \
    --cli-input-json file://"$TEMP_TASK_DEF" \
    --region "$AWS_REGION" \
    --query 'taskDefinition.taskDefinitionArn' \
    --output text)

echo "Task Definition registered: $TASK_DEF_ARN"
rm "$TEMP_TASK_DEF"

echo ""
echo "=== Preparing Service Definition ==="
# Create temporary service definition with replaced values
TEMP_SERVICE_DEF=$(mktemp)

if [ -n "$TARGET_GROUP_ARN" ]; then
    # Include load balancer configuration
    sed "s|{{CLUSTER_NAME}}|$CLUSTER_NAME|g; \
         s|{{SUBNET_1}}|$SUBNET_1|g; \
         s|{{SUBNET_2}}|$SUBNET_2|g; \
         s|{{SECURITY_GROUP}}|$SECURITY_GROUP|g; \
         s|{{TARGET_GROUP_ARN}}|$TARGET_GROUP_ARN|g" \
        ecs/service-definition.json > "$TEMP_SERVICE_DEF"
else
    # Remove load balancer configuration
    sed "s|{{CLUSTER_NAME}}|$CLUSTER_NAME|g; \
         s|{{SUBNET_1}}|$SUBNET_1|g; \
         s|{{SUBNET_2}}|$SUBNET_2|g; \
         s|{{SECURITY_GROUP}}|$SECURITY_GROUP|g" \
        ecs/service-definition.json | \
        jq 'del(.loadBalancers, .healthCheckGracePeriodSeconds)' > "$TEMP_SERVICE_DEF"
fi

echo ""
echo "=== Checking if Service Exists ==="
EXISTING_SERVICE=$(aws ecs describe-services \
    --cluster "$CLUSTER_NAME" \
    --services "$SERVICE_NAME" \
    --region "$AWS_REGION" \
    --query 'services[?status==`ACTIVE`].serviceName' \
    --output text 2>/dev/null || echo "")

if [ -z "$EXISTING_SERVICE" ] || [ "$EXISTING_SERVICE" = "None" ]; then
    echo "Service does not exist. Creating new service..."
    aws ecs create-service \
        --cli-input-json file://"$TEMP_SERVICE_DEF" \
        --region "$AWS_REGION"
else
    echo "Service exists. Updating service..."
    aws ecs update-service \
        --cluster "$CLUSTER_NAME" \
        --service "$SERVICE_NAME" \
        --task-definition "$TASK_DEF_ARN" \
        --force-new-deployment \
        --region "$AWS_REGION"
fi

rm "$TEMP_SERVICE_DEF"

echo ""
echo "=== Waiting for Service Stability ==="
echo "This may take several minutes..."
aws ecs wait services-stable \
    --cluster "$CLUSTER_NAME" \
    --services "$SERVICE_NAME" \
    --region "$AWS_REGION"

echo ""
echo "=========================================="
echo "Deployment Completed Successfully!"
echo "=========================================="
echo ""
echo "Service Details:"
aws ecs describe-services \
    --cluster "$CLUSTER_NAME" \
    --services "$SERVICE_NAME" \
    --region "$AWS_REGION" \
    --query 'services[0].{ServiceName:serviceName,Status:status,DesiredCount:desiredCount,RunningCount:runningCount}' \
    --output table

echo ""
echo "CloudWatch Logs:"
echo "  Log Group: /ecs/cargo-tracker"
echo "  Region: $AWS_REGION"
echo ""

if [ -n "$ALB_DNS" ]; then
    echo "Application URL:"
    echo "  http://$ALB_DNS/cargo-tracker/"
    echo ""
fi

echo "To view logs:"
echo "  aws logs tail /ecs/cargo-tracker --follow --region $AWS_REGION"
echo ""
