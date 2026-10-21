#!/usr/bin/env bash
#
# Waits on the replica count KEDA drives for a Deployment in $NAMESPACE.
#
#   keda-http-replicas.sh zero <deployment> [seconds]
#     spec.replicas is 0 and no pod of the Deployment is left
#   keda-http-replicas.sh at-least <deployment> <count> [seconds]
#     status.readyReplicas is at least <count>
#
# Prints result=<what> on success and exits non-zero on timeout, with the
# Deployment's last observed counts.

set -euo pipefail

mode=$1
deploy=$2
case "${mode}" in
  zero) want=0; limit=${3:-240} ;;
  at-least) want=$3; limit=${4:-240} ;;
  *) echo "unknown mode ${mode}" >&2; exit 2 ;;
esac

deadline=$((SECONDS + limit))
while (( SECONDS < deadline )); do
  spec=$(kubectl get deployment "${deploy}" -n "${NAMESPACE}" -o jsonpath='{.spec.replicas}')
  # status.readyReplicas is omitempty: absent rather than 0 when nothing is ready.
  ready=$(kubectl get deployment "${deploy}" -n "${NAMESPACE}" -o jsonpath='{.status.readyReplicas}')
  ready=${ready:-0}
  if [[ "${mode}" == zero ]]; then
    selector=$(kubectl get deployment "${deploy}" -n "${NAMESPACE}" \
      -o go-template='{{range $k, $v := .spec.selector.matchLabels}}{{$k}}={{$v}},{{end}}')
    pods=$(kubectl get pods -n "${NAMESPACE}" -l "${selector%,}" -o name | wc -l)
    if [[ "${spec}" == 0 && "${pods}" == 0 ]]; then
      echo "result=zero"
      exit 0
    fi
  elif (( ready >= want )); then
    echo "result=at-least-${want}"
    exit 0
  fi
  sleep 3
done

echo "timed out after ${limit}s: spec.replicas=${spec} readyReplicas=${ready}" >&2
exit 1
