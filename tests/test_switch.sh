#!/bin/bash
# switch-stack.sh must refuse bad input without touching any container, and report what is running.
cd "$(dirname "$0")/.." || exit 1
. tests/lib.sh
snap() { docker ps -q | sort | shasum | cut -d' ' -f1; }
before=$(snap)

out=$(bash scripts/switch-stack.sh bogus 2>&1); rc=$?
assert_eq 2 "$rc" "unknown stack name exits 2"
assert_eq 1 "$(echo "$out" | grep -c -i 'usage')" "unknown stack prints usage"

out=$(OPENSEARCH_STACK_DIR=/nonexistent/dir bash scripts/switch-stack.sh opensearch 2>&1); rc=$?
assert_eq 2 "$rc" "refuses when the OpenSearch stack folder is missing"
assert_eq 1 "$(echo "$out" | grep -c '/nonexistent/dir')" "names the missing folder"
assert_eq "$before" "$(snap)" "no container was stopped or started by a refused switch"

out=$(bash scripts/switch-stack.sh status 2>&1); rc=$?
assert_eq 0 "$rc" "status exits 0"
assert_eq 1 "$(echo "$out" | grep -c -E '^(tempo|opensearch|none|both)')" "status names the running stack"
