@echo off
setlocal enabledelayedexpansion

REM Deploy to AWS EKS Script for Cargo Tracker (Windows)
REM This script deploys the containerized application to AWS EKS

echo ==========================================
echo AWS EKS Deployment Script
echo ==========================================
echo.

REM Prompt for AWS configuration
set /p AWS_REGION="Enter AWS Region (e.g., us-east-1): "
set /p CLUSTER_NAME="Enter EKS Cluster Name: "

echo.
echo AWS Region: !AWS_REGION!
echo EKS Cluster: !CLUSTER_NAME!
echo.

REM Prompt for Docker image URI
set /p IMAGE_URI="Enter Docker Image URI (e.g., 123456789012.dkr.ecr.us-east-1.amazonaws.com/cargo-tracker:latest): "

echo.
echo Docker Image: !IMAGE_URI!
echo.

REM Prompt for database configuration
echo === Database Configuration ===
echo Enter database connection details (or press Enter to use defaults)
set /p DB_DRIVER_CLASS="Database Driver Class (default: org.h2.jdbcx.JdbcDataSource): "
if "!DB_DRIVER_CLASS!"=="" set DB_DRIVER_CLASS=org.h2.jdbcx.JdbcDataSource

set /p DB_JDBC_URL="Database JDBC URL (default: jdbc:h2:file:/app/data/cargo-tracker-database): "
if "!DB_JDBC_URL!"=="" set DB_JDBC_URL=jdbc:h2:file:/app/data/cargo-tracker-database

set /p DB_USER="Database User (optional): "
set /p DB_PASSWORD="Database Password (optional): "

echo.
echo Database Driver: !DB_DRIVER_CLASS!
echo Database URL: !DB_JDBC_URL!
echo.

REM Configure kubectl for EKS
echo ==========================================
echo Configuring kubectl for EKS...
echo ==========================================
aws eks update-kubeconfig --region !AWS_REGION! --name !CLUSTER_NAME!

if !ERRORLEVEL! neq 0 (
    echo ERROR: Failed to configure kubectl for EKS cluster
    exit /b 1
)

echo kubectl configured successfully
echo.

REM Verify cluster connectivity
echo Verifying cluster connectivity...
kubectl cluster-info
if !ERRORLEVEL! neq 0 (
    echo ERROR: Cannot connect to EKS cluster
    exit /b 1
)

echo.
echo Cluster connectivity verified
echo.

REM Update Kubernetes manifests with actual values
echo ==========================================
echo Updating Kubernetes manifests...
echo ==========================================

REM Create temporary directory for processed manifests
set TEMP_DIR=%TEMP%\k8s-deploy-%RANDOM%
mkdir !TEMP_DIR!
xcopy /E /I /Q kubernetes !TEMP_DIR! >nul

REM Replace placeholders in deployment.yaml using PowerShell
powershell -Command "(Get-Content '!TEMP_DIR!\deployment.yaml') -replace '{{IMAGE_URI}}', '!IMAGE_URI!' | Set-Content '!TEMP_DIR!\deployment.yaml'"
powershell -Command "(Get-Content '!TEMP_DIR!\deployment.yaml') -replace '{{DB_DRIVER_CLASS}}', '!DB_DRIVER_CLASS!' | Set-Content '!TEMP_DIR!\deployment.yaml'"
powershell -Command "(Get-Content '!TEMP_DIR!\deployment.yaml') -replace '{{DB_JDBC_URL}}', '!DB_JDBC_URL!' | Set-Content '!TEMP_DIR!\deployment.yaml'"
powershell -Command "(Get-Content '!TEMP_DIR!\deployment.yaml') -replace '{{DB_USER}}', '!DB_USER!' | Set-Content '!TEMP_DIR!\deployment.yaml'"
powershell -Command "(Get-Content '!TEMP_DIR!\deployment.yaml') -replace '{{DB_PASSWORD}}', '!DB_PASSWORD!' | Set-Content '!TEMP_DIR!\deployment.yaml'"

echo Manifests updated successfully
echo.

REM Apply Kubernetes manifests
echo ==========================================
echo Deploying to EKS...
echo ==========================================

REM Create namespace
echo Creating namespace...
kubectl apply -f !TEMP_DIR!\namespace.yaml

REM Apply deployment
echo Applying deployment...
kubectl apply -f !TEMP_DIR!\deployment.yaml

REM Apply service
echo Applying service...
kubectl apply -f !TEMP_DIR!\service.yaml

REM Apply ingress
echo Applying ingress...
kubectl apply -f !TEMP_DIR!\ingress.yaml

echo.
echo Kubernetes resources applied successfully
echo.

REM Wait for deployment rollout
echo ==========================================
echo Waiting for deployment to complete...
echo ==========================================
kubectl rollout status deployment/cargo-tracker -n cargo-tracker --timeout=5m

if !ERRORLEVEL! neq 0 (
    echo WARNING: Deployment rollout did not complete within timeout
    echo Check deployment status with: kubectl get pods -n cargo-tracker
) else (
    echo Deployment completed successfully
)

echo.

REM Verify deployment
echo ==========================================
echo Verifying deployment...
echo ==========================================
kubectl get pods,svc,ingress -n cargo-tracker

echo.

REM Get ingress URL
echo ==========================================
echo Application Access Information
echo ==========================================
for /f "delims=" %%i in ('kubectl get ingress cargo-tracker-ingress -n cargo-tracker -o jsonpath^="{.status.loadBalancer.ingress[0].hostname}" 2^>nul') do set INGRESS_ADDRESS=%%i
if "!INGRESS_ADDRESS!"=="" set INGRESS_ADDRESS=Pending...

echo Ingress Address: !INGRESS_ADDRESS!
echo.
echo Note: It may take a few minutes for the Load Balancer to be provisioned.
echo Once ready, access the application at: http://!INGRESS_ADDRESS!/cargo-tracker/
echo.

REM Cleanup temporary directory
rmdir /S /Q !TEMP_DIR!

echo ==========================================
echo Deployment Complete!
echo ==========================================
echo.
echo Useful commands:
echo   View pods:        kubectl get pods -n cargo-tracker
echo   View logs:        kubectl logs -f deployment/cargo-tracker -n cargo-tracker
echo   View services:    kubectl get svc -n cargo-tracker
echo   View ingress:     kubectl get ingress -n cargo-tracker
echo   Describe pod:     kubectl describe pod ^<pod-name^> -n cargo-tracker
echo.
echo To rollback deployment:
echo   kubectl rollout undo deployment/cargo-tracker -n cargo-tracker
echo ==========================================

endlocal
