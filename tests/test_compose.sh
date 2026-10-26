#!/bin/bash
cd "$(dirname "$0")/.." || exit 1
. tests/lib.sh
SVCS="collector tempo prometheus grafana"
assert_eq 0 "$(docker-compose config -q >/dev/null 2>&1; echo $?)" "docker-compose config is valid"
CFG=$(docker-compose config --format json 2>/dev/null)
for s in $SVCS; do
  assert_eq 1 "$(echo "$CFG" | jq -r ".services.$s.mem_limit // empty" | grep -c .)" "$s has mem_limit"
  assert_eq always "$(echo "$CFG" | jq -r ".services.$s.restart // empty")" "$s restart is always"
done
for i in $(seq 1 40); do
  curl -sf localhost:3200/ready >/dev/null && curl -sf localhost:${PROMETHEUS_PORT:-9090}/-/ready >/dev/null && curl -sf localhost:3000/api/health >/dev/null && break
  sleep 3
done
assert_eq 200 "$(curl -s -o /dev/null -w '%{http_code}' localhost:3200/ready)" "tempo ready"
assert_eq 200 "$(curl -s -o /dev/null -w '%{http_code}' localhost:${PROMETHEUS_PORT:-9090}/-/ready)" "prometheus ready"
assert_eq 200 "$(curl -s -o /dev/null -w '%{http_code}' localhost:3000/api/health)" "grafana healthy"
for s in $SVCS; do
  id=$(docker-compose ps -q $s)
  read -r mem pol <<<"$(docker inspect -f '{{.HostConfig.Memory}} {{.HostConfig.RestartPolicy.Name}}' "$id")"
  assert_eq 1 "$([ "${mem:-0}" -gt 0 ] && echo 1 || echo 0)" "$s container has a memory limit ($mem)"
  assert_eq always "$pol" "$s container restart policy"
done
