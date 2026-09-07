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
# It also holds Chart.yaml to the version its refs name. TARGET_REFS is a
# space-separated list because a run can name the version being prepared in
# more than one place: the branch a pull request targets (a feature PR into
# release-X.Y.Z), the branch it comes from (the release PR itself, which
# targets main and would otherwise assert nothing), or a vX.Y.Z tag. Refs that
# name no version are ignored, so passing all of them is safe.
#
# Run it the same way CI does:
#   bash .github/scripts/check-version-pins.sh
#   TARGET_REFS=release-3.2.0 bash .github/scripts/check-version-pins.sh
#   TARGET_REFS="main release-3.2.0" bash .github/scripts/check-version-pins.sh
#   TARGET_REFS=v3.2.0 bash .github/scripts/check-version-pins.sh

set -euo pipefail

cd "$(dirname "$0")/../.."

chart_version=$(awk '/^version:[[:space:]]/ {print $2; exit}' Chart.yaml)
if [[ -z "${chart_version}" ]]; then
  echo "could not read 'version:' from Chart.yaml" >&2
  exit 1
fi
major=${chart_version%%.*}

status=0

# --- the ref names against Chart.yaml --------------------------------------

for ref in ${TARGET_REFS:-}; do
  [[ "${ref}" =~ ^(release-|v)([0-9]+\.[0-9]+\.[0-9]+)$ ]] || continue
  ref_version=${BASH_REMATCH[2]}
  if [[ "${chart_version}" != "${ref_version}" ]]; then
    echo "Chart.yaml is on ${chart_version}, but ${ref} calls for ${ref_version}."
    echo "Set 'version: ${ref_version}' in Chart.yaml."
    echo
    status=1
  fi
done

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
