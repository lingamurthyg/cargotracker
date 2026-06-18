@echo off
setlocal enabledelayedexpansion

REM Deploy Cargo Tracker to AWS ECS Fargate (Windows)
REM This script deploys the containerized application to AWS ECS

echo ==========================================
echo   Cargo Tracker - ECS Fargate Deployment
echo ==========================================
echo.

REM Check if AWS CLI is installed
where aws >nul 2>&1
if !ERRORLEVEL! neq 0 (
    echo AWS CLI is not installed. Please install it first.
    exit /b 1
)

REM Prompt for AWS configuration
echo === AWS Configuration ===
set /p AWS_REGION="Enter AWS Region (e.g., us-east-1): "
set /p CLUSTER_NAME="Enter ECS Cluster Name: "
echo.

REM Get AWS Account ID
echo Retrieving AWS Account ID...
for /f "tokens=*" %%i in ('aws sts get-caller-identity --query Account --output text') do set ACCOUNT_ID=%%i
if !ERRORLEVEL! neq 0 (
    echo Failed to retrieve AWS Account ID. Please check your AWS credentials.
    exit /b 1
)
echo AWS Account ID: !ACCOUNT_ID!
echo.

REM Check/Create ECS Cluster
echo Checking ECS cluster...
aws ecs describe-clusters --clusters !CLUSTER_NAME! --region !AWS_REGION! >nul 2>&1
if !ERRORLEVEL! neq 0 (
    echo Cluster does not exist. Creating ECS cluster: !CLUSTER_NAME!
    aws ecs create-cluster --cluster-name !CLUSTER_NAME! --region !AWS_REGION!
    if !ERRORLEVEL! neq 0 (
        echo Failed to create ECS cluster
        exit /b 1
    )
    echo ECS cluster created successfully
)
echo.

REM Prompt for network configuration
echo === Network Configuration ===
set /p VPC_ID="Enter VPC ID: "
set /p SUBNETS_INPUT="Enter Subnet IDs (comma-separated, at least 2): "
set /p SECURITY_GROUP="Enter Security Group ID: "
echo.

REM Parse subnets
for /f "tokens=1,2 delims=," %%a in ("!SUBNETS_INPUT!") do (
    set SUBNET_1=%%a
    set SUBNET_2=%%b
)

REM Trim whitespace
set SUBNET_1=!SUBNET_1: =!
set SUBNET_2=!SUBNET_2: =!
if "!SUBNET_2!"=="" set SUBNET_2=!SUBNET_1!

echo VPC ID: !VPC_ID!
echo Subnet 1: !SUBNET_1!
echo Subnet 2: !SUBNET_2!
echo Security Group: !SECURITY_GROUP!
echo.

REM Prompt for Docker image URI
echo === Docker Image Configuration ===
set /p IMAGE_URI="Enter Docker Image URI (e.g., 123456789.dkr.ecr.us-east-1.amazonaws.com/cargo-tracker:latest): "
echo.

REM Load Balancer Configuration
echo === Load Balancer Configuration ===
set /p NEED_LB="Do you need a load balancer for this service? (y/n): "

if /i "!NEED_LB!"=="y" (
    echo Creating Application Load Balancer and Target Group...
    
    set ALB_NAME=cargo-tracker-alb
    echo Creating ALB: !ALB_NAME!
    
    for /f "tokens=*" %%i in ('aws elbv2 create-load-balancer --name !ALB_NAME! --subnets !SUBNET_1! !SUBNET_2! --security-groups !SECURITY_GROUP! --scheme internet-facing --type application --ip-address-type ipv4 --region !AWS_REGION! --query "LoadBalancers[0].LoadBalancerArn" --output text 2^>nul') do set ALB_ARN=%%i
    
    if "!ALB_ARN!"=="" (
        echo ALB may already exist, retrieving existing ALB...
        for /f "tokens=*" %%i in ('aws elbv2 describe-load-balancers --names !ALB_NAME! --region !AWS_REGION! --query "LoadBalancers[0].LoadBalancerArn" --output text 2^>nul') do set ALB_ARN=%%i
    )
    
    if "!ALB_ARN!"=="" (
        echo Failed to create or retrieve ALB
        exit /b 1
    )
    
    echo ALB ARN: !ALB_ARN!
    
    REM Get ALB DNS Name
    for /f "tokens=*" %%i in ('aws elbv2 describe-load-balancers --load-balancer-arns !ALB_ARN! --region !AWS_REGION! --query "LoadBalancers[0].DNSName" --output text') do set ALB_DNS=%%i
    
    REM Create Target Group
    set TG_NAME=cargo-tracker-tg
    echo Creating Target Group: !TG_NAME!
    
    for /f "tokens=*" %%i in ('aws elbv2 create-target-group --name !TG_NAME! --protocol HTTP --port 8080 --vpc-id !VPC_ID! --target-type ip --health-check-enabled --health-check-protocol HTTP --health-check-path "/" --health-check-interval-seconds 30 --health-check-timeout-seconds 5 --healthy-threshold-count 2 --unhealthy-threshold-count 3 --region !AWS_REGION! --query "TargetGroups[0].TargetGroupArn" --output text 2^>nul') do set TARGET_GROUP_ARN=%%i
    
    if "!TARGET_GROUP_ARN!"=="" (
        echo Target Group may already exist, retrieving existing TG...
        for /f "tokens=*" %%i in ('aws elbv2 describe-target-groups --names !TG_NAME! --region !AWS_REGION! --query "TargetGroups[0].TargetGroupArn" --output text 2^>nul') do set TARGET_GROUP_ARN=%%i
    )
    
    if "!TARGET_GROUP_ARN!"=="" (
        echo Failed to create or retrieve Target Group
        exit /b 1
    )
    
    echo Target Group ARN: !TARGET_GROUP_ARN!
    
    REM Create Listener
    echo Creating ALB Listener...
    aws elbv2 create-listener --load-balancer-arn !ALB_ARN! --protocol HTTP --port 80 --default-actions Type=forward,TargetGroupArn=!TARGET_GROUP_ARN! --region !AWS_REGION! >nul 2>&1
    
    echo Load Balancer setup completed
    echo.
) else (
    echo Skipping load balancer creation
    set TARGET_GROUP_ARN=
    
    REM Remove loadBalancers section from service definition
    powershell -Command "(Get-Content ecs\service-definition.json) -replace '\"loadBalancers\":.*?],', '' | Set-Content ecs\service-definition-temp.json"
    powershell -Command "(Get-Content ecs\service-definition-temp.json) -replace '\"healthCheckGracePeriodSeconds\":.*?,', '' | Set-Content ecs\service-definition.json"
    del ecs\service-definition-temp.json
    echo.
)

