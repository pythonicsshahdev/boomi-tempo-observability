import pytest
from blt import check
from blt.toolkit import RunStats


class FakeBackend:
    name = "fake"
    settle_seconds = 15

    def __init__(self, spans):
        self.spans, self.calls = spans, []

    def count_route_traces(self, route, start, end, method=None):
        self.calls.append(("route", route, start, end, method))
        return self.spans

    def count_process_traces(self, process, start, end):
        self.calls.append(("process", process, start, end))
        return self.spans


def stats(total=2000, end=1000.0):
    return RunStats(run_id="R", total=total, by_code={"200": total}, start=800.0, end=end, steps=["step-01"])


NOSLEEP = dict(sleep=lambda s: None, now=lambda: 10_000.0)


def test_match_within_tolerance():
    r = check.check_run(stats(2000), FakeBackend(2030), route="/x", **NOSLEEP)   # 1.5% off
    assert r.status == "match" and r.delta == 30


def test_mismatch_outside_tolerance_reports_both_numbers():
    r = check.check_run(stats(2000), FakeBackend(1500), route="/x", **NOSLEEP)
    assert r.status == "mismatch" and (r.jmeter, r.traces, r.delta) == (2000, 1500, -500)


def test_zero_traces_is_uncorrelated_never_a_pass():
    r = check.check_run(stats(2000), FakeBackend(0), route="/x", **NOSLEEP)
    assert r.status == "uncorrelated" and any("retention" in n for n in r.notes)


def test_tiny_runs_allow_a_small_absolute_difference():
    assert check.check_run(stats(20), FakeBackend(22), route="/x", **NOSLEEP).status == "match"
    assert check.check_run(stats(20), FakeBackend(30), route="/x", **NOSLEEP).status == "mismatch"


def test_window_is_padded():
    b = FakeBackend(2000)
    check.check_run(stats(2000), b, route="/x", pad_s=15, **NOSLEEP)
    assert b.calls[0][2:4] == (785.0, 1015.0)


def test_waits_for_the_trace_store_when_the_run_just_ended():
    slept = []
    check.check_run(stats(2000, end=1000.0), FakeBackend(2000), route="/x",
                    sleep=slept.append, now=lambda: 1005.0)
    assert slept == [10.0]          # settle 15 s, run ended 5 s ago


def test_no_wait_when_the_run_is_old_or_disabled():
    slept = []
    check.check_run(stats(2000, end=1000.0), FakeBackend(2000), route="/x", sleep=slept.append, now=lambda: 5000.0)
    check.check_run(stats(2000, end=1000.0), FakeBackend(2000), route="/x", wait=False, sleep=slept.append, now=lambda: 1001.0)
    assert slept == []


def test_process_mode_uses_process_count():
    b = FakeBackend(2000)
    r = check.check_run(stats(2000), b, process="My Proc", **NOSLEEP)
    assert b.calls[0][0] == "process" and r.status == "match"


def test_exactly_one_of_route_or_process():
    with pytest.raises(ValueError):
        check.check_run(stats(), FakeBackend(1), **NOSLEEP)
    with pytest.raises(ValueError):
        check.check_run(stats(), FakeBackend(1), route="/x", process="p", **NOSLEEP)


def test_failed_requests_are_reported():
    s = RunStats(run_id="R", total=100, by_code={"200": 90, "500": 10}, start=1.0, end=2.0, steps=[])
    assert check.check_run(s, FakeBackend(100), route="/x", **NOSLEEP).failed == 10


def test_approximate_counts_get_a_wider_tolerance_and_say_so():
    exact = RunStats(run_id="R", total=2000, by_code={"200": 2000}, start=800.0, end=1000.0, steps=[])
    approx = RunStats(run_id="R", total=2000, by_code={"200": 2000}, start=800.0, end=1000.0, steps=[], approximate=True)
    assert check.check_run(exact, FakeBackend(2100), route="/x", **NOSLEEP).status == "mismatch"      # 5% off
    r = check.check_run(approx, FakeBackend(2100), route="/x", **NOSLEEP)
    assert r.status == "match" and any("Prometheus" in n for n in r.notes)
