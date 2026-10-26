#!/bin/bash
cd "$(dirname "$0")/.." || exit 1
. tests/lib.sh
CI=otel/opentelemetry-collector-contrib
v() { docker run --rm -v "$PWD/config":/c "$CI" validate --config "/c/$1"; }
assert_eq 0 "$(v collector.yaml >/dev/null 2>&1; echo $?)" "collector.yaml validates"
sed 's|exporters: \[otlp/tempo\]|exporters: [nosuch]|' config/collector.yaml > config/_broken.yaml
assert_fails "broken collector config is rejected" v _broken.yaml
rm -f config/_broken.yaml
assert_eq 0 "$(docker run --rm --entrypoint promtool -v "$PWD/config":/c prom/prometheus check config /c/prometheus.yml >/dev/null 2>&1; echo $?)" "prometheus.yml passes promtool"
assert_eq 1 "$(grep -c 'local-blocks' config/tempo.yaml 2>/dev/null || echo 0)" "tempo.yaml has the local-blocks processor"
