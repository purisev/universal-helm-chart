#!/usr/bin/env bash
# Prints two lines: a cron `start` and `end` expression (minute hour * * *)
# bracketing the current UTC time, for the e2e-autoscaling KEDA cron
# scenario. The cron scaler evaluates start/end as a recurring daily
# window, not as timestamps, so the values can't be hardcoded in values
# YAML and have to be computed fresh at CI runtime instead.
set -euo pipefail

date -u -d '-5 minutes' +'%-M %-H * * *'
date -u -d '+30 minutes' +'%-M %-H * * *'
