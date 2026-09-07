#!/usr/bin/env bash
#
# Every example under docs/02-examples/ has to render against the chart in this
# tree. Two kinds of values are checked:
#
#   1. The values files a reader copies. A directory holding values-base.yaml
#      renders base plus each overlay, the way its install script does; every
#      other directory renders each values file on its own.
#   2. The same values inlined into the Argo CD Application (helm.values) and
#      the Flux HelmRelease (spec.values) next to them. They are hand-kept
#      copies of the values file and drift from it otherwise. A HelmRelease
#      that declares valuesFrom carries only an overlay inline, so it renders
#      over values-base.yaml the way Flux merges it at apply time.
#
# The multi-source Applications point at the values files by path instead of
# inlining them, so checking the files covers those too.
#
# Needs helm and yq. Run it the same way CI does:
#   bash .github/scripts/check-examples.sh

set -euo pipefail

cd "$(dirname "$0")/../.."

for tool in helm yq; do
  command -v "${tool}" >/dev/null || { echo "${tool} is required to run this check" >&2; exit 1; }
done

tmp=$(mktemp -d)
trap 'rm -rf "${tmp}"' EXIT

status=0
checked=0

render() {
  local label=$1
  shift
  checked=$((checked + 1))
  local out
  if out=$(helm template example . "$@" 2>&1); then
    return 0
  fi
  echo "${label}"
  printf '%s\n' "${out}" | sed 's/^/  /'
  echo
  status=1
}

inline_values='[.. | select(tag == "!!map") | select(has("helm")) | .helm.values | select(. != null)]'

for dir in docs/02-examples/*/; do
  if [[ -f "${dir}values-base.yaml" ]]; then
    for overlay in "${dir}"values-*.yaml; do
      [[ "${overlay}" == "${dir}values-base.yaml" ]] && continue
      render "${overlay} (over values-base.yaml)" -f "${dir}values-base.yaml" -f "${overlay}"
    done
  else
    for values in "${dir}"values*.yaml; do
      [[ -f "${values}" ]] || continue
      render "${values}" -f "${values}"
    done
  fi

  for manifest in "${dir}"argocd/*.yaml "${dir}"flux/*.yaml; do
    [[ -f "${manifest}" ]] || continue

    base=()
    if [[ -f "${dir}values-base.yaml" ]] &&
       [[ $(yq "[.. | select(tag == \"!!map\") | .valuesFrom | select(. != null)] | length" "${manifest}") -gt 0 ]]; then
      base=(-f "${dir}values-base.yaml")
    fi

    count=$(yq "${inline_values} | length" "${manifest}")
    for ((i = 0; i < count; i++)); do
      yq -r "${inline_values} | .[${i}]" "${manifest}" > "${tmp}/inline.yaml"
      render "${manifest} (helm.values)" "${base[@]}" -f "${tmp}/inline.yaml"
    done

    if [[ $(yq "[select(.kind == \"HelmRelease\") | .spec.values | select(. != null)] | length" "${manifest}") -gt 0 ]]; then
      yq 'select(.kind == "HelmRelease") | .spec.values' "${manifest}" > "${tmp}/inline.yaml"
      render "${manifest} (spec.values)" "${base[@]}" -f "${tmp}/inline.yaml"
    fi
  done
done

if [[ ${status} -eq 0 ]]; then
  echo "${checked} example value set(s) render against this chart."
fi

exit ${status}
