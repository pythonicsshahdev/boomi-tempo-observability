#!/bin/bash
# The Boomi API Gateway posts OTLP/HTTP with Content-Type: application/x-protobuf but a JSON body.
# The shim must make that work, and must leave real protobuf clients alone.
cd "$(dirname "$0")/.." || exit 1
. tests/lib.sh
TG=ghcr.io/open-telemetry/opentelemetry-collector-contrib/telemetrygen:latest
now=$(date +%s)000000000
post() { curl -s -o /dev/null -w '%{http_code}' -X POST -H 'Content-Type: application/x-protobuf' -H 'service.name: boomi-api-gateway' -d "$3" "localhost:$1/v1/$2"; }

spans=$(for i in 1 2 3; do printf '{"traceId":"fa11ba00%024x","spanId":"%016x","name":"shim-test","kind":2,"startTimeUnixNano":"%s","endTimeUnixNano":"%s"}' "$i" "$i" "$now" "$((now+1000000))"; done | sed 's/}{/},{/g')
traces='{"resourceSpans":[{"resource":{"attributes":[{"key":"service.name","value":{"stringValue":"shim-test"}}]},"scopeSpans":[{"spans":['"$spans"']}]}]}'
metrics='{"resourceMetrics":[{"resource":{"attributes":[{"key":"service.name","value":{"stringValue":"shim-test"}}]},"scopeMetrics":[{"metrics":[{"name":"shim.test.gauge","unit":"1","gauge":{"dataPoints":[{"asDouble":1,"timeUnixNano":"'"$now"'"}]}}]}]}]}'
logs='{"resourceLogs":[{"resource":{"attributes":[{"key":"service.name","value":{"stringValue":"shim-test"}}]},"scopeLogs":[{"logRecords":[{"timeUnixNano":"'"$now"'","body":{"stringValue":"shim test"}}]}]}]}'

assert_eq 200 "$(post 4320 traces "$traces")" "gateway-style JSON traces accepted on 4320"
assert_eq 200 "$(post 4318 metrics "$metrics")" "gateway-style JSON metrics accepted on 4318"
assert_eq 200 "$(post 4318 logs "$logs")" "gateway-style JSON logs accepted on 4318"

tempo_count() { curl -sG localhost:3200/api/search --data-urlencode 'q={ trace:id =~ "fa11ba00.*" }' --data-urlencode limit=100 \
  --data-urlencode "start=$(( $(date +%s) - 600 ))" --data-urlencode "end=$(( $(date +%s) + 60 ))" | jq '.traces | length' 2>/dev/null || echo 0; }
for i in $(seq 1 20); do [ "$(tempo_count)" = 3 ] && break; sleep 3; done
assert_eq 3 "$(tempo_count)" "the 3 shim-test traces reached Tempo"

docker run --rm "$TG" traces --otlp-http --otlp-endpoint host.docker.internal:4318 --otlp-insecure --traces 3 >/dev/null 2>&1
assert_eq 0 "$?" "real protobuf over HTTP still passes through the shim"
