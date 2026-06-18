@echo off
setlocal enabledelayedexpansion

echo ==========================================
echo AWS ECS Fargate Deployment Script
echo ==========================================
echo.

REM Project configuration
set PROJECT_NAME=cargo-tracker
set SERVICE_NAME=%PROJECT_NAME%-service
set TASK_FAMILY=%PROJECT_NAME%-task

echo Project: %PROJECT_NAME%
echo Service: %SERVICE_NAME%
echo Task Family: %TASK_FAMILY%
echo.

REM Prompt for AWS configuration
echo === AWS Configuration ===
set /p AWS_REGION="Enter AWS Region (e.g., us-east-1): "
set /p CLUSTER_NAME="Enter ECS Cluster Name: "

REM Get AWS Account ID
echo.
echo Retrieving AWS Account ID...
for /f "delims=" %%i in ('aws sts get-caller-identity --query Account --output text') do set ACCOUNT_ID=%%i
echo AWS Account ID: !ACCOUNT_ID!

REM Check if cluster exists, create if not
echo.
echo Checking if ECS cluster exists...
aws ecs describe-clusters --clusters "!CLUSTER_NAME!" --region "!AWS_REGION!" >nul 2>&1
if !ERRORLEVEL! neq 0 (
    echo Cluster does not exist. Creating ECS cluster: !CLUSTER_NAME!
    aws ecs create-cluster --cluster-name "!CLUSTER_NAME!" --region "!AWS_REGION!"
    if !ERRORLEVEL! neq 0 (
        echo ERROR: Failed to create ECS cluster
        exit /b 1
    )
    echo ECS cluster created successfully
)

REM Prompt for network configuration
echo.
echo === Network Configuration ===
set /p VPC_ID="Enter VPC ID: "
set /p SUBNET_IDS="Enter Subnet IDs (comma-separated, at least 2): "
set /p SECURITY_GROUP="Enter Security Group ID: "

REM Parse subnets
for /f "tokens=1,2 delims=," %%a in ("!SUBNET_IDS!") do (
    set SUBNET_1=%%a
    set SUBNET_2=%%b
)

REM Prompt for Docker image URI
echo.
echo === Docker Image Configuration ===
set /p IMAGE_URI="Enter Docker Image URI (e.g., 123456789.dkr.ecr.us-east-1.amazonaws.com/cargo-tracker:latest): "

REM Prompt for load balancer
echo.
echo === Load Balancer Configuration ===
set /p NEED_LB="Do you need a load balancer for this service? (y/n): "

if /i "!NEED_LB!"=="y" (
    echo.
    echo Creating Application Load Balancer and Target Group...
    
    REM Create ALB
    set ALB_NAME=%PROJECT_NAME%-alb
    echo Creating ALB: !ALB_NAME!
    for /f "delims=" %%i in ('aws elbv2 create-load-balancer --name "!ALB_NAME!" --subnets !SUBNET_1! !SUBNET_2! --security-groups "!SECURITY_GROUP!" --scheme internet-facing --type application --ip-address-type ipv4 --region "!AWS_REGION!" --query "LoadBalancers[0].LoadBalancerArn" --output text') do set ALB_ARN=%%i
    
    if !ERRORLEVEL! neq 0 (
        echo ERROR: Failed to create ALB
        exit /b 1
    )
    
    echo ALB created: !ALB_ARN!
    
    REM Create Target Group with target-type ip
    set TG_NAME=%PROJECT_NAME%-tg
    echo Creating Target Group: !TG_NAME!
    for /f "delims=" %%i in ('aws elbv2 create-target-group --name "!TG_NAME!" --protocol HTTP --port 8080 --vpc-id "!VPC_ID!" --target-type ip --health-check-enabled --health-check-protocol HTTP --health-check-path "/cargo-tracker/" --health-check-interval-seconds 30 --health-check-timeout-seconds 5 --healthy-threshold-count 2 --unhealthy-threshold-count 3 --region "!AWS_REGION!" --query "TargetGroups[0].TargetGroupArn" --output text') do set TARGET_GROUP_ARN=%%i
    
    if !ERRORLEVEL! neq 0 (
        echo ERROR: Failed to create Target Group
        exit /b 1
    )
    
    echo Target Group created: !TARGET_GROUP_ARN!
    
    REM Create Listener
    echo Creating ALB Listener...
    aws elbv2 create-listener --load-balancer-arn "!ALB_ARN!" --protocol HTTP --port 80 --default-actions Type=forward,TargetGroupArn="!TARGET_GROUP_ARN!" --region "!AWS_REGION!"
    
    if !ERRORLEVEL! neq 0 (
        echo ERROR: Failed to create ALB Listener
        exit /b 1
    )
    
    echo ALB Listener created successfully
    
    REM Get ALB DNS name
    for /f "delims=" %%i in ('aws elbv2 describe-load-balancers --load-balancer-arns "!ALB_ARN!" --region "!AWS_REGION!" --query "LoadBalancers[0].DNSName" --output text') do set ALB_DNS=%%i
    echo ALB DNS Name: !ALB_DNS!
) else (
    echo Skipping load balancer creation
    set TARGET_GROUP_ARN=
)

