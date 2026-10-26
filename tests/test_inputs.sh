#!/bin/bash
cd "$(dirname "$0")/.." || exit 1
. tests/lib.sh
n=$(jq '.spec.elements | length' dashboards/boomi-runtime-load-test.json 2>/dev/null || echo 0)
assert_eq 1 "$([ "$n" -ge 24 ] && echo 1 || echo 0)" "dashboard has at least 24 elements (got $n)"
assert_eq 11 "$(grep -c ExtractPatterns config/collector.yaml 2>/dev/null || echo 0)" "11 ExtractPatterns statements"
assert_eq 1 "$(grep -c 'DS_Store' .gitignore 2>/dev/null || echo 0)" ".gitignore lists DS_Store"
assert_eq 1 "$(grep -c '^data/' .gitignore 2>/dev/null || echo 0)" ".gitignore lists data/"
