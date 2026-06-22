@echo off
setlocal enabledelayedexpansion

REM ============================================================================
REM AWS EKS Deployment Script for Cargo Tracker (Windows)
REM Deploys containerized application to Amazon EKS
REM ============================================================================

echo ============================================================================
echo AWS EKS Deployment Script for Cargo Tracker
echo ============================================================================
echo.

REM Check prerequisites
echo Checking prerequisites...

where aws >nul 2>&1
if !ERRORLEVEL! neq 0 (
    echo ERROR: AWS CLI is not installed
    echo Please install AWS CLI: https://aws.amazon.com/cli/
    exit /b 1
)

where kubectl >nul 2>&1
if !ERRORLEVEL! neq 0 (
    echo ERROR: kubectl is not installed
    echo Please install kubectl: https://kubernetes.io/docs/tasks/tools/
    exit /b 1
)

echo Prerequisites check passed
echo.

REM AWS Configuration
echo AWS EKS Configuration
echo ================================
set /p AWS_REGION="Enter AWS Region (e.g., us-east-1): "
set /p CLUSTER_NAME="Enter EKS Cluster Name: "

echo.
echo Configuring kubectl for EKS cluster...
aws eks update-kubeconfig --region !AWS_REGION! --name !CLUSTER_NAME!

if !ERRORLEVEL! neq 0 (
    echo Failed to configure kubectl for EKS cluster
    exit /b 1
)

echo.
echo Verifying cluster connectivity...
kubectl cluster-info

if !ERRORLEVEL! neq 0 (
    echo Failed to connect to EKS cluster
    exit /b 1
)

echo.
echo Docker Image Configuration
echo ================================
set /p IMAGE_URI="Enter Docker Image URI (e.g., 123456789.dkr.ecr.us-east-1.amazonaws.com/cargo-tracker:latest): "

echo.
echo Database Configuration
echo ================================
echo Configure database connection (press Enter to use H2 embedded database)
set /p DB_DRIVER_CLASS="Enter DB_DRIVER_CLASS (default: org.h2.jdbcx.JdbcDataSource): "
if "!DB_DRIVER_CLASS!"=="" set DB_DRIVER_CLASS=org.h2.jdbcx.JdbcDataSource

set /p DB_JDBC_URL="Enter DB_JDBC_URL (default: jdbc:h2:file:/app/data/cargo-tracker-database): "
if "!DB_JDBC_URL!"=="" set DB_JDBC_URL=jdbc:h2:file:/app/data/cargo-tracker-database

set /p DB_USER="Enter DB_USER (optional): "
set /p DB_PASSWORD="Enter DB_PASSWORD (optional): "

echo.
echo Updating Kubernetes manifests...

REM Create temporary deployment file with replacements
powershell -Command "(Get-Content kubernetes\deployment.yaml) -replace '{{IMAGE_URI}}', '!IMAGE_URI!' -replace '{{DB_DRIVER_CLASS}}', '!DB_DRIVER_CLASS!' -replace '{{DB_JDBC_URL}}', '!DB_JDBC_URL!' -replace '{{DB_USER}}', '!DB_USER!' -replace '{{DB_PASSWORD}}', '!DB_PASSWORD!' | Set-Content kubernetes\deployment-temp.yaml"

echo.
echo Deploying to AWS EKS...
echo ================================

REM Apply namespace
echo Creating namespace...
kubectl apply -f kubernetes\namespace.yaml

REM Apply deployment
echo Deploying application...
kubectl apply -f kubernetes\deployment-temp.yaml

REM Apply service
echo Creating service...
kubectl apply -f kubernetes\service.yaml

REM Apply ingress
echo Creating ingress...
kubectl apply -f kubernetes\ingress.yaml

echo.
echo Waiting for deployment to complete...
kubectl rollout status deployment/cargo-tracker -n cargo-tracker --timeout=5m

if !ERRORLEVEL! neq 0 (
    echo Deployment rollout failed or timed out
    echo Check pod status with: kubectl get pods -n cargo-tracker
    echo Check logs with: kubectl logs -n cargo-tracker -l app=cargo-tracker
    del kubernetes\deployment-temp.yaml
    exit /b 1
)

echo.
echo Verifying deployment...
echo ================================
kubectl get pods,svc,ingress -n cargo-tracker

echo.
echo ============================================================================
echo SUCCESS! Application deployed to AWS EKS
echo ============================================================================
echo.
echo Deployment Details:
echo   Namespace: cargo-tracker
echo   Cluster: !CLUSTER_NAME!
echo   Region: !AWS_REGION!
echo   Image: !IMAGE_URI!
echo.
echo Access your application:
echo   1. Get the Load Balancer URL:
echo      kubectl get ingress cargo-tracker-ingress -n cargo-tracker
echo.
echo   2. Monitor pods:
echo      kubectl get pods -n cargo-tracker -w
echo.
echo   3. View logs:
echo      kubectl logs -n cargo-tracker -l app=cargo-tracker -f
echo.
echo   4. Port forward for local access:
echo      kubectl port-forward -n cargo-tracker svc/cargo-tracker-service 8080:80
echo.

REM Clean up temporary file
del kubernetes\deployment-temp.yaml

endlocal
