import json
from blt import cli, check
from blt.toolkit import RunStats, RunNotFound
from blt.backends.detect import BackendDetectionError


class B:
    name = "fake"
    settle_seconds = 0

    def __init__(self, n): self.n = n
    def count_route_traces(self, *a, **k): return self.n
    def count_process_traces(self, *a, **k): return self.n


def stats_fn(total):
    return lambda prom, run_id, get_json: RunStats(run_id, total, {"200": total}, 100.0, 200.0, ["step-01"])


def run(argv, spans=100, total=100, **kw):
    out = []
    code = cli.main(argv, fetch=kw.get("fetch", stats_fn(total)), build_backend=kw.get("build", lambda name, a: B(spans)),
                    out=out.append, sleep=lambda s: None, now=lambda: 9999.0)
    return code, "\n".join(out)


BASE = ["check", "--run-id", "R", "--route", "/x"]


def test_exit_codes_match_mismatch_uncorrelated():
    assert run(BASE, spans=100)[0] == 0
    assert run(BASE, spans=50)[0] == 1
    assert run(BASE, spans=0)[0] == 2


def test_text_output_names_both_numbers_and_status():
    code, text = run(BASE, spans=50)
    assert "mismatch" in text and "100" in text and "50" in text


def test_json_output():
    code, text = run(BASE + ["--json"], spans=100)
    d = json.loads(text)
    assert d["status"] == "match" and d["jmeter"] == 100 and d["traces"] == 100 and d["backend"] == "fake"


def test_unknown_run_exits_2_with_a_message():
    def fetch(prom, run_id, get_json): raise RunNotFound("no such run")
    code, text = run(BASE, fetch=fetch)
    assert code == 2 and "no such run" in text


def test_backend_detection_failure_exits_2():
    def build(name, a): raise BackendDetectionError("both stacks answer; pass --backend")
    code, text = run(BASE, build=build)
    assert code == 2 and "--backend" in text


def test_route_or_process_is_required():
    code, text = run(["check", "--run-id", "R"])
    assert code == 2 and "--route" in text


def test_jtl_dir_is_used_when_given_and_prometheus_is_not_touched():
    def boom(prom, run_id, get_json): raise AssertionError("prometheus must not be used")
    seen = {}

    def jtl(path, run_id):
        seen["args"] = (path, run_id)
        return RunStats(run_id, 100, {"200": 100}, 100.0, 200.0, ["step-01"])

    out = []
    code = cli.main(BASE + ["--jtl-dir", "/some/results"], fetch=boom, fetch_jtl=jtl,
                    build_backend=lambda n, a: B(100), out=out.append, sleep=lambda s: None, now=lambda: 9999.0)
    assert code == 0 and seen["args"] == ("/some/results", "R")
