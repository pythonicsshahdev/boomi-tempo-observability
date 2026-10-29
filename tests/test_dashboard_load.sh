#!/bin/bash
cd "$(dirname "$0")/.." || exit 1
. tests/lib.sh
G=localhost:3000; A=admin:admin; UID_=boomi-loadtest
code() { curl -s -o /dev/null -w '%{http_code}' -u $A "$G/$1"; }
assert_eq 1 "$(curl -s $G/api/health | jq -r '.version' | grep -c .)" "grafana reports a version"
assert_eq 200 "$(code api/plugins/volkovlabs-echarts-panel/settings)" "echarts plugin is installed"
assert_eq 404 "$(code api/plugins/no-such-plugin/settings)" "control: a missing plugin returns 404"
assert_eq "$UID_" "$(curl -s -u $A "$G/api/search?query=Boomi" | jq -r '.[0].uid')" "dashboard is provisioned"
assert_eq 404 "$(code api/dashboards/uid/no-such-dashboard)" "control: a missing dashboard returns 404"
V2=$(curl -s -u $A "$G/apis/dashboard.grafana.app/v2beta1/namespaces/default/dashboards/$UID_")
assert_eq v2 "$(echo "$V2" | jq -r '.status.conversion.storedVersion')" "dashboard is stored as the v2 schema"
assert_eq false "$(echo "$V2" | jq -r '.status.conversion.failed')" "v2 conversion did not fail"
assert_eq 2 "$(curl -s -u $A "$G/api/datasources" | jq '[.[]|select(.uid=="prometheus" or .uid=="tempo")]|length')" "prometheus and tempo datasources exist"
