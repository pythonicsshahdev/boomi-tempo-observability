#!/bin/bash
# loadtest.sh --stack opensearch must refuse (exit 2, say why) when that stack is not running.
# Only meaningful while the OpenSearch stack is down; skipped otherwise.
cd "$(dirname "$0")/.." || exit 1
. tests/lib.sh
if [ -n "$(docker ps -q --filter 'name=^opensearch$')" ]; then echo "skip: the opensearch stack is running"; exit 0; fi
out=$(bash scripts/loadtest.sh --stack opensearch --duration 5 2>&1); rc=$?
assert_eq 2 "$rc" "refuses when the opensearch stack is not running"
assert_eq 1 "$(echo "$out" | grep -c 'opensearch stack is not running')" "says the opensearch stack is not running"
