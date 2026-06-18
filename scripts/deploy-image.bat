@echo off
setlocal enabledelayedexpansion

REM Deploy Cargo Tracker to AWS EKS (Windows)
REM This script deploys the containerized application to Amazon EKS

echo ========================================
echo Cargo Tracker - EKS Deployment Script
echo ========================================
echo.

REM Check prerequisites
echo Checking prerequisites...

where aws >nul 2>&1
if !ERRORLEVEL! neq 0 (
    echo AWS CLI is not installed. Please install it first.
    exit /b 1
)

where kubectl >nul 2>&1
if !ERRORLEVEL! neq 0 (
    echo kubectl is not installed. Please install it first.
    exit /b 1
)

echo Prerequisites check passed!
echo.

REM Prompt for AWS configuration
set /p AWS_REGION="Enter AWS Region (e.g., us-east-1): "
set /p CLUSTER_NAME="Enter EKS Cluster Name: "

if "!AWS_REGION!"=="" (
    echo AWS Region is required.
    exit /b 1
)

if "!CLUSTER_NAME!"=="" (
    echo Cluster Name is required.
    exit /b 1
)

REM Prompt for Docker image URI
echo.
echo Enter the full Docker image URI
echo Example: 123456789012.dkr.ecr.us-east-1.amazonaws.com/cargo-tracker:latest
set /p IMAGE_URI="Docker Image URI: "

if "!IMAGE_URI!"=="" (
    echo Docker Image URI is required.
    exit /b 1
)

REM Configure kubectl for EKS
echo.
echo Configuring kubectl for EKS cluster...
aws eks update-kubeconfig --region !AWS_REGION! --name !CLUSTER_NAME!

if !ERRORLEVEL! neq 0 (
    echo Failed to configure kubectl. Please check your AWS credentials and cluster name.
    exit /b 1
)

REM Verify cluster connectivity
echo Verifying cluster connectivity...
kubectl cluster-info
if !ERRORLEVEL! neq 0 (
    echo Failed to connect to cluster.
    exit /b 1
)

echo Successfully connected to EKS cluster!
echo.

REM Update deployment manifest with image URI
echo Updating Kubernetes manifests with image URI...
cd /d "%~dp0\.."

REM Create temporary directory for processed manifests
set TEMP_DIR=%TEMP%\cargo-tracker-k8s-%RANDOM%
mkdir !TEMP_DIR!

REM Copy manifests to temp directory
xcopy /E /I /Y kubernetes !TEMP_DIR! >nul

REM Replace placeholder in deployment.yaml using PowerShell
powershell -Command "(Get-Content '!TEMP_DIR!\deployment.yaml') -replace '{{IMAGE_URI}}', '!IMAGE_URI!' | Set-Content '!TEMP_DIR!\deployment.yaml'"

echo Manifests updated successfully!
echo.

REM Apply Kubernetes manifests
echo Deploying to Kubernetes...
echo.

echo 1. Creating namespace...
kubectl apply -f !TEMP_DIR!\namespace.yaml

echo.
echo 2. Deploying application...
kubectl apply -f !TEMP_DIR!\deployment.yaml

echo.
echo 3. Creating service...
kubectl apply -f !TEMP_DIR!\service.yaml

echo.
echo 4. Creating ingress...
kubectl apply -f !TEMP_DIR!\ingress.yaml

echo.
echo Waiting for deployment to complete...
kubectl rollout status deployment/cargo-tracker -n cargo-tracker --timeout=5m

if !ERRORLEVEL! neq 0 (
    echo Deployment rollout failed or timed out.
    echo Checking pod status...
    kubectl get pods -n cargo-tracker
    rmdir /S /Q !TEMP_DIR!
    exit /b 1
)

echo.
echo ========================================
echo Deployment Successful!
echo ========================================
echo.

REM Display deployment information
echo Deployment Information:
echo.
kubectl get pods -n cargo-tracker
echo.
kubectl get svc -n cargo-tracker
echo.
kubectl get ingress -n cargo-tracker

echo.
echo Application Access:
for /f "delims=" %%i in ('kubectl get ingress cargo-tracker-ingress -n cargo-tracker -o jsonpath^="{.status.loadBalancer.ingress[0].hostname}" 2^>nul') do set INGRESS_HOST=%%i

if not "!INGRESS_HOST!"=="" (
    echo Application URL: http://!INGRESS_HOST!/cargo-tracker
) else (
    echo Ingress is being provisioned. Run the following command to get the URL:
    echo kubectl get ingress cargo-tracker-ingress -n cargo-tracker
)

echo.
echo Useful Commands:
echo View logs: kubectl logs -f deployment/cargo-tracker -n cargo-tracker
echo View pods: kubectl get pods -n cargo-tracker
echo Describe pod: kubectl describe pod ^<pod-name^> -n cargo-tracker
echo Scale deployment: kubectl scale deployment/cargo-tracker --replicas=3 -n cargo-tracker
echo Delete deployment: kubectl delete namespace cargo-tracker
echo.

REM Cleanup
rmdir /S /Q !TEMP_DIR!

endlocal
