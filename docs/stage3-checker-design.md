# Stage 3: the correlation checker (`blt check`)

Replaces the correlation plan's runner. The Boomi Load Testing Toolkit (separate project) runs the load; this checker only reads.

**Question it answers:** for one toolkit run, does the number of requests JMeter sent agree with the number of traces the trace store holds for that route in the run's window?

```
python3 -m blt check --run-id 20261107-193845 --route /ws/rest/tempoobs/loadtarget/ping \
    --jtl-dir ~/Documents/boomicompanion_projects/BOOMI_Performance_Testing_POC/test-plans/results
```

## How it counts

1. **JMeter side, exact (`--jtl-dir`, or env `BLT_JTL_DIR`):** the toolkit writes one results file per step and instance, `<run_id>-<step>-<n>.jtl`, one row per request, warmup included. Row count = requests sent; the response-code column gives the failures; the first and last timestamps give the window. For the 2026-11-07 run this gave 2,852 requests and 17 failures, matching the toolkit's own report.
2. **JMeter side, approximate (default without `--jtl-dir`):** `jmeter_requests_total{run_id=...}` in the toolkit's Prometheus (`localhost:9090`), summed over every series' last value. Prometheus scrapes the JMeter containers every 5 s, so each step's final value can miss up to 5 s of requests: one real run read 2,707 of 2,852, and a 30 s run read 117 of 137. The result is marked approximate and the tolerance grows by steps x 5 s x the run's average request rate, which the output states. The run window is found by anchoring on the series' last sample and scanning the 6 hours before it at the 5 s scrape interval (a coarse scan over days can step over a short run), so runs longer than 6 hours are not supported.
3. **Trace side: one trace per request.** The checker counts distinct **traces** that contain a span with `http.route` equal to `--route` (optionally `--method`), or traces with a route that starts with `--route-prefix` (for runs that hit several paths: the customers run's "get customer" route contains the customer id), or, with `--process NAME`, traces with an `Execute process` span for that process. It does not count spans: the Boomi API Gateway and the Atom each emit a span with the route inside one trace (trace context propagates), so a span count is 2x the requests. Live check: 10 requests gave 20 spans, 10 traces.
   - **Tempo:** search API, never TraceQL metrics (the metrics endpoint ignores the trace-id regex). Exact about 15 s after the last request; a result that reaches the search limit is refused as truncated.
   - **OpenSearch:** cardinality of `traceId.keyword` over `ss4o_traces-*` (exact below 40,000). Needs about 5 s.
   - Detected automatically (Tempo `:3200/ready`, OpenSearch `:9200`); both or neither up is an error unless `--backend` is given. The checker waits out the settle time; `--no-wait` skips it.
4. **Verdict:** `match` (traces within 2% or 3 of JMeter's total), `mismatch` (both numbers and the difference are printed), `uncorrelated` (zero traces: wrong route, telemetry off, or the trace store has already dropped the data; the Tempo stack keeps 1 hour). Exit code 0, 1, 2. Errors (unknown run, nothing reachable, truncated search) print a message and exit 2. `--json` prints the result as JSON.

Evidence: the customers run `20261110-093803` (`rest-boomi-local`, 137 requests: 69 list calls and 68 get-customer calls) gave 137 traces in OpenSearch, difference +0. Earlier,  the 2026-11-07 run had 2,850 `Execute process` traces in Tempo against 2,852 requests in the results files (0.07% apart).

Not in scope: running load, per-request (trace-id) matching, changing retention.
