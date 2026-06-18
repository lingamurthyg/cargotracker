@echo off
setlocal enabledelayedexpansion

REM Build and Push Docker Image Script for Cargo Tracker (Windows)
REM This script builds the Docker image and pushes it to a container registry

echo ========================================
echo Cargo Tracker - Build and Push Script
echo ========================================
echo.

REM Project name
set PROJECT_NAME=cargo-tracker

REM Sanitize image name (lowercase, replace special chars with hyphens)
set IMAGE_NAME=cargo-tracker

echo Select Container Registry:
echo 1. AWS ECR (Elastic Container Registry)
echo 2. Docker Hub
set /p REGISTRY_CHOICE="Enter your choice (1 or 2): "

if "!REGISTRY_CHOICE!"=="1" (
    echo Selected: AWS ECR
    
    REM AWS ECR Configuration
    set /p AWS_REGION="Enter AWS Region (e.g., us-east-1): "
    set /p AWS_ACCOUNT_ID="Enter AWS Account ID: "
    set /p ECR_REPO="Enter ECR Repository Name (default: !IMAGE_NAME!): "
    if "!ECR_REPO!"=="" set ECR_REPO=!IMAGE_NAME!
    
    REM Construct ECR registry URL
    set REGISTRY_URL=!AWS_ACCOUNT_ID!.dkr.ecr.!AWS_REGION!.amazonaws.com
    set FULL_IMAGE_NAME=!REGISTRY_URL!/!ECR_REPO!
    
    echo Authenticating with AWS ECR...
    for /f "delims=" %%i in ('aws ecr get-login-password --region !AWS_REGION!') do set ECR_PASSWORD=%%i
    echo !ECR_PASSWORD! | docker login --username AWS --password-stdin !REGISTRY_URL!
    
    if !ERRORLEVEL! neq 0 (
        echo ECR authentication failed. Please check your AWS credentials.
        exit /b 1
    )
    
    REM Check if ECR repository exists, create if it doesn't
    echo Checking if ECR repository exists...
    aws ecr describe-repositories --repository-names !ECR_REPO! --region !AWS_REGION! >nul 2>&1
    if !ERRORLEVEL! neq 0 (
        echo Creating ECR repository: !ECR_REPO!
        aws ecr create-repository --repository-name !ECR_REPO! --region !AWS_REGION!
    )
    
) else if "!REGISTRY_CHOICE!"=="2" (
    echo Selected: Docker Hub
    
    REM Docker Hub Configuration
    set /p DOCKER_USERNAME="Enter Docker Hub Username: "
    set /p DOCKER_PASSWORD="Enter Docker Hub Password/Token: "
    
    set FULL_IMAGE_NAME=!DOCKER_USERNAME!/!IMAGE_NAME!
    
    echo Authenticating with Docker Hub...
    echo !DOCKER_PASSWORD! | docker login --username !DOCKER_USERNAME! --password-stdin
    
    if !ERRORLEVEL! neq 0 (
        echo Docker Hub authentication failed.
        exit /b 1
    )
    
) else (
    echo Invalid choice. Exiting.
    exit /b 1
)

REM Prompt for image tag
set /p IMAGE_TAG="Enter image tag (default: latest): "
if "!IMAGE_TAG!"=="" set IMAGE_TAG=latest

set FULL_IMAGE_NAME=!FULL_IMAGE_NAME!:!IMAGE_TAG!

echo.
echo ========================================
echo Build Configuration
echo ========================================
echo Image Name: !FULL_IMAGE_NAME!
echo Build Context: %CD%
echo.

REM Build Docker image
echo Building Docker image...
docker build -t !FULL_IMAGE_NAME! .

if !ERRORLEVEL! neq 0 (
    echo Docker build failed.
    exit /b 1
)

echo Docker image built successfully!
echo.

REM Push Docker image
echo Pushing Docker image to registry...
docker push !FULL_IMAGE_NAME!

if !ERRORLEVEL! neq 0 (
    echo Docker push failed.
    exit /b 1
)

echo.
echo ========================================
echo Success!
echo ========================================
echo Image pushed successfully: !FULL_IMAGE_NAME!
echo.
echo Next Steps:
echo 1. Update your Kubernetes deployment manifests with this image
echo 2. Run the deployment script: scripts\deploy-image.bat
echo.

endlocal
