#!/usr/bin/env bash
set -euo pipefail

# Environment variables expected:
# ARGO_APP_NAME, ARGO_NAMESPACE, REGISTRY, REPO, TAG, SECRET_NAME, K8S_NAMESPACE

ARGO_APP_NAME="${ARGO_APP_NAME:-kuber-todo}"
ARGO_NAMESPACE="${ARGO_NAMESPACE:-argocd}"
REGISTRY="${REGISTRY:?REGISTRY not set}"
REPO="${REPO:?REPO not set}"
TAG="${TAG:?TAG not set}"
SECRET_NAME="${SECRET_NAME:-kuber-todo-mongodb-root}"
K8S_NAMESPACE="${K8S_NAMESPACE:-kuber-todo}"

# Build helm.values YAML
VALUES=$(cat <<EOF
mongodb:
  rootPasswordSecretName: "${SECRET_NAME}"
  rootPasswordKey: "root-password"
image:
  repository: "${REGISTRY}/${REPO}"
  tag: "${TAG}"
EOF
)

# Convert to JSON patch payload safely using Python
PATCH_JSON=$(printf '%s' "$VALUES" | python3 -c 'import sys,json; v=sys.stdin.read(); print(json.dumps({"spec":{"source":{"helm":{"values":v}}}}))')

# Apply patch
kubectl -n "${ARGO_NAMESPACE}" patch application "${ARGO_APP_NAME}" --type merge -p "${PATCH_JSON}"
