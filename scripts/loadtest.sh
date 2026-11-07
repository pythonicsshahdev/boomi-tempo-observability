#!/bin/bash
# loadtest.sh [--duration SEC] [--synthetic] [--rate N] [--stack tempo|opensearch]
# Samples every container's memory while load runs, then reports peak memory against the limit,
# restarts, OOM kills and volume sizes. Exits 1 (GATE FAILED) if any container restarted, was
# OOM-killed or is not running at the end.
#   default      : just samples for --duration while something else drives the load
#                  (for example a Boomi Load Testing Toolkit run against a Boomi API)
#   --synthetic  : also drives telemetrygen traces (--rate spans/s) and metrics (60/s)
cd "$(dirname "$0")/.." || exit 1
DUR=300; RATE=500; SYN=0; STACK=tempo
while [ $# -gt 0 ]; do
  case $1 in
    --duration) DUR=$2; shift 2;;
    --rate) RATE=$2; shift 2;;
    --synthetic) SYN=1; shift;;
    --stack) STACK=$2; shift 2;;
    *) echo "unknown arg $1" >&2; exit 2;;
  esac
done
case $STACK in
  tempo)      SVCS="collector tempo prometheus grafana"
              VOLS="boomi-tempo_tempo-data boomi-tempo_prometheus-data"
              sid() { docker-compose ps -q "$1"; } ;;
  opensearch) SVCS="opensearch vector otel-collector prometheus grafana"
              VOLS="vector_simplified_opensearch-data vector_simplified_prometheus-data"
              sid() { docker ps -q --filter "name=^$1\$"; } ;;
  *) echo "unknown stack $STACK" >&2; exit 2 ;;
esac
missing=""
for s in $SVCS; do [ -n "$(sid $s)" ] || missing="$missing $s"; done
[ -n "$missing" ] && { echo "$STACK stack is not running (missing:$missing)" >&2; exit 2; }
TG=ghcr.io/open-telemetry/opentelemetry-collector-contrib/telemetrygen:latest
OUT=results/$(date +%Y%m%d-%H%M%S); mkdir -p "$OUT"

declare_ids() { for s in $SVCS; do echo "$s $(sid $s)"; done; }
restarts() { docker inspect -f '{{.RestartCount}}' "$1" 2>/dev/null || echo 0; }
base_file=$OUT/base.txt
declare_ids | while read -r s id; do echo "$s $id $(restarts "$id")"; done > "$base_file"

( while true; do
    for s in $SVCS; do
      id=$(awk -v s=$s '$1==s{print $2}' "$base_file")
      docker stats --no-stream --format '{{.MemUsage}}' "$id" 2>/dev/null | sed "s|^|$(date +%s),$s,|"
    done
    sleep 3
  done ) > "$OUT/stats.csv" &
SAMPLER=$!

if [ "$SYN" = 1 ]; then
  echo "synthetic load: traces ${RATE}/s, metrics 60/s, ${DUR}s"
  docker run --rm "$TG" traces --otlp-endpoint host.docker.internal:4319 --otlp-insecure \
    --rate "$RATE" --duration "${DUR}s" --child-spans 3 --service loadtest >"$OUT/gen-traces.log" 2>&1 &
  G1=$!
  docker run --rm "$TG" metrics --otlp-endpoint host.docker.internal:4317 --otlp-insecure \
    --rate 60 --duration "${DUR}s" --service loadtest >"$OUT/gen-metrics.log" 2>&1 &
  G2=$!
  wait $G1; r1=$?; wait $G2; r2=$?
  echo "load generators exited: traces=$r1 metrics=$r2 (non-zero is expected if the target was starved)"
else
  echo "sampling for ${DUR}s; run the load now (for example a toolkit profile against a Boomi API)"
  sleep "$DUR"
fi
kill $SAMPLER 2>/dev/null; wait $SAMPLER 2>/dev/null

to_mib() { awk '{v=$1; u=v; gsub(/[0-9.]/,"",u); gsub(/[A-Za-z]/,"",v);
  if(u=="GiB")v*=1024; else if(u=="KiB"||u=="kB")v/=1024; else if(u=="B")v/=1048576; printf "%.1f", v}'; }
failed=""
printf '%-11s %9s %9s %9s %6s %6s %s\n' container peak_MiB limit_MiB restarts oom state note | tee "$OUT/summary.txt"
while read -r s id base; do
  peak=$(awk -F, -v s=$s '$2==s{split($3,a," / "); print a[1]}' "$OUT/stats.csv" | while read -r m; do echo "$m" | to_mib; echo; done | sort -n | tail -1)
  limit=$(docker inspect -f '{{.HostConfig.Memory}}' "$id" | awk '{if($1==0)print "none"; else printf "%.0f", $1/1048576}')
  now=$(restarts "$id"); delta=$((now - base))
  oom=$(docker inspect -f '{{.State.OOMKilled}}' "$id"); st=$(docker inspect -f '{{.State.Status}}' "$id")
  note=""
  if [ "$delta" -gt 0 ] || [ "$oom" = true ] || [ "$st" != running ]; then failed="$failed $s"; note="<-- FAILED"; fi
  printf '%-11s %9s %9s %9s %6s %6s %s\n' "$s" "${peak:-n/a}" "$limit" "$delta" "$oom" "$st" "$note" | tee -a "$OUT/summary.txt"
done < "$base_file"

echo "volumes:" | tee -a "$OUT/summary.txt"
for v in $VOLS; do
  kb=$(docker run --rm -v "$v":/v busybox du -sk /v 2>/dev/null | cut -f1)
  echo "  $v: ${kb:-n/a} KiB" | tee -a "$OUT/summary.txt"
done
echo "results in $OUT/"
if [ -n "$failed" ]; then echo "GATE FAILED:$failed restarted, was OOM-killed or is not running" | tee -a "$OUT/summary.txt" >&2; exit 1; fi
echo "gate passed: no restarts, no OOM kills"
