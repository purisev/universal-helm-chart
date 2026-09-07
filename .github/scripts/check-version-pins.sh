#!/usr/bin/env bash
#
# Every place the docs pin this chart's version has to name the version in
# Chart.yaml. The pins live in Argo CD Applications (targetRevision), Flux
# OCIRepositories (tag), helm install scripts (--version), schema URLs and a
# few sentences of prose, so this matches on the version itself rather than on
# the key in front of it: any X.Y.Z sharing a major with Chart.yaml, with or
# without a leading v.
#
# Historical records are excluded, because naming an older version is their job:
# the migration guide and the ADRs.
#
# On a release-X.Y.Z branch it also holds Chart.yaml to the version the branch
# name promises, which is the bump that is easy to forget until after the tag.
#
# Run it the same way CI does:
#   bash .github/scripts/check-version-pins.sh
#   TARGET_REF=release-3.2.0 bash .github/scripts/check-version-pins.sh

set -euo pipefail

cd "$(dirname "$0")/../.."

chart_version=$(awk '/^version:[[:space:]]/ {print $2; exit}' Chart.yaml)
if [[ -z "${chart_version}" ]]; then
  echo "could not read 'version:' from Chart.yaml" >&2
  exit 1
fi
major=${chart_version%%.*}

status=0

# --- the branch name against Chart.yaml ------------------------------------

target_ref=${TARGET_REF:-}
if [[ "${target_ref}" =~ ^release-([0-9]+\.[0-9]+\.[0-9]+)$ ]]; then
  branch_version=${BASH_REMATCH[1]}
  if [[ "${chart_version}" != "${branch_version}" ]]; then
    echo "Chart.yaml is on ${chart_version}, but the release branch is ${target_ref}."
    echo "Set 'version: ${branch_version}' in Chart.yaml before tagging."
    echo
    status=1
  fi
fi

# --- the docs against Chart.yaml -------------------------------------------

matches=$(grep -rnoE "v?${major}\.[0-9]+\.[0-9]+" README.md docs \
  --exclude-dir=05-adr \
  --exclude=04-migration.md || true)

stale=$(printf '%s' "${matches}" | awk -F: -v want="${chart_version}" '
  NF == 0 { next }
  { found = $NF; sub(/^v/, "", found); if (found != want) print }')

if [[ -n "${stale}" ]]; then
  count=$(printf '%s\n' "${stale}" | wc -l | tr -d ' ')
  echo "${count} reference(s) name a chart version other than ${chart_version}:"
  echo
  printf '%s\n' "${stale}" | sed 's/^/  /'
  echo
  echo "Update them to ${chart_version}. A version that belongs to something else"
  echo "(a dependency, an image tag) should not share this chart's major, and a"
  echo "historical mention belongs in the migration guide or an ADR, both skipped."
  status=1
fi

if [[ ${status} -eq 0 ]]; then
  echo "Chart.yaml is on ${chart_version} and every reference in README.md and docs/ agrees."
fi

exit ${status}
