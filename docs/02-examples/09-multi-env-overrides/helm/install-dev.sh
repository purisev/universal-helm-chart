#!/usr/bin/env bash
# Plain Helm CLI install — dev environment.
# Pattern: -f base.yaml -f <env>.yaml. Later -f files win on key collision.
#
#   bash helm/install-dev.sh
#
# For staging / prod, copy this and adjust release name + values overlay.
set -euo pipefail

cd "$(dirname "$0")/.."

helm upgrade --install orders-dev \
  oci://ghcr.io/purisev/universal-helm-chart \
  --version 2.0.0 \
  --namespace orders-dev \
  --create-namespace \
  -f values-base.yaml \
  -f values-dev.yaml