REM Create CloudWatch log group
echo.
echo Creating CloudWatch log group...
aws logs create-log-group --log-group-name "/ecs/%PROJECT_NAME%" --region "!AWS_REGION!" 2>nul
if !ERRORLEVEL! neq 0 (
    echo Log group already exists or creation skipped
)

REM Replace placeholders in task definition
echo.
echo Preparing task definition...
copy ecs\task-definition.json %TEMP%\task-definition.json >nul
powershell -Command "(Get-Content '%TEMP%\task-definition.json') -replace '{{IMAGE_URI}}', '!IMAGE_URI!' | Set-Content '%TEMP%\task-definition.json'"
powershell -Command "(Get-Content '%TEMP%\task-definition.json') -replace '{{AWS_REGION}}', '!AWS_REGION!' | Set-Content '%TEMP%\task-definition.json'"
powershell -Command "(Get-Content '%TEMP%\task-definition.json') -replace '{{ACCOUNT_ID}}', '!ACCOUNT_ID!' | Set-Content '%TEMP%\task-definition.json'"

REM Register task definition
echo Registering task definition...
for /f "delims=" %%i in ('aws ecs register-task-definition --cli-input-json file://%TEMP%/task-definition.json --region "!AWS_REGION!" --query "taskDefinition.taskDefinitionArn" --output text') do set TASK_DEF_ARN=%%i

if !ERRORLEVEL! neq 0 (
    echo ERROR: Failed to register task definition
    exit /b 1
)

echo Task definition registered: !TASK_DEF_ARN!

REM Prepare service definition
echo.
echo Preparing service definition...
copy ecs\service-definition.json %TEMP%\service-definition.json >nul
powershell -Command "(Get-Content '%TEMP%\service-definition.json') -replace '{{CLUSTER_NAME}}', '!CLUSTER_NAME!' | Set-Content '%TEMP%\service-definition.json'"
powershell -Command "(Get-Content '%TEMP%\service-definition.json') -replace '{{SUBNET_1}}', '!SUBNET_1!' | Set-Content '%TEMP%\service-definition.json'"
powershell -Command "(Get-Content '%TEMP%\service-definition.json') -replace '{{SUBNET_2}}', '!SUBNET_2!' | Set-Content '%TEMP%\service-definition.json'"
powershell -Command "(Get-Content '%TEMP%\service-definition.json') -replace '{{SECURITY_GROUP}}', '!SECURITY_GROUP!' | Set-Content '%TEMP%\service-definition.json'"

if /i "!NEED_LB!"=="y" (
    powershell -Command "(Get-Content '%TEMP%\service-definition.json') -replace '{{TARGET_GROUP_ARN}}', '!TARGET_GROUP_ARN!' | Set-Content '%TEMP%\service-definition.json'"
) else (
    REM Remove loadBalancers section if no LB
    powershell -Command "$json = Get-Content '%TEMP%\service-definition.json' | ConvertFrom-Json; $json.PSObject.Properties.Remove('loadBalancers'); $json.PSObject.Properties.Remove('healthCheckGracePeriodSeconds'); $json | ConvertTo-Json -Depth 10 | Set-Content '%TEMP%\service-definition.json'"
)

REM Check if service exists
echo.
echo Checking if service exists...
for /f "delims=" %%i in ('aws ecs describe-services --cluster "!CLUSTER_NAME!" --services "!SERVICE_NAME!" --region "!AWS_REGION!" --query "services[?status==`ACTIVE`].serviceName" --output text') do set SERVICE_EXISTS=%%i

if "!SERVICE_EXISTS!"=="" (
    echo Service does not exist. Creating new service...
    aws ecs create-service --cli-input-json file://%TEMP%/service-definition.json --region "!AWS_REGION!"
    
    if !ERRORLEVEL! neq 0 (
        echo ERROR: Failed to create service
        exit /b 1
    )
    
    echo Service created successfully
) else (
    echo Service exists. Updating service...
    aws ecs update-service --cluster "!CLUSTER_NAME!" --service "!SERVICE_NAME!" --task-definition "!TASK_DEF_ARN!" --region "!AWS_REGION!"
    
    if !ERRORLEVEL! neq 0 (
        echo ERROR: Failed to update service
        exit /b 1
    )
    
    echo Service updated successfully
)

REM Wait for service to stabilize
echo.
echo Waiting for service to stabilize (this may take a few minutes)...
aws ecs wait services-stable --cluster "!CLUSTER_NAME!" --services "!SERVICE_NAME!" --region "!AWS_REGION!"

echo.
echo ==========================================
echo Deployment Completed Successfully
echo ==========================================
echo.
echo Service Details:
aws ecs describe-services --cluster "!CLUSTER_NAME!" --services "!SERVICE_NAME!" --region "!AWS_REGION!" --query "services[0].[serviceName,status,runningCount,desiredCount]" --output table

echo.
echo CloudWatch Logs: /ecs/%PROJECT_NAME%
echo Region: !AWS_REGION!

if /i "!NEED_LB!"=="y" (
    echo.
    echo Application URL: http://!ALB_DNS!/cargo-tracker/
    echo.
    echo Note: It may take a few minutes for the ALB to become healthy
)

echo.
echo Deployment complete!

endlocal
