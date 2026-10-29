#!/bin/bash
cd "$(dirname "$0")/.." || exit 1
. tests/lib.sh
. scripts/lib.sh
export PROMETHEUS_PORT=${PROMETHEUS_PORT:-9091}

bash scripts/stop.sh >/dev/null 2>&1
assert_eq "" "$(port_holder 4319)" "4319 is free after stop"

nc -l 4319 & NC=$!
sleep 1
out=$(bash scripts/start.sh --check-only 2>&1); rc=$?
assert_eq 2 "$rc" "check-only exits 2 when 4319 is held"
assert_eq 1 "$(echo "$out" | grep -c '4319')" "message names port 4319"
kill $NC 2>/dev/null; wait $NC 2>/dev/null

out=$(bash scripts/start.sh --check-only 2>&1); rc=$?
assert_eq 0 "$rc" "check-only passes once 4319 is free"

if [ -n "$(port_holder 9090)" ]; then
  assert_eq 1 "$(echo "$out" | grep -c 'port 9090 is held')" "note names the holder of 9090 (exit stays 0)"
else
  echo "skip: 9090 is free, no note expected"
fi

bash scripts/start.sh >/dev/null 2>&1
out=$(bash scripts/start.sh --check-only 2>&1); rc=$?
assert_eq 0 "$rc" "own running containers do not count as holders"
