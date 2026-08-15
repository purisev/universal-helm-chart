#!/usr/bin/env bash
# Pushes two tags of a real public image into the in-cluster NORA registry
# under a single image name, so argocd-image-updater's semver strategy has
# a real newer version to discover starting from the older tag the chart's
# ImageUpdater CR is configured with.
set -euo pipefail

kubectl port-forward -n nora svc/nora 4000:4000 &
PORT_FORWARD_PID=$!
trap 'kill $PORT_FORWARD_PID' EXIT

for i in $(seq 1 30); do
  if curl -s -o /dev/null "http://localhost:4000/v2/"; then
    break
  fi
  sleep 2
done

crane copy --insecure busybox:1.36 localhost:4000/test-image:1.0.0
crane copy --insecure busybox:1.36 localhost:4000/test-image:1.1.0
