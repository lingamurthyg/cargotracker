@echo off
setlocal enabledelayedexpansion

echo ==========================================
echo AWS EKS Deployment Script
echo ==========================================
echo.

REM Prompt for AWS configuration
set /p AWS_REGION="Enter AWS Region (e.g., us-east-1): "
set /p CLUSTER_NAME="Enter EKS Cluster Name: "
set /p IMAGE_URI="Enter Docker Image URI (full path with tag): "

if "!AWS_REGION!"=="" (
    echo ERROR: AWS Region is required
    exit /b 1
)
if "!CLUSTER_NAME!"=="" (
    echo ERROR: EKS Cluster Name is required
    exit /b 1
)
if "!IMAGE_URI!"=="" (
    echo ERROR: Docker Image URI is required
    exit /b 1
)

echo.
echo === Optional Environment Variables ===
echo Press Enter to skip any optional configuration
echo.

REM Optional database configuration
set /p DB_DRIVER_CLASS="Enter Database Driver Class (or press Enter to skip): "
set /p DB_JDBC_URL="Enter Database JDBC URL (or press Enter to skip): "
set /p DB_USER="Enter Database User (or press Enter to skip): "
set /p DB_PASSWORD="Enter Database Password (or press Enter to skip): "

echo.
echo ==========================================
echo Configuring kubectl for EKS
echo ==========================================
echo.

REM Configure kubectl to use EKS cluster
aws eks update-kubeconfig --region !AWS_REGION! --name !CLUSTER_NAME!

if !ERRORLEVEL! neq 0 (
    echo ERROR: Failed to configure kubectl for EKS cluster
    exit /b 1
)

REM Verify cluster connectivity
echo Verifying cluster connectivity...
kubectl cluster-info
if !ERRORLEVEL! neq 0 (
    echo ERROR: Cannot connect to Kubernetes cluster
    exit /b 1
)

echo.
echo ==========================================
echo Updating Kubernetes Manifests
echo ==========================================
echo.

REM Create temporary directory for modified manifests
set TEMP_DIR=%TEMP%\k8s-deploy-%RANDOM%
mkdir "!TEMP_DIR!"
xcopy /E /I /Q kubernetes "!TEMP_DIR!" >nul

REM Replace IMAGE_URI placeholder using PowerShell
echo Updating image URI...
powershell -Command "(Get-Content '!TEMP_DIR!\deployment.yaml') -replace '{{IMAGE_URI}}', '!IMAGE_URI!' | Set-Content '!TEMP_DIR!\deployment.yaml'"

REM Replace optional database configuration if provided
if not "!DB_DRIVER_CLASS!"=="" (
    echo Updating database driver class...
    powershell -Command "(Get-Content '!TEMP_DIR!\deployment.yaml') -replace '{{DB_DRIVER_CLASS}}', '!DB_DRIVER_CLASS!' | Set-Content '!TEMP_DIR!\deployment.yaml'"
)

if not "!DB_JDBC_URL!"=="" (
    echo Updating database JDBC URL...
    powershell -Command "(Get-Content '!TEMP_DIR!\deployment.yaml') -replace '{{DB_JDBC_URL}}', '!DB_JDBC_URL!' | Set-Content '!TEMP_DIR!\deployment.yaml'"
)

if not "!DB_USER!"=="" (
    echo Updating database user...
    powershell -Command "(Get-Content '!TEMP_DIR!\deployment.yaml') -replace '{{DB_USER}}', '!DB_USER!' | Set-Content '!TEMP_DIR!\deployment.yaml'"
)

REM Create database secret if password provided
if not "!DB_PASSWORD!"=="" (
    echo Creating database secret...
    kubectl create secret generic cargo-tracker-db-secret --from-literal=password="!DB_PASSWORD!" --namespace=cargo-tracker --dry-run=client -o yaml | kubectl apply -f -
)

echo.
echo ==========================================
echo Deploying to AWS EKS
echo ==========================================
echo.

REM Apply Kubernetes manifests in order
echo Creating namespace...
kubectl apply -f "!TEMP_DIR!\namespace.yaml"

echo Deploying application...
kubectl apply -f "!TEMP_DIR!\deployment.yaml"

echo Creating service...
kubectl apply -f "!TEMP_DIR!\service.yaml"

echo Creating ingress...
kubectl apply -f "!TEMP_DIR!\ingress.yaml"

echo.
echo Waiting for deployment to complete...
kubectl rollout status deployment/cargo-tracker -n cargo-tracker --timeout=5m

if !ERRORLEVEL! neq 0 (
    echo WARNING: Deployment rollout did not complete within timeout
    echo Check deployment status with: kubectl get pods -n cargo-tracker
)

echo.
echo ==========================================
echo Deployment Status
echo ==========================================
echo.

REM Display deployment status
kubectl get pods,svc,ingress -n cargo-tracker

echo.
echo ==========================================
echo Application Access Information
echo ==========================================
echo.

REM Get ingress URL
for /f "tokens=*" %%i in ('kubectl get ingress cargo-tracker-ingress -n cargo-tracker -o jsonpath^="{.status.loadBalancer.ingress[0].hostname}" 2^>nul') do set INGRESS_URL=%%i

if not "!INGRESS_URL!"=="" (
    echo Application URL: http://!INGRESS_URL!/cargo-tracker/
    echo.
    echo Note: It may take a few minutes for the Load Balancer to become available.
) else (
    echo Ingress is being provisioned. Check status with:
    echo kubectl get ingress -n cargo-tracker
)

echo.
echo ==========================================
echo Useful Commands
echo ==========================================
echo.
echo View logs:           kubectl logs -f deployment/cargo-tracker -n cargo-tracker
echo View pods:           kubectl get pods -n cargo-tracker
echo Describe pod:        kubectl describe pod ^<pod-name^> -n cargo-tracker
echo Scale deployment:    kubectl scale deployment/cargo-tracker --replicas=3 -n cargo-tracker
echo Delete deployment:   kubectl delete namespace cargo-tracker
echo.

REM Cleanup temporary directory
rmdir /S /Q "!TEMP_DIR!"

echo Deployment completed successfully!
echo.

endlocal
