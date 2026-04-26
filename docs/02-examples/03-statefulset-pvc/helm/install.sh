#!/usr/bin/env bash
# Plain Helm CLI install. Run from the example directory:
#   bash helm/install.sh
#
# Pre-requisite: the db-credentials Secret must exist in the namespace.
# See README.md → "Try it" for the kubectl create secret command.
set -euo pipefail

cd "$(dirname "$0")/.."

helm upgrade --install stateful \
  oci://ghcr.io/purisev/universal-helm-chart \
  --version 2.0.0 \
  --namespace stateful \
  --create-namespace \
  -f values.yaml
