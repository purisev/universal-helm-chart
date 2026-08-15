#!/usr/bin/env bash
# Prints CRON_START and CRON_END as shell assignments, each a cron
# `minute hour * * *` expression bracketing the current UTC time, for the
# e2e-autoscaling KEDA cron scenario. The cron scaler evaluates start/end
# as a recurring daily window, not as timestamps, so the values can't be
# hardcoded in values YAML and have to be computed fresh at CI runtime
# instead. Intended usage: eval "$(bash keda-cron-window.sh)" — each
# expression is itself space-separated, so joining the two lines with a
# plain space (e.g. via `tr '\n' ' '` + `read`) is ambiguous and unsafe.
set -euo pipefail

printf 'CRON_START=%q\n' "$(date -u -d '-5 minutes' +'%-M %-H * * *')"
printf 'CRON_END=%q\n' "$(date -u -d '+30 minutes' +'%-M %-H * * *')"
