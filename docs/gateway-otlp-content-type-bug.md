# Boomi API Gateway: OTLP/HTTP exports sent with the wrong Content-Type

**Found 2026-11-08** on gateway `LOCAL_MAC_DOCKER_GATEWAY_PROD_01` (image `boomi/gateway:5.4.2-rhel`, started 2026-11-04), exporting to an OpenTelemetry Collector.

## Symptom

The gateway's own log (`logs/<date>.api_gateway.<node>_Node.log`) shows about 7,200 lines a day, every day back to at least 2026-10-09:

```
WARN [io.opentelemetry.exporter.internal.http.HttpExporter] Failed to export logs. Server responded with HTTP status code 400. Error message: proto: unexpected end of group
WARN [io.opentelemetry.exporter.internal.http.HttpExporter] Failed to export metrics. Server responded with HTTP status code 400. Error message: proto: illegal wireType 7
```

The same happens for spans. The OpenTelemetry settings were applied (log at startup: "OpenTelemetry logging enable - true", "metrics enable - true", "tracing enable - true", "OpenTelemetry Tracer started"). Restarting does not help. Networking is fine: the gateway container reaches the collector and gets an HTTP answer.

## Cause

A packet capture of one export shows the request header and body disagree:

```
POST /v1/logs HTTP/1.1
Content-Type: application/x-protobuf
service.name: boomi-api-gateway
content-length: 9737
host: host.docker.internal:4318

{"resourceLogs":[{"resource":{"attributes":[{"key":"hostname", ...
```

The body is OTLP JSON, the header says protobuf. The collector's OTLP/HTTP receiver chooses its decoder from `Content-Type`, parses the JSON text as protobuf, and fails (`{` is byte `0x7B`, which looks like a protobuf group tag). Settings in the gateway UI: endpoint `http://host.docker.internal:4318`, compression NONE, SSL disabled, traces override `http://host.docker.internal:4320`.

## Workaround in this repo

`config/shim/otlp-http-shim.conf` (an nginx service, `otlp-http-shim`, which publishes the HTTP ports 4318 and 4320): when a request body starts with `{`, the content type is rewritten to `application/json`; real protobuf passes through untouched. After adding it the gateway's export failures stopped immediately, and its traces, metrics and logs reached the collector. Test: `tests/test_shim.sh`.

## To report to Boomi

Expected: the exporter's `Content-Type` matches the encoding of the body it sends (either `application/json` with a JSON body, or protobuf with a protobuf body). Only gateway 5.4.2 was tested.
