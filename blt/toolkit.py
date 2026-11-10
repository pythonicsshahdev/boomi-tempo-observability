"""Read one Boomi Load Testing Toolkit run back out of the toolkit's Prometheus."""
import csv
import glob
import os
import re
import time
from dataclasses import dataclass, field
from typing import Dict, List


SCRAPE_STEP_S = 5          # the toolkit's Prometheus scrape interval
SCAN_BACK_S = 6 * 3600     # runs longer than this are not supported


class RunNotFound(Exception):
    pass


@dataclass
class RunStats:
    run_id: str
    total: int
    by_code: Dict[str, int]
    start: float
    end: float
    steps: List[str] = field(default_factory=list)
    approximate: bool = False        # True when the total comes from Prometheus counters


def _extent(get_json, prom, query, start, end, step):
    """First and last time the query has a sample, or None."""
    body = get_json(prom + "/api/v1/query_range",
                    {"query": query, "start": int(start), "end": int(end), "step": step})
    times = [float(t) for r in body["data"]["result"] for t, _ in r["values"]]
    return (min(times), max(times)) if times else None


def fetch_run_stats(prom, run_id, get_json, lookback_days=7, now=None):
    now = time.time() if now is None else now
    sel = 'jmeter_requests_total{run_id="%s"}' % run_id
    body = get_json(prom + "/api/v1/query",
                    {"query": "last_over_time(%s[%dd])" % (sel, lookback_days), "time": int(now)})
    series = body["data"]["result"]
    if not series:
        raise RunNotFound("no toolkit run with run_id %s in the last %d days at %s" % (run_id, lookback_days, prom))
    by_code, steps = {}, []
    for r in series:
        code = r["metric"].get("code", "?")
        by_code[code] = by_code.get(code, 0) + int(float(r["value"][1]))
        step = r["metric"].get("step_id")
        if step and step not in steps:
            steps.append(step)
    # Anchor on the last sample, then scan the 6 h before it at the 5 s scrape interval. (A coarse scan over
    # days can step right over a 30 s series.)
    last = get_json(prom + "/api/v1/query", {
        "query": "max(timestamp(last_over_time(%s[%dd])))" % (sel, lookback_days), "time": int(now)})["data"]["result"]
    if not last:
        raise RunNotFound("run %s has counters but no samples inside the last %d days" % (run_id, lookback_days))
    anchor = float(last[0]["value"][1])
    extent = _extent(get_json, prom, "count(%s)" % sel, anchor - SCAN_BACK_S, anchor + SCRAPE_STEP_S, SCRAPE_STEP_S)
    if extent is None:
        raise RunNotFound("run %s has counters but no samples in the 6 hours before its last sample" % run_id)
    fine = extent
    return RunStats(run_id=run_id, total=sum(by_code.values()), by_code=by_code,
                    start=fine[0], end=fine[1], steps=sorted(steps), approximate=True)


def fetch_run_stats_from_jtl(results_dir, run_id):
    """Exact counts from the toolkit's per-request results files (<run_id>-<step>-<n>.jtl, one row per
    request, warmup included, timestamps in epoch milliseconds)."""
    paths = sorted(glob.glob(os.path.join(results_dir, run_id + "-*.jtl")))
    if not paths:
        raise RunNotFound("no %s-*.jtl files in %s" % (run_id, results_dir))
    by_code, steps, first, last, total = {}, [], None, None, 0
    for path in paths:
        m = re.search(r"-(step-\d+)-\d+\.jtl$", path)
        if m and m.group(1) not in steps:
            steps.append(m.group(1))
        with open(path, newline="") as fh:
            for rec in csv.DictReader(fh):
                total += 1
                by_code[rec["responseCode"]] = by_code.get(rec["responseCode"], 0) + 1
                ts, el = int(rec["timeStamp"]), int(rec["elapsed"])
                first = ts if first is None else min(first, ts)
                last = ts + el if last is None else max(last, ts + el)
    if total == 0:
        raise RunNotFound("the results files for %s hold no requests" % run_id)
    return RunStats(run_id=run_id, total=total, by_code=by_code, start=first / 1000.0, end=last / 1000.0,
                    steps=sorted(steps), approximate=False)
