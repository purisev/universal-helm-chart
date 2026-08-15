#!/usr/bin/env bash
# Pushes the current repo's checked-out commit to the in-cluster Gitea
# instance, so the ArgoCD repo-server (which runs inside the kind cluster
# and can't see the CI runner's filesystem) has a real git source to clone.
# Port-forwards Gitea to the runner only for the duration of the push.
set -euo pipefail

GITEA_USER="gitea_admin"
GITEA_PASSWORD='r8sA8CPHD9!bt6d'
REPO_NAME="universal-helm-chart"

kubectl port-forward -n gitea svc/gitea-http 3000:3000 &
PORT_FORWARD_PID=$!
trap 'kill $PORT_FORWARD_PID' EXIT

for i in $(seq 1 30); do
  if curl -s -o /dev/null "http://localhost:3000/api/v1/version"; then
    break
  fi
  sleep 2
done

curl -s -o /dev/null -u "${GITEA_USER}:${GITEA_PASSWORD}" \
  -X POST "http://localhost:3000/api/v1/user/repos" \
  -H "Content-Type: application/json" \
  -d "{\"name\":\"${REPO_NAME}\",\"private\":false,\"auto_init\":false}"

git -c user.name="e2e" -c user.email="e2e@example.com" \
  push --force "http://${GITEA_USER}:${GITEA_PASSWORD}@localhost:3000/${GITEA_USER}/${REPO_NAME}.git" \
  "HEAD:refs/heads/main"
