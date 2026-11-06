#!/usr/bin/env bash
# Compares storefront CPU use with how often the kernel throttled it.
set -euo pipefail
prom="${PROMETHEUS_URL:-http://localhost:30090}"
q() { curl -fsS -G "$prom/api/v1/query" --data-urlencode "query=$1" | jq -r '.data.result[0].value[1] // "NaN"'; }
sel='namespace="shop",pod=~"storefront.*",container="shop"'
use=$(q "avg(sum by (pod) (rate(container_cpu_usage_seconds_total{$sel}[1m])))")
thr=$(q "sum(rate(container_cpu_cfs_throttled_periods_total{$sel}[1m])) / sum(rate(container_cpu_cfs_periods_total{$sel}[1m]))")
awk -v u="$use" -v t="$thr" 'BEGIN { printf "cpu per pod       %.0f millicores\nthrottled periods %.0f%%\n", u*1000, t*100 }'
