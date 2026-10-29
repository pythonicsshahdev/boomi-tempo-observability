#!/bin/bash
cd "$(dirname "$0")/.." || exit 1
. tests/lib.sh
export PROMETHEUS_PORT=${PROMETHEUS_PORT:-9091}
snap() { docker ps -q | sort | shasum | cut -d' ' -f1; }

shim=$(mktemp -d)
for t in bash docker docker-compose curl unzip; do ln -s "$(command -v $t)" "$shim/$t"; done
before=$(snap)

out=$(PATH="$shim" /bin/bash scripts/install.sh 2>&1); rc=$?
assert_eq 2 "$rc" "install exits 2 when jq is missing"
assert_eq 1 "$(echo "$out" | grep -c 'jq')" "message names jq"
assert_eq "$before" "$(snap)" "no containers changed when a tool is missing"

out=$(MIN_VM_GIB=999 bash scripts/install.sh 2>&1); rc=$?
assert_eq 2 "$rc" "install exits 2 when the Docker VM is too small"
assert_eq "$before" "$(snap)" "no containers changed when the VM is too small"

bash scripts/install.sh >/dev/null 2>&1
assert_eq 0 "$?" "install succeeds on a healthy host"
rm -rf "$shim"
