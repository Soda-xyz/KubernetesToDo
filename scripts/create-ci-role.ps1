<#
Create-CI-Role.ps1
Scaffolded helper script to create an IAM role for GitHub Actions OIDC, attach a CI policy, map role into EKS via eksctl, and apply namespace RBAC.

Safety defaults:
- Dry-run by default. Use -Apply to perform changes and -Yes to skip confirmation prompts.
- Writes expanded trust policy to iam/github-oidc-trust-policy.json for audit.
- Does not persist secrets or credentials.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$AwsAccountId,

    [Parameter(Mandatory = $true)]
    [string]$Region,

    [Parameter(Mandatory = $true)]
    [string]$GithubOwner,

    [Parameter(Mandatory = $true)]
    [string]$GithubRepo,

    [Parameter(Mandatory = $true)]
    [string]$GithubBranch,

    [Parameter(Mandatory = $true)]
    [string]$RoleName,

    [Parameter(Mandatory = $true)]
    [string]$ClusterName,

    [switch]$Apply,
    [switch]$Yes
)

function Test-Tool {
    param([string]$name, [string]$cmd)
    try {
        $null = Get-Command $cmd -ErrorAction Stop
        return $true
    }
    catch {
        Write-Warning "$name not found in PATH."
        return $false
    }
}

Write-Host "Starting create-ci-role.ps1 (dry-run unless -Apply provided)"

# Prereq checks
$missing = @()
if (-not (Test-Tool -name 'aws' -cmd 'aws')) { $missing += 'aws' }
if (-not (Test-Tool -name 'eksctl' -cmd 'eksctl')) { $missing += 'eksctl' }
if (-not (Test-Tool -name 'kubectl' -cmd 'kubectl')) { $missing += 'kubectl' }
if ($missing.Count -gt 0) {
    Write-Error "Missing required tools: $($missing -join ', '). Install them and re-run the script."
    exit 2
}

# Build the trust policy
$tplPath = Join-Path $PSScriptRoot '..\iam\github-oidc-trust-policy.json.template' -Resolve
if (-not (Test-Path $tplPath)) {
    Write-Error "Trust policy template not found at $tplPath"
    exit 3
}

$tpl = Get-Content $tplPath -Raw
$tpl = $tpl -replace '\$\{AWS_ACCOUNT_ID\}', $AwsAccountId
$tpl = $tpl -replace '\$\{GITHUB_OWNER\}', $GithubOwner
$tpl = $tpl -replace '\$\{GITHUB_REPO\}', $GithubRepo
$tpl = $tpl -replace '\$\{GITHUB_BRANCH\}', $GithubBranch

$outTrustPath = Join-Path $PSScriptRoot '..\iam\github-oidc-trust-policy.json' -Resolve
Write-Host "Writing expanded trust policy to: $outTrustPath"
Set-Content -Path $outTrustPath -Value $tpl -Encoding utf8

# Prepare commands
$roleArn = "arn:aws:iam::${AwsAccountId}:role/$RoleName"

$ciPolicyPath = Join-Path $PSScriptRoot '..\iam\ci-role-policy.json' -Resolve

Write-Host "----- DRY RUN: The following actions will be performed if you run with -Apply -----"
Write-Host "1) Ensure IAM role exists: $RoleName"
Write-Host "2) Attach inline policy: $ciPolicyPath"
Write-Host "3) Create eks identity mapping for cluster: $ClusterName"
Write-Host "4) Apply Kubernetes RBAC manifests (ci-role/rolebinding)"
Write-Host "--------------------------------------------------------------------------"

if (-not $Apply) {
    Write-Host "Dry-run mode: no changes will be applied. Rerun with -Apply -Yes to execute the actions."
    exit 0
}

if (-not $Yes) {
    $confirm = Read-Host "Are you sure you want to apply these changes? Type 'yes' to continue"
    if ($confirm -ne 'yes') { Write-Host 'Aborting.'; exit 0 }
}

## 1) Ensure IAM role exists (create if missing)
Write-Host "Checking for existing role: $RoleName"
& aws iam get-role --role-name $RoleName > $null 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host "Role not found; creating role $RoleName"
    & aws iam create-role --role-name $RoleName --assume-role-policy-document file://$outTrustPath --description 'GitHub Actions OIDC role for KubernetesToDo CI'
    if ($LASTEXITCODE -ne 0) { Write-Warning "Failed to create role $RoleName" }
}
else { Write-Host "Role $RoleName already exists" }

## 2) Attach/put inline policy
Write-Host "Attaching inline policy to $RoleName from $ciPolicyPath"
& aws iam put-role-policy --role-name $RoleName --policy-name GitHubActionsCIInlinePolicy --policy-document file://$ciPolicyPath
if ($LASTEXITCODE -ne 0) { Write-Warning "Failed to attach inline policy to $RoleName" }

## 3) Create eks identity mapping
Write-Host "Creating IAM identity mapping in cluster $ClusterName (eksctl)"
& eksctl create iamidentitymapping --cluster $ClusterName --region $Region --arn $roleArn --username github-actions-kuber-todo --group system:masters
if ($LASTEXITCODE -ne 0) { Write-Warning "eksctl create iamidentitymapping may have failed or mapping already exists" }

## 4) Apply Kubernetes RBAC
Write-Host "Applying Kubernetes RBAC manifests"
& kubectl apply -f (Join-Path $PSScriptRoot '..\k8s\rbac\ci-role.yaml' -Resolve)
if ($LASTEXITCODE -ne 0) { Write-Warning "kubectl apply ci-role.yaml failed" }
& kubectl apply -f (Join-Path $PSScriptRoot '..\k8s\rbac\ci-rolebinding.yaml' -Resolve)
if ($LASTEXITCODE -ne 0) { Write-Warning "kubectl apply ci-rolebinding.yaml failed" }

# Write an audit file
$audit = @{
    roleArn      = $roleArn
    appliedAt    = (Get-Date).ToString('u')
    awsAccountId = $AwsAccountId
    cluster      = $ClusterName
}
$auditPath = Join-Path $PSScriptRoot '..\localfiles\ci-role-created.json' -Resolve
$audit | ConvertTo-Json | Set-Content -Path $auditPath -Encoding utf8
Write-Host "Applied. Audit written to $auditPath"

Write-Host "Recommended verification commands:"
Write-Host "  aws sts get-caller-identity"
Write-Host "  kubectl auth can-i create secrets -n kuber-todo"
