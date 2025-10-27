<#
.SYNOPSIS
  Apply an aws-auth mapping for a given IAM user and optionally create namespace-scoped RBAC for CI.

USAGE
  # run with defaults (values in this repo). Update parameters as needed
  ./scripts/apply-aws-auth.ps1

  # specify your real ARN explicitly
  ./scripts/apply-aws-auth.ps1 -IamUserArn 'arn:aws:iam::984649216408:user/Soda' -K8sUsername 'github-actions-kuber-todo' -Cluster 'final-disco-ladybug' -Region 'eu-west-1'

NOTES
  - This script uses a temporary aws-auth ConfigMap entry that gives the mapped user the `system:masters` group to verify authentication. After verification, remove the broad group and rely on the Role/RoleBinding created in k8s/rbac/. The script will apply the Role and RoleBinding from the repository.
  - Run this from a shell that already has AWS credentials configured and kubectl installed and working for the target cluster (or where `aws eks get-token` succeeds).
#>

param(
  [string]$IamUserArn = 'arn:aws:iam::984649216408:user/Soda',
  [string]$K8sUsername = 'github-actions-kuber-todo',
  [string]$Cluster = 'final-disco-ladybug',
  [string]$Region = 'eu-west-1',
  [switch]$UseEksctl
)

Write-Host "Running aws-auth apply script"
Write-Host "IAM ARN: $IamUserArn"
Write-Host "Kubernetes username: $K8sUsername"
Write-Host "Cluster: $Cluster (region: $Region)"

Write-Host "\n--- AWS caller identity ---"
aws sts get-caller-identity | ConvertTo-Json -Depth 4

Write-Host "\n--- Try to generate EKS token (aws eks get-token) ---"
try {
  aws eks get-token --cluster-name $Cluster --region $Region --output json | ConvertTo-Json -Depth 4
}
catch {
  Write-Error "Failed to generate token with aws eks get-token. Ensure AWS credentials allow eks:Access. Error: $_"
  exit 2
}

Write-Host "\n--- kubeconfig current-context ---"
kubectl config current-context

Write-Host "\n--- Preparing aws-auth ConfigMap (temporary mapping to system:masters for verification) ---"
$cm = @"
apiVersion: v1
kind: ConfigMap
metadata:
  name: aws-auth
  namespace: kube-system
data:
  mapUsers: |
    - userarn: $IamUserArn
      username: $K8sUsername
      groups:
        - system:masters
"@

Write-Host "Applying aws-auth (this will add/update the mapUsers entry)"
$cm | kubectl apply -f -

Write-Host "\n--- Verify aws-auth ConfigMap ---"
kubectl -n kube-system get configmap aws-auth -o yaml

Write-Host "\n--- Test basic kubectl operations as mapped user ---"
kubectl auth can-i create secrets -n kuber-todo || kubectl auth can-i create secrets -n default
kubectl get ns || true
kubectl get nodes || true

Write-Host "\n--- Applying namespace Role and RoleBinding for CI (k8s/rbac/) ---"
if (Test-Path "k8s/rbac/ci-role.yaml") {
  kubectl apply -f k8s/rbac/ci-role.yaml
}
else {
  Write-Warning "k8s/rbac/ci-role.yaml not found in repo"
}

if (Test-Path "k8s/rbac/ci-rolebinding.yaml") {
  kubectl apply -f k8s/rbac/ci-rolebinding.yaml
}
else {
  Write-Warning "k8s/rbac/ci-rolebinding.yaml not found in repo"
}

Write-Host "\nIf the above kubectl calls succeeded, the CI identity can authenticate. Remember to remove 'system:masters' in aws-auth and rely on the Role/RoleBinding for least privilege."
Write-Host "To remove the broad mapping, edit the aws-auth ConfigMap and remove or replace the mapUsers entry for $IamUserArn. Alternatively, use eksctl to create a role mapping and keep aws-auth minimal."

Write-Host "Done."