REM Create CloudWatch Log Group
echo Creating CloudWatch Log Group...
aws logs create-log-group --log-group-name "/ecs/cargo-tracker" --region !AWS_REGION! 2>nul
echo.

REM Replace placeholders in task definition
echo Preparing task definition...
powershell -Command "(Get-Content ecs\task-definition.json) -replace '{{IMAGE_URI}}', '!IMAGE_URI!' -replace '{{AWS_REGION}}', '!AWS_REGION!' -replace '{{ACCOUNT_ID}}', '!ACCOUNT_ID!' | Set-Content ecs\task-definition-resolved.json"

REM Register task definition
echo Registering ECS task definition...
for /f "tokens=*" %%i in ('aws ecs register-task-definition --cli-input-json file://ecs/task-definition-resolved.json --region !AWS_REGION! --query "taskDefinition.taskDefinitionArn" --output text') do set TASK_DEF_ARN=%%i

if !ERRORLEVEL! neq 0 (
    echo Failed to register task definition
    exit /b 1
)

echo Task definition registered: !TASK_DEF_ARN!
echo.

REM Replace placeholders in service definition
echo Preparing service definition...
if not "!TARGET_GROUP_ARN!"=="" (
    powershell -Command "(Get-Content ecs\service-definition.json) -replace '{{CLUSTER_NAME}}', '!CLUSTER_NAME!' -replace '{{SUBNET_1}}', '!SUBNET_1!' -replace '{{SUBNET_2}}', '!SUBNET_2!' -replace '{{SECURITY_GROUP}}', '!SECURITY_GROUP!' -replace '{{TARGET_GROUP_ARN}}', '!TARGET_GROUP_ARN!' | Set-Content ecs\service-definition-resolved.json"
) else (
    powershell -Command "(Get-Content ecs\service-definition.json) -replace '{{CLUSTER_NAME}}', '!CLUSTER_NAME!' -replace '{{SUBNET_1}}', '!SUBNET_1!' -replace '{{SUBNET_2}}', '!SUBNET_2!' -replace '{{SECURITY_GROUP}}', '!SECURITY_GROUP!' | Set-Content ecs\service-definition-resolved.json"
)

REM Check if service exists
echo Checking if service exists...
for /f "tokens=*" %%i in ('aws ecs describe-services --cluster !CLUSTER_NAME! --services cargo-tracker-service --region !AWS_REGION! --query "services[0].serviceName" --output text 2^>nul') do set SERVICE_EXISTS=%%i

if "!SERVICE_EXISTS!"=="cargo-tracker-service" (
    echo Service exists. Updating service...
    aws ecs update-service --cluster !CLUSTER_NAME! --service cargo-tracker-service --task-definition !TASK_DEF_ARN! --desired-count 2 --region !AWS_REGION! --force-new-deployment
    
    if !ERRORLEVEL! neq 0 (
        echo Failed to update service
        exit /b 1
    )
    
    echo Service updated successfully
) else (
    echo Service does not exist. Creating service...
    aws ecs create-service --cli-input-json file://ecs/service-definition-resolved.json --region !AWS_REGION!
    
    if !ERRORLEVEL! neq 0 (
        echo Failed to create service
        exit /b 1
    )
    
    echo Service created successfully
)

echo.
echo Waiting for service to become stable...
aws ecs wait services-stable --cluster !CLUSTER_NAME! --services cargo-tracker-service --region !AWS_REGION!

echo.
echo ==========================================
echo   Deployment Completed Successfully!
echo ==========================================
echo.
echo Cluster: !CLUSTER_NAME!
echo Service: cargo-tracker-service
echo Task Definition: !TASK_DEF_ARN!
echo CloudWatch Logs: /ecs/cargo-tracker
echo.

if not "!ALB_DNS!"=="" (
    echo Application URL: http://!ALB_DNS!
    echo.
)

echo To view service details:
echo   aws ecs describe-services --cluster !CLUSTER_NAME! --services cargo-tracker-service --region !AWS_REGION!
echo.
echo To view logs:
echo   aws logs tail /ecs/cargo-tracker --follow --region !AWS_REGION!
echo.

endlocal
