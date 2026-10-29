#!/bin/bash
# check_panels.sh <dashboard-uid> [--service REGEX] [--min-with-data N]
# Runs every panel's queries through Grafana's /api/ds/query (the same path the browser uses)
# and prints: title <TAB> frames <TAB> non-zero samples. Exit 1 if a query errors or fewer than
# N panels returned non-zero data. A panel with no data is reported, not hidden as zeros.
cd "$(dirname "$0")/.." || exit 1
uid=$1; shift
svc='.*'; min=1
while [ $# -gt 0 ]; do
  case $1 in --service) svc=$2; shift 2;; --min-with-data) min=$2; shift 2;; *) echo "unknown arg $1" >&2; exit 2;; esac
done
G=${GRAFANA_URL:-localhost:3000}; A=${GRAFANA_AUTH:-admin:admin}
dash=$(curl -sf -u "$A" "$G/apis/dashboard.grafana.app/v2beta1/namespaces/default/dashboards/$uid") \
  || { echo "dashboard $uid not found" >&2; exit 2; }
errors=0; with=0
for k in $(echo "$dash" | jq -r '.spec.elements | keys[]'); do
  title=$(echo "$dash" | jq -r --arg k "$k" '.spec.elements[$k].spec.title')
  body=$(echo "$dash" | jq -c --arg k "$k" --arg svc "$svc" '
    def subst: gsub("\\$\\{service:regex\\}|\\$service"; $svc) | gsub("\\$\\{node:regex\\}|\\$node"; ".*") | gsub("\\$__rate_interval|\\$__interval"; "1m");
    {queries: [ .spec.elements[$k].spec.data.spec.queries[]
        | select(.spec.query.datasource.name != "-- Dashboard --") | select(.spec.hidden | not)
        | (.spec.query.spec | tojson | subst | fromjson)
          + {refId: .spec.refId, datasource: {uid: .spec.query.datasource.name}, intervalMs: 15000, maxDataPoints: 500} ],
     from: "now-1h", to: "now"}')
  if [ "$(echo "$body" | jq '.queries | length')" = 0 ]; then printf '%s\tskipped (reads another panel)\n' "$title"; continue; fi
  resp=$(curl -s -u "$A" -H 'Content-Type: application/json' -d "$body" "$G/api/ds/query")
  frames=$(echo "$resp" | jq '[.results[]?.frames[]?] | length' 2>/dev/null || echo 0)
  nonzero=$(echo "$resp" | jq '[.results[]?.frames[]?.data.values[1:][]?[]? | numbers | select(. != 0)] | length' 2>/dev/null || echo 0)
  err=$(echo "$resp" | jq -r '[.results[]?.error // empty, .message // empty] | first // empty' 2>/dev/null)
  if [ -n "$err" ]; then errors=$((errors+1)); printf '%s\tERROR: %s\n' "$title" "$(echo "$err" | cut -c1-120)"; continue; fi
  [ "${nonzero:-0}" -gt 0 ] && with=$((with+1))
  printf '%s\t%s\t%s\n' "$title" "$frames" "$nonzero"
done
echo "--- panels with data: $with, query errors: $errors (need at least $min with data)"
[ "$errors" -eq 0 ] && [ "$with" -ge "$min" ]
