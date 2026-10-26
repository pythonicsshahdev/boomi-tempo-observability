#!/bin/bash
# Grafana's own plugin installer fails behind TLS-inspecting networks (container lacks the
# proxy CA). Download on the host instead, which uses the OS trust store.
cd "$(dirname "$0")/.." || exit 1
P=volkovlabs-echarts-panel
[ -d grafana/plugins/$P ] && { echo "$P already present"; exit 0; }
tmp=$(mktemp -d) || exit 1
curl -fsSL "https://grafana.com/api/plugins/$P/versions/latest/download" -o "$tmp/$P.zip" || { echo "download failed"; exit 1; }
unzip -q "$tmp/$P.zip" -d grafana/plugins || { echo "unzip failed"; exit 1; }
rm -rf "$tmp"
ls grafana/plugins
