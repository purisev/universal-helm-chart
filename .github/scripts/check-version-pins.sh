#!/usr/bin/env bash
#
# Every place the docs pin this chart's version has to name the version in
# Chart.yaml. Two passes find those places, and their results are merged:
#
#   1. By context, at any major: Argo CD `targetRevision`, `helm ... --version`,
#      a version segment in a universal-helm-chart URL, and `tag` in a Flux
#      OCIRepository (the only file where `tag` names the chart rather than a
#      container image). These stay visible across a major bump, when nothing
#      left in the docs shares Chart.yaml's major any more.
#   2. By version, at Chart.yaml's own major: any X.Y.Z, with or without a
#      leading v. This catches prose naming the version with no key in front of
#      it — and only within the major, so a major bump is the one release where
#      the prose is worth a manual look.
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

semver='v?[0-9]+\.[0-9]+\.[0-9]+'

by_context=$(grep -rnoE "(targetRevision:|--version)[[:space:]=]+\"?${semver}|universal-helm-chart/${semver}" README.md docs \
  --exclude-dir=05-adr \
  --exclude=04-migration.md || true)

by_context_flux=$(grep -rnoE "tag:[[:space:]]*\"?${semver}" README.md docs \
  --include=ocirepository.yaml \
  --exclude-dir=05-adr || true)

by_major=$(grep -rnoE "v?${major}\.[0-9]+\.[0-9]+" README.md docs \
  --exclude-dir=05-adr \
  --exclude=04-migration.md || true)

# Every match ends with the version it found, so the tail of the match is the
# version and the head of the line is file:line. A line found by more than one
# pass is reported once, under the match that names the key it sits behind.
stale=$(printf '%s\n%s\n%s\n' "${by_context}" "${by_context_flux}" "${by_major}" | awk -v want="${chart_version}" '
  NF == 0 { next }
  {
    if (!match($0, /[0-9]+\.[0-9]+\.[0-9]+$/)) next
    found = substr($0, RSTART, RLENGTH)
    split($0, loc, ":")
    if (found == want || seen[loc[1] ":" loc[2] ":" found]++) next
    print
  }')

if [[ -n "${stale}" ]]; then
  count=$(printf '%s\n' "${stale}" | wc -l | tr -d ' ')
  echo "${count} reference(s) name a chart version other than ${chart_version}:"
  echo
  printf '%s\n' "${stale}" | sed 's/^/  /'
  echo
  echo "Update them to ${chart_version}. A version that belongs to something else"
  echo "(a dependency, an image tag) should sit outside a chart pin and should not"
  echo "share this chart's major, and a historical mention belongs in the migration"
  echo "guide or an ADR, both skipped."
  status=1
fi

if [[ ${status} -eq 0 ]]; then
  echo "Chart.yaml is on ${chart_version} and every reference in README.md and docs/ agrees."
fi

exit ${status}
