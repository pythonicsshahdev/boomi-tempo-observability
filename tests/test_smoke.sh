#!/bin/bash
# Synthetic smoke test: traces (trace-id prefix control), metric-name conversion, logs discarded.
cd "$(dirname "$0")/.." || exit 1
. tests/lib.sh
PROM=${PROMETHEUS_PORT:-9090}
TG=ghcr.io/open-telemetry/opentelemetry-collector-contrib/telemetrygen:latest
now=$(date +%s)000000000
since=$(date -u +%Y-%m-%dT%H:%M:%S)

# --- traces: 20 single-span traces whose ids start deadbeef, sent to the second port pair (4320)
spans=$(for i in $(seq 1 20); do
  printf '{"traceId":"deadbeef%024x","spanId":"%016x","name":"smoke","kind":2,"startTimeUnixNano":"%s","endTimeUnixNano":"%s","attributes":[{"key":"http.route","value":{"stringValue":"/smoke"}}]}' "$i" "$i" "$now" "$((now+1000000))"
done | sed 's/}{/},{/g')
body='{"resourceSpans":[{"resource":{"attributes":[{"key":"service.name","value":{"stringValue":"smoke-test"}}]},"scopeSpans":[{"spans":['"$spans"']}]}]}'
assert_eq 200 "$(curl -s -o /dev/null -w '%{http_code}' -H 'Content-Type: application/json' -d "$body" localhost:4320/v1/traces)" "traces accepted on 4320"

tempo_count() {  # tempo_count <trace-id-prefix>
  local s=$(( $(date +%s) - 600 )) e=$(( $(date +%s) + 60 ))
  curl -sG localhost:3200/api/search --data-urlencode "q={ trace:id =~ \"$1.*\" }" \
    --data-urlencode "limit=100" --data-urlencode "start=$s" --data-urlencode "end=$e" | jq '.traces | length' 2>/dev/null || echo 0
}
for i in $(seq 1 20); do [ "$(tempo_count deadbeef)" = 20 ] && break; sleep 3; done
assert_eq 20 "$(tempo_count deadbeef)" "tempo search finds all 20 deadbeef traces"
assert_eq 0 "$(tempo_count cafebabe)" "wrong-prefix control returns 0"

# --- metrics: gauge jvm.heap.current (unit By) must become jvm_heap_current_bytes
mbody='{"resourceMetrics":[{"resource":{"attributes":[{"key":"service.name","value":{"stringValue":"smoke-test"}}]},"scopeMetrics":[{"metrics":[{"name":"jvm.heap.current","unit":"By","gauge":{"dataPoints":[{"asDouble":123456,"timeUnixNano":"'"$now"'","attributes":[{"key":"jvm.id","value":{"stringValue":"smoke-1"}}]}]}}]}]}]}'
assert_eq 200 "$(curl -s -o /dev/null -w '%{http_code}' -H 'Content-Type: application/json' -d "$mbody" localhost:4318/v1/metrics)" "metrics accepted on 4318"
prom_count() { curl -sG "localhost:$PROM/api/v1/query" --data-urlencode "query=$1" | jq '.data.result | length' 2>/dev/null || echo 0; }
for i in $(seq 1 20); do [ "$(prom_count 'jvm_heap_current_bytes{job="smoke-test",jvm_id="smoke-1"}')" -ge 1 ] && break; sleep 3; done
assert_eq 1 "$(prom_count 'jvm_heap_current_bytes{job="smoke-test",jvm_id="smoke-1"}')" "prometheus has jvm_heap_current_bytes with job and jvm_id labels"

# --- logs over gRPC on 4317: accepted and discarded, no collector errors
docker run --rm "$TG" logs --otlp-endpoint host.docker.internal:4317 --otlp-insecure --logs 10 >/tmp/smoke-logs.out 2>&1
assert_eq 0 "$?" "logs accepted over gRPC on 4317"
sleep 2
assert_eq 0 "$(docker-compose logs --since "$since" collector 2>&1 | grep -ci 'error')" "collector logged no errors"
