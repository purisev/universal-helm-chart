#!/usr/bin/env bash
#
# Prints the CHANGELOG.md section of one version, without its heading. The
# version defaults to the one in Chart.yaml. Fails when the section is missing
# or empty, so a version cannot be published without release notes.
#
#   bash .github/scripts/release-notes.sh
#   bash .github/scripts/release-notes.sh 3.2.0

set -euo pipefail

cd "$(dirname "$0")/../.."

version=${1:-$(awk '/^version:[[:space:]]/ {print $2; exit}' Chart.yaml)}
if [[ ! "${version}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "'${version}' is not an X.Y.Z version" >&2
  exit 1
fi

notes=$(awk -v version="${version}" '
  /^## / { in_section = ($2 == version); next }
  in_section
' CHANGELOG.md)

if [[ -z "${notes//[[:space:]]/}" ]]; then
  echo "CHANGELOG.md has no notes under a '## ${version}' heading." >&2
  exit 1
fi

printf '%s\n' "${notes}"
