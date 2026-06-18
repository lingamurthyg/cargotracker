@echo off
setlocal enabledelayedexpansion

echo ========================================
echo AWS EKS Deployment Script
echo Cargo Tracker Application
echo ========================================
echo.

set /p AWS_REGION="Enter AWS Region (e.g., us-east-1): "
if "!AWS_REGION!"=="" (
    echo ERROR: AWS Region is required
    exit /b 1
)

set /p CLUSTER_NAME="Enter EKS Cluster Name: "
if "!CLUSTER_NAME!"=="" (
    echo ERROR: EKS Cluster Name is required
    exit /b 1
)

set /p IMAGE_URI="Enter Docker Image URI: "
if "!IMAGE_URI!"=="" (
    echo ERROR: Docker Image URI is required
    exit /b 1
)

echo.
echo === Optional: Database Configuration ===
set /p DB_JDBC_URL="Enter Database JDBC URL (or press Enter to use default H2): "
if "!DB_JDBC_URL!"=="" set DB_JDBC_URL=jdbc:h2:file:/opt/payara/cargo-tracker-data/cargo-tracker-database

echo.
echo Configuration Summary:
echo   AWS Region: !AWS_REGION!
echo   EKS Cluster: !CLUSTER_NAME!
echo   Image URI: !IMAGE_URI!
echo   Database URL: !DB_JDBC_URL!
echo.
set /p CONFIRM="Continue with deployment? (y/n): "
if /i not "!CONFIRM!"=="y" (
    echo Deployment cancelled
    exit /b 0
)

echo.
echo ========================================
echo Step 1: Configure kubectl for EKS
echo ========================================
echo.

aws eks update-kubeconfig --region !AWS_REGION! --name !CLUSTER_NAME!

if !ERRORLEVEL! neq 0 (
    echo ERROR: Failed to configure kubectl
    exit /b 1
)

echo Verifying cluster connectivity...
kubectl cluster-info
if !ERRORLEVEL! neq 0 (
    echo ERROR: Cannot connect to cluster
    exit /b 1
)

echo.
echo ========================================
echo Step 2: Update Kubernetes Manifests
echo ========================================
echo.

set TMP_DIR=%TEMP%\cargo-tracker-deploy-%RANDOM%
mkdir !TMP_DIR!

xcopy /E /I /Y kubernetes !TMP_DIR! >nul

powershell -Command "(Get-Content '!TMP_DIR!\deployment.yaml') -replace '{{IMAGE_URI}}', '!IMAGE_URI!' | Set-Content '!TMP_DIR!\deployment.yaml'"
powershell -Command "(Get-Content '!TMP_DIR!\deployment.yaml') -replace '{{DB_JDBC_URL}}', '!DB_JDBC_URL!' | Set-Content '!TMP_DIR!\deployment.yaml'"

echo Manifests updated successfully

echo.
echo ========================================
echo Step 3: Apply Kubernetes Manifests
echo ========================================
echo.

echo Creating namespace...
kubectl apply -f !TMP_DIR!\namespace.yaml

echo.
echo Deploying application...
kubectl apply -f !TMP_DIR!\deployment.yaml

echo.
echo Creating service...
kubectl apply -f !TMP_DIR!\service.yaml

echo.
echo Creating ingress...
kubectl apply -f !TMP_DIR!\ingress.yaml

echo.
echo ========================================
echo Step 4: Wait for Deployment Rollout
echo ========================================
echo.

kubectl rollout status deployment/cargo-tracker -n cargo-tracker --timeout=5m

if !ERRORLEVEL! neq 0 (
    echo WARNING: Deployment rollout did not complete successfully
    echo Check pod status with: kubectl get pods -n cargo-tracker
)

echo.
echo ========================================
echo Step 5: Verify Deployment
echo ========================================
echo.

echo Pods:
kubectl get pods -n cargo-tracker -o wide

echo.
echo Services:
kubectl get svc -n cargo-tracker

echo.
echo Ingress:
kubectl get ingress -n cargo-tracker

echo.
echo ========================================
echo Deployment Complete!
echo ========================================
echo.

for /f "delims=" %%i in ('kubectl get ingress cargo-tracker-ingress -n cargo-tracker -o jsonpath="{.status.loadBalancer.ingress[0].hostname}" 2^>nul') do set INGRESS_URL=%%i

if not "!INGRESS_URL!"=="" (
    echo Application URL: http://!INGRESS_URL!/cargo-tracker/
) else (
    echo Ingress is being provisioned. Check status with:
    echo   kubectl get ingress -n cargo-tracker -w
)

echo.
echo Useful commands:
echo   View logs: kubectl logs -f deployment/cargo-tracker -n cargo-tracker
echo   Get pods: kubectl get pods -n cargo-tracker
    echo   Describe pod: kubectl describe pod ^<pod-name^> -n cargo-tracker
echo   Port forward: kubectl port-forward svc/cargo-tracker-service 8080:80 -n cargo-tracker
echo.

rmdir /S /Q !TMP_DIR!
endlocal