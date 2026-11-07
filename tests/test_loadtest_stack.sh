#!/bin/bash
# loadtest.sh --stack opensearch must refuse (exit 2, say why) when that stack is not running.
cd "$(dirname "$0")/.." || exit 1
. tests/lib.sh
out=$(bash scripts/loadtest.sh --stack opensearch --duration 5 2>&1); rc=$?
assert_eq 2 "$rc" "refuses when the opensearch stack is not running"
assert_eq 1 "$(echo "$out" | grep -c 'opensearch stack is not running')" "says the opensearch stack is not running"
