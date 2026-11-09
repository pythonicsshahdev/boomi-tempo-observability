import argparse
import dataclasses
import json
import os
import sys
import time
import urllib.error

from blt import check as check_mod, http, toolkit
from blt.backends import base, detect
from blt.backends.opensearch import OpenSearchBackend
from blt.backends.tempo import TempoBackend

EXIT = {"match": 0, "mismatch": 1, "uncorrelated": 2}


def default_build_backend(choice, args):
    name = detect.detect_backend(lambda: http.status(args.tempo.rstrip("/") + "/ready") == 200,
                                 lambda: http.status(args.opensearch) == 200,
                                 None if choice == "auto" else choice)
    if name == "tempo":
        return TempoBackend(args.tempo, http.get_json)
    return OpenSearchBackend(args.opensearch, http.post_json)


def build_parser():
    p = argparse.ArgumentParser(prog="blt", description="Compare a Boomi Load Testing Toolkit run with the trace store.")
    sub = p.add_subparsers(dest="cmd", required=True)
    c = sub.add_parser("check", help="compare JMeter's request count with the number of traces on the route for a run")
    c.add_argument("--run-id", required=True, help="the toolkit's run_id, e.g. 20261107-193845")
    c.add_argument("--route", help="http.route of the traced hop, e.g. /ws/rest/tempoobs/loadtarget/ping")
    c.add_argument("--process", help="alternatively count Execute process spans of this process name")
    c.add_argument("--method", help="also require this HTTP method (route mode)")
    c.add_argument("--jtl-dir", default=os.environ.get("BLT_JTL_DIR"),
                   help="the toolkit's test-plans/results folder: exact request counts (env BLT_JTL_DIR); "
                        "without it the counts come from Prometheus and are approximate")
    c.add_argument("--prometheus", default="http://localhost:9090", help="the toolkit's Prometheus")
    c.add_argument("--tempo", default="http://localhost:3200")
    c.add_argument("--opensearch", default="http://localhost:9200")
    c.add_argument("--backend", choices=["auto", "tempo", "opensearch"], default="auto")
    c.add_argument("--pad-seconds", type=float, default=15)
    c.add_argument("--tolerance-pct", type=float, default=2.0)
    c.add_argument("--no-wait", action="store_true", help="do not wait for the trace store to settle")
    c.add_argument("--json", action="store_true")
    return p


def _fmt(ts):
    return time.strftime("%H:%M:%S", time.localtime(ts))


def main(argv=None, *, fetch=toolkit.fetch_run_stats, fetch_jtl=toolkit.fetch_run_stats_from_jtl, build_backend=default_build_backend,
         out=print, sleep=time.sleep, now=time.time):
    args = build_parser().parse_args(argv)
    if bool(args.route) == bool(args.process):
        out("error: pass exactly one of --route or --process")
        return 2
    try:
        if args.jtl_dir:
            stats = fetch_jtl(args.jtl_dir, args.run_id)
        else:
            stats = fetch(args.prometheus.rstrip("/"), args.run_id, http.get_json)
        backend = build_backend(args.backend, args)
        result = check_mod.check_run(stats, backend, route=args.route, process=args.process, method=args.method,
                                     pad_s=args.pad_seconds, tolerance_pct=args.tolerance_pct,
                                     wait=not args.no_wait, sleep=sleep, now=now)
    except (toolkit.RunNotFound, detect.BackendDetectionError, base.TruncatedResult) as e:
        out("error: %s" % e)
        return 2
    except (urllib.error.URLError, OSError) as e:
        out("error: could not reach a service (%s)" % e)
        return 2
    if args.json:
        out(json.dumps(dataclasses.asdict(result)))
    else:
        out("run %s: JMeter sent %d requests (%d failed)" % (result.run_id, result.jmeter, result.failed))
        out("%s: %d traces in %s between %s and %s" % (
            ("route " + result.route) if result.route else ("process " + result.process),
            result.traces, result.backend, _fmt(result.window_start), _fmt(result.window_end)))
        out("result: %s (difference %+d)" % (result.status, result.delta))
        for n in result.notes:
            out("note: " + n)
    return EXIT[result.status]


if __name__ == "__main__":
    sys.exit(main())
