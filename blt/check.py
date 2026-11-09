import time
from dataclasses import dataclass, field
from typing import List, Optional


APPROX_TOLERANCE_PCT = 6.0


@dataclass
class CheckResult:
    status: str                      # match | mismatch | uncorrelated
    jmeter: int
    traces: int                      # distinct traces on the route: one per request
    delta: int                       # traces - jmeter
    failed: int                      # JMeter requests whose HTTP code was not 2xx
    window_start: float
    window_end: float
    backend: str
    run_id: str
    route: Optional[str] = None
    process: Optional[str] = None
    notes: List[str] = field(default_factory=list)


def check_run(stats, backend, route=None, process=None, method=None, pad_s=15, tolerance_pct=2.0,
              min_abs=3, wait=True, sleep=time.sleep, now=time.time):
    if (route is None) == (process is None):
        raise ValueError("pass exactly one of route or process")
    if wait:
        remaining = backend.settle_seconds - (now() - stats.end)
        if remaining > 0:
            sleep(remaining)
    start, end = stats.start - pad_s, stats.end + pad_s
    if route is not None:
        traces = backend.count_route_traces(route, start, end, method)
        target = "route %s" % route
    else:
        traces = backend.count_process_traces(process, start, end)
        target = "process %s" % process
    delta = traces - stats.total
    notes = []
    if getattr(stats, "approximate", False):
        # Prometheus scrapes the JMeter containers every 5 s, so each step's last counter value can miss
        # up to 5 s of requests: the total is a lower bound.
        tolerance_pct = max(tolerance_pct, APPROX_TOLERANCE_PCT)
        notes.append("the JMeter total comes from Prometheus counters, which can miss up to 5 s of requests per "
                     "step; tolerance widened to %g%%. Pass --jtl-dir for an exact count." % tolerance_pct)
    failed = sum(n for code, n in stats.by_code.items() if not code.startswith("2"))
    if traces == 0:
        status = "uncorrelated"
        notes.append("no traces for %s in the run window: check the route string, that telemetry is switched on, "
                     "and the trace store's retention (the Tempo stack keeps 1 hour)" % target)
    elif abs(delta) <= max(min_abs, tolerance_pct / 100.0 * stats.total):
        status = "match"
    else:
        status = "mismatch"
        notes.append("JMeter counts warmup requests; requests rejected before the traced hop (401/429) or "
                     "dropped telemetry make the two numbers differ")
    return CheckResult(status=status, jmeter=stats.total, traces=traces, delta=delta, failed=failed,
                       window_start=start, window_end=end, backend=backend.name, run_id=stats.run_id,
                       route=route, process=process, notes=notes)
