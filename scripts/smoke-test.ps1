# Minimal smoke-test for KubernetesToDo deployment (PowerShell).
# Waits for ArgoCD Application to be Synced+Healthy, waits for pods in the app namespace to be Running,
# then performs simple HTTP GET checks against the Ingress LoadBalancer using the Host header.

param(
    [string]$Namespace = 'kuber-todo',
    [string]$ArgoAppName = 'kuber-todo',
    [Parameter(Mandatory = $true)][string]$IngressHost,
    [int]$TimeoutSeconds = 300
)

function Fail([string]$msg, [int]$code = 1) {
    Write-Host "ERROR: $msg" -ForegroundColor Red
    exit $code
}

function Wait-ForArgoApp {
    Write-Host "Waiting for ArgoCD Application '$ArgoAppName' to be Synced and Healthy (timeout: $TimeoutSeconds s)..."
    $end = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $end) {
        $sync = kubectl -n argocd get applications.argoproj.io $ArgoAppName -o jsonpath='{.status.sync.status}' 2>$null
        $health = kubectl -n argocd get applications.argoproj.io $ArgoAppName -o jsonpath='{.status.health.status}' 2>$null
        if ($sync -eq 'Synced' -and $health -eq 'Healthy') {
            Write-Host "ArgoCD Application is Synced and Healthy."
            return $true
        }
        Start-Sleep -Seconds 5
    }
    return $false
}

function Wait-ForPodsRunning {
    Write-Host "Waiting for pods in namespace '$Namespace' to be Running (timeout: $TimeoutSeconds s)..."
    $end = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $end) {
        $pods = kubectl -n $Namespace get pods --no-headers 2>$null
        if (-not $pods) {
            Start-Sleep -Seconds 3; continue
        }
        $allRunning = $true
        $lines = $pods -split "`n"
        foreach ($l in $lines) {
            if ([string]::IsNullOrWhiteSpace($l)) { continue }
            $cols = $l -split '\s+' | Where-Object { $_ -ne '' }
            $status = $cols[2]
            if ($status -ne 'Running') { $allRunning = $false; break }
        }
        if ($allRunning) { Write-Host "All pods are Running."; return $true }
        Start-Sleep -Seconds 5
    }
    return $false
}

function Get-LBHostFromIngress {
    $ingressHost = kubectl -n $Namespace get ingress -l app.kubernetes.io/component=ingress -o jsonpath='{.items[0].status.loadBalancer.ingress[0].hostname}' 2>$null
    if (-not [string]::IsNullOrWhiteSpace($ingressHost)) { return $ingressHost }
    $ingressHost = kubectl -n $Namespace get ingress -o jsonpath='{.items[0].status.loadBalancer.ingress[0].hostname}' 2>$null
    if (-not [string]::IsNullOrWhiteSpace($ingressHost)) { return $ingressHost }
    $svc = kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>$null
    return $svc
}

function Invoke-HttpCheck {
    param([string]$lbHost, [string]$path = '/')
    $uri = "http://$lbHost$path"
    Write-Host "Checking $uri with Host header '$IngressHost'..."
    try {
        $resp = Invoke-WebRequest -Uri $uri -Headers @{ Host = $IngressHost } -UseBasicParsing -TimeoutSec 15
        Write-Host "HTTP $($resp.StatusCode)"
        return $resp.StatusCode -ge 200 -and $resp.StatusCode -lt 400
    }
    catch {
        Write-Host "Request failed: $($_.Exception.Message)"
        return $false
    }
}

if (-not (Wait-ForArgoApp)) { Fail "ArgoCD Application did not become Synced+Healthy within timeout." }
if (-not (Wait-ForPodsRunning)) { Fail "Not all pods entered Running state within timeout." }

$lbHost = Get-LBHostFromIngress
if ([string]::IsNullOrWhiteSpace($lbHost)) { Fail "Could not determine Load Balancer hostname from Ingress or ingress-nginx service." }

Write-Host "Detected Load Balancer host: $lbHost"

$rootOk = Invoke-HttpCheck -lbHost $lbHost -path '/'
$apiOk = Invoke-HttpCheck -lbHost $lbHost -path '/api/todo'

if ($rootOk -and $apiOk) {
    Write-Host "Smoke-test passed: root and API endpoints returned successful responses." -ForegroundColor Green
    exit 0
}
else {
    Write-Host "Smoke-test FAILED: some endpoints failed." -ForegroundColor Red
    exit 2
}
