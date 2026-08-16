#!/usr/bin/env bash
# Plain Helm CLI install — DRY-RUN BY DEFAULT.
# This example exercises the chart's full surface and assumes a lot of CRDs are present.
# Read README.md → "Prerequisites (CRDs)" before removing --dry-run.
#
#   bash helm/install.sh                    # render only (no apply)
#   bash helm/install.sh --apply            # actually install (drops --dry-run)
set -euo pipefail

cd "$(dirname "$0")/.."

DRY_RUN_FLAGS=(--dry-run=server --debug)
if [[ "${1:-}" == "--apply" ]]; then
  DRY_RUN_FLAGS=()
fi

helm upgrade --install kitchen-sink \
  oci://ghcr.io/purisev/universal-helm-chart \
  --version 3.0.0 \
  --namespace kitchen-sink \
  --create-namespace \
  -f values.yaml \
  "${DRY_RUN_FLAGS[@]}"
