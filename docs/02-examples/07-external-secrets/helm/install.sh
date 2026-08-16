#!/usr/bin/env bash
# Plain Helm CLI install. Run from the example directory:
#   bash helm/install.sh
set -euo pipefail

cd "$(dirname "$0")/.."

helm upgrade --install secrets \
  oci://ghcr.io/purisev/universal-helm-chart \
  --version 3.0.0 \
  --namespace secrets \
  --create-namespace \
  -f values.yaml
