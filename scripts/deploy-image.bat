@echo off
setlocal enabledelayedexpansion

echo =====================================
echo AWS EKS Deployment Script
echo Cargo Tracker Application
echo =====================================

echo.
echo === AWS EKS Configuration ===
set /p AWS_REGION="Enter AWS Region (e.g., us-east-1): "
set /p CLUSTER_NAME="Enter EKS Cluster Name: "

if "!AWS_REGION!"=="" (
    echo Error: AWS Region is required
    exit /b 1
)

if "!CLUSTER_NAME!"=="" (
    echo Error: EKS Cluster Name is required
    exit /b 1
)

echo.
echo === Docker Image Configuration ===
set /p IMAGE_URI="Enter Docker Image URI (with tag): "

if "!IMAGE_URI!"=="" (
    echo Error: Docker Image URI is required
    exit /b 1
)

echo.
echo === Application Configuration ===
echo Configure environment variables (press Enter to use defaults)

set /p DB_URL="Enter Database URL [jdbc:h2:mem:testdb;DB_CLOSE_DELAY=-1]: "
if "!DB_URL!"=="" set DB_URL=jdbc:h2:mem:testdb;DB_CLOSE_DELAY=-1

set /p DB_USER="Enter Database User [sa]: "
if "!DB_USER!"=="" set DB_USER=sa

set /p DB_PASSWORD="Enter Database Password [empty]: "
if "!DB_PASSWORD!"=="" set DB_PASSWORD=

set /p TIMER_DB_URL="Enter Timer Database URL [jdbc:h2:mem:timerdb;DB_CLOSE_DELAY=-1]: "
if "!TIMER_DB_URL!"=="" set TIMER_DB_URL=jdbc:h2:mem:timerdb;DB_CLOSE_DELAY=-1

set /p TIMER_DB_USER="Enter Timer Database User [sa]: "
if "!TIMER_DB_USER!"=="" set TIMER_DB_USER=sa

set /p TIMER_DB_PASSWORD="Enter Timer Database Password [empty]: "
if "!TIMER_DB_PASSWORD!"=="" set TIMER_DB_PASSWORD=

set /p GRAPH_TRAVERSAL_URL="Enter Graph Traversal URL [http://localhost:8080/graph-traversal/]: "
if "!GRAPH_TRAVERSAL_URL!"=="" set GRAPH_TRAVERSAL_URL=http://localhost:8080/graph-traversal/

set /p ADMIN_USER="Enter Admin User [admin]: "
if "!ADMIN_USER!"=="" set ADMIN_USER=admin

set /p ADMIN_PASSWORD="Enter Admin Password [admin]: "
if "!ADMIN_PASSWORD!"=="" set ADMIN_PASSWORD=admin

echo.
echo =====================================
echo Configuring kubectl for EKS...
echo =====================================

aws eks update-kubeconfig --region !AWS_REGION! --name !CLUSTER_NAME!

if !ERRORLEVEL! neq 0 (
    echo Error: Failed to configure kubectl for EKS cluster
    exit /b 1
)

echo.
echo Verifying cluster connectivity...
kubectl cluster-info

if !ERRORLEVEL! neq 0 (
    echo Error: Unable to connect to Kubernetes cluster
    exit /b 1
)

echo.
echo =====================================
echo Updating Kubernetes manifests...
echo =====================================

set MANIFEST_DIR=kubernetes

if not exist "!MANIFEST_DIR!" (
    echo Error: Kubernetes manifests directory not found: !MANIFEST_DIR!
    exit /b 1
)

set TMP_DIR=%TEMP%\k8s-manifests-%RANDOM%
mkdir "!TMP_DIR!"

xcopy /Y "!MANIFEST_DIR!\*" "!TMP_DIR!\"

for %%f in ("!TMP_DIR!\*.yaml") do (
    powershell -Command "(Get-Content '%%f') -replace '{{IMAGE_URI}}', '!IMAGE_URI!' ^| Set-Content '%%f'"
    powershell -Command "(Get-Content '%%f') -replace '{{DB_URL}}', '!DB_URL!' ^| Set-Content '%%f'"
    powershell -Command "(Get-Content '%%f') -replace '{{DB_USER}}', '!DB_USER!' ^| Set-Content '%%f'"
    powershell -Command "(Get-Content '%%f') -replace '{{TIMER_DB_URL}}', '!TIMER_DB_URL!' ^| Set-Content '%%f'"
    powershell -Command "(Get-Content '%%f') -replace '{{TIMER_DB_USER}}', '!TIMER_DB_USER!' ^| Set-Content '%%f'"
    powershell -Command "(Get-Content '%%f') -replace '{{GRAPH_TRAVERSAL_URL}}', '!GRAPH_TRAVERSAL_URL!' ^| Set-Content '%%f'"
    powershell -Command "(Get-Content '%%f') -replace '{{ADMIN_USER}}', '!ADMIN_USER!' ^| Set-Content '%%f'"
)

echo.
echo Creating Kubernetes secrets...
kubectl create namespace cargo-tracker --dry-run=client -o yaml | kubectl apply -f -

kubectl create secret generic cargo-tracker-secrets --from-literal=db-password="!DB_PASSWORD!" --from-literal=timer-db-password="!TIMER_DB_PASSWORD!" --from-literal=admin-password="!ADMIN_PASSWORD!" --namespace=cargo-tracker --dry-run=client -o yaml | kubectl apply -f -

echo.
echo =====================================
echo Deploying to Kubernetes...
echo =====================================

echo Applying namespace...
kubectl apply -f "!TMP_DIR!\namespace.yaml"

echo Applying deployment...
kubectl apply -f "!TMP_DIR!\deployment.yaml"

echo Applying service...
kubectl apply -f "!TMP_DIR!\service.yaml"

echo Applying ingress...
kubectl apply -f "!TMP_DIR!\ingress.yaml"

echo.
echo =====================================
echo Waiting for deployment to complete...
echo =====================================

kubectl rollout status deployment/cargo-tracker -n cargo-tracker --timeout=300s

if !ERRORLEVEL! neq 0 (
    echo Error: Deployment rollout failed or timed out
    echo Check pod status with: kubectl get pods -n cargo-tracker
    echo Check logs with: kubectl logs -n cargo-tracker -l app=cargo-tracker
    rmdir /S /Q "!TMP_DIR!"
    exit /b 1
)

echo.
echo =====================================
echo Verifying deployment...
echo =====================================

kubectl get pods,svc,ingress -n cargo-tracker

echo.
echo =====================================
echo Deployment Complete!
echo =====================================

for /f "delims=" %%i in ('kubectl get ingress cargo-tracker-ingress -n cargo-tracker -o jsonpath="{.status.loadBalancer.ingress[0].hostname}" 2^>nul') do set INGRESS_ADDRESS=%%i

if not "!INGRESS_ADDRESS!"=="" (
    echo Application URL: http://!INGRESS_ADDRESS!/cargo-tracker/
) else (
    echo Ingress is being provisioned. Check status with:
    echo kubectl get ingress cargo-tracker-ingress -n cargo-tracker
)

echo.
echo Useful commands:
echo   View pods:        kubectl get pods -n cargo-tracker
echo   View logs:        kubectl logs -n cargo-tracker -l app=cargo-tracker
echo   View services:    kubectl get svc -n cargo-tracker
echo   View ingress:     kubectl get ingress -n cargo-tracker
echo   Delete deployment: kubectl delete namespace cargo-tracker
echo.
echo =====================================

rmdir /S /Q "!TMP_DIR!"

endlocal