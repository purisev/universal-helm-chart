#!/usr/bin/env bash
# Pushes a follow-up commit that only bumps commonAnnotations (a field the
# chart's job-group hash explicitly excludes) so ArgoCD detects a new
# revision and performs a real resync, without changing the identity of
# any hash-suffixed job. Proves resync idempotency: the job's name (and
# UID) must stay exactly the same across the resync.
#
# ArgoCD Core has no API server to receive a webhook, and its default
# git-polling interval is 3 minutes, so a plain push here wouldn't be
# picked up on any timescale this suite can wait for. Force an immediate
# refresh via the documented refresh annotation instead, which the
# Application Controller itself watches for.
set -euo pipefail

GITEA_USER="gitea_admin"
GITEA_PASSWORD='r8sA8CPHD9!bt6d'
REPO_NAME="universal-helm-chart"
MARKER="resync-$(date -u +%s)"

kubectl port-forward -n gitea svc/gitea-http 3000:3000 &
PORT_FORWARD_PID=$!
trap 'kill $PORT_FORWARD_PID; rm -rf "$CLONE_DIR"' EXIT

for i in $(seq 1 30); do
  if curl -s -o /dev/null "http://localhost:3000/api/v1/version"; then
    break
  fi
  sleep 2
done

CLONE_DIR=$(mktemp -d)
git clone --quiet "http://${GITEA_USER}:${GITEA_PASSWORD}@localhost:3000/${GITEA_USER}/${REPO_NAME}.git" "$CLONE_DIR"

sed -i "s/^commonAnnotations: {}/commonAnnotations:\n  resync-marker: \"${MARKER}\"/" \
  "$CLONE_DIR/test/e2e/values/argocd.yaml"

git -C "$CLONE_DIR" -c user.name="e2e" -c user.email="e2e@example.com" \
  commit -am "e2e: trigger resync (${MARKER})" --quiet
git -C "$CLONE_DIR" push --quiet origin main

kubectl patch application e2e-app -n argocd --type merge \
  -p '{"metadata":{"annotations":{"argocd.argoproj.io/refresh":"hard"}}}'

echo "marker=${MARKER}"
