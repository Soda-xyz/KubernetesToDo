<#
.\scripts\attach-ecr-policy.ps1

Idempotent helper to attach AmazonEC2ContainerRegistryReadOnly to EKS nodegroup IAM roles.
Usage:
  # Dry-run (shows actions)
  pwsh .\scripts\attach-ecr-policy.ps1 -Cluster final-disco-ladybug -Region eu-west-1

  # Apply changes
  pwsh .\scripts\attach-ecr-policy.ps1 -Cluster final-disco-ladybug -Region eu-west-1 -Apply

Notes:
- Works with managed nodegroups. If you use Fargate, there is no node role to attach and the script will warn.
- Requires `aws` CLI on PATH and credentials with iam:AttachRolePolicy / eks:DescribeNodegroup permissions.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Cluster,

    [Parameter(Mandatory = $true)]
    [string]$Region = 'eu-west-1',

    [Parameter(Mandatory = $false)]
    [string]$NodeGroupName,

    [switch]$Apply
)

function Show-ErrorAndExit($msg) {
    Write-Error $msg
    exit 2
}

# Check aws
try { Get-Command aws -ErrorAction Stop | Out-Null } catch { Show-ErrorAndExit "aws CLI not found in PATH" }

Write-Host "Cluster: $Cluster  Region: $Region  NodeGroup: ${NodeGroupName:-<all>}  Apply: $($Apply.IsPresent)"

# Gather nodegroups
if ($NodeGroupName) {
    $nodegroups = @($NodeGroupName)
}
else {
    $list = aws eks list-nodegroups --cluster-name $Cluster --region $Region --output json | ConvertFrom-Json
    $nodegroups = $list.nodegroups
}

if (-not $nodegroups -or $nodegroups.Count -eq 0) {
    Write-Warning "No managed nodegroups found for cluster $Cluster. If you are using Fargate or self-managed nodes, handle role attachment manually."
    exit 0
}

$policyArn = 'arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly'

$rolesToAttach = @{}
foreach ($ng in $nodegroups) {
    Write-Host "Inspecting nodegroup: $ng"
    $desc = aws eks describe-nodegroup --cluster-name $Cluster --nodegroup-name $ng --region $Region --output json | ConvertFrom-Json
    $nodeRoleArn = $desc.nodegroup.nodeRole
    if (-not $nodeRoleArn) { Write-Warning "Nodegroup $ng has no nodeRole (maybe Fargate or error). Skipping."; continue }
    $roleName = $nodeRoleArn.Split('/')[-1]
    $rolesToAttach[$roleName] = $nodeRoleArn
}

if ($rolesToAttach.Count -eq 0) { Write-Warning "No node roles discovered. Exiting."; exit 0 }

Write-Host "Found node roles:`n$($rolesToAttach.Keys -join "`n")`n"

foreach ($role in $rolesToAttach.Keys) {
    Write-Host "Checking role: $role"
    $attached = aws iam list-attached-role-policies --role-name $role --query "AttachedPolicies[?PolicyArn=='$policyArn']" --output json | ConvertFrom-Json
    if ($attached -and $attached.Count -gt 0) {
        Write-Host "Policy already attached to $role"
        continue
    }
    if ($Apply.IsPresent) {
        Write-Host "Attaching $policyArn to $role"
        aws iam attach-role-policy --role-name $role --policy-arn $policyArn
        if ($LASTEXITCODE -ne 0) { Write-Warning "Failed to attach policy to $role" }
        else { Write-Host "Attached policy to $role" }
    }
    else {
        Write-Host "Would attach $policyArn to $role (run with -Apply to perform)"
    }
}

if ($Apply.IsPresent) {
    Write-Host "
Optional: quick runtime test - create a short-lived test pod that references your ECR image to verify node can pull it. Replace placeholders and run manually if desired."
    Write-Host "kubectl run test-ecr-pod --image='<AWS_ACCOUNT_ID>.dkr.ecr.<REGION>.amazonaws.com/<repo>:<tag>' --restart=Never --image-pull-policy=IfNotPresent"
}

Write-Host "Done."
