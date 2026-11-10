import pytest
from blt import toolkit


def fake_get(responses):
    calls = []

    def get_json(url, params=None):
        calls.append((url, params))
        q = params["query"]
        for needle, body in responses:
            if needle in q:
                return body
        raise AssertionError("unexpected query: " + q)

    get_json.calls = calls
    return get_json


def vec(*series):
    return {"status": "success", "data": {"resultType": "vector", "result": [
        {"metric": m, "value": [1000, str(v)]} for m, v in series]}}


def matrix(points):
    return {"status": "success", "data": {"resultType": "matrix", "result": [
        {"metric": {}, "values": [[t, "1"] for t in points]}]}}


def test_total_sums_every_series_across_steps_and_codes():
    g = fake_get([
        ("last_over_time", vec(({"step_id": "step-01", "code": "200"}, 196),
                               ({"step_id": "step-01", "code": "500"}, 4),
                               ({"step_id": "step-02", "code": "200"}, 389))),
        ("count(", matrix([100, 160, 220])),
    ])
    s = toolkit.fetch_run_stats("http://p:9090", "RID", g, now=1_000_000)
    assert s.total == 589
    assert s.by_code == {"200": 585, "500": 4}
    assert s.steps == ["step-01", "step-02"]


def test_query_selects_the_run_id():
    g = fake_get([("last_over_time", vec(({"step_id": "s", "code": "200"}, 1))), ("count(", matrix([10]))])
    toolkit.fetch_run_stats("http://p:9090", "20261107-193845", g, now=1_000_000)
    assert 'run_id="20261107-193845"' in g.calls[0][1]["query"]


def test_window_is_first_and_last_sample_time():
    g = fake_get([
        ("last_over_time", vec(({"step_id": "s", "code": "200"}, 5))),
        ("count(", matrix([100, 160, 220, 280])),
    ])
    s = toolkit.fetch_run_stats("http://p:9090", "RID", g, now=1_000_000)
    assert (s.start, s.end) == (100, 280)


def test_unknown_run_raises():
    g = fake_get([("last_over_time", vec())])
    with pytest.raises(toolkit.RunNotFound):
        toolkit.fetch_run_stats("http://p:9090", "nope", g, now=1_000_000)


# ---- exact counts from the toolkit's results files (.jtl) ----

HEADER = "timeStamp,elapsed,label,responseCode,responseMessage,threadName,dataType,success,failureMessage,bytes,sentBytes,grpThreads,allThreads,Latency,IdleTime,Connect\n"


def row(ts, elapsed, code):
    return "%d,%d,Ping,%s,OK,T 1-1,text,true,,246,209,3,3,195,0,10\n" % (ts, elapsed, code)


def test_jtl_counts_rows_codes_window_and_steps(tmp_path):
    (tmp_path / "RID-step-01-1.jtl").write_text(HEADER + row(1_000_000, 200, 200) + row(1_001_000, 100, 200))
    (tmp_path / "RID-step-02-1.jtl").write_text(HEADER + row(1_005_000, 50, 500))
    (tmp_path / "OTHER-step-01-1.jtl").write_text(HEADER + row(9_000_000, 1, 200))
    s = toolkit.fetch_run_stats_from_jtl(str(tmp_path), "RID")
    assert s.total == 3 and s.by_code == {"200": 2, "500": 1}
    assert s.steps == ["step-01", "step-02"]
    assert (s.start, s.end) == (1000.0, 1005.05)
    assert s.approximate is False


def test_jtl_missing_run_raises(tmp_path):
    with pytest.raises(toolkit.RunNotFound):
        toolkit.fetch_run_stats_from_jtl(str(tmp_path), "RID")


def test_prometheus_stats_are_marked_approximate():
    g = fake_get([("last_over_time", vec(({"step_id": "s", "code": "200"}, 5))), ("count(", matrix([100]))])
    assert toolkit.fetch_run_stats("http://p:9090", "RID", g, now=1_000_000).approximate is True


def test_window_scan_is_anchored_on_the_last_sample_and_uses_the_scrape_interval():
    """A coarse scan over days can step right over a 30 s series: scan 6 h back from the last sample at 5 s."""
    g = fake_get([
        ("timestamp(", vec(({}, 1000))),
        ("last_over_time", vec(({"step_id": "s", "code": "200"}, 5))),
        ("count(", matrix([990, 995, 1000])),
    ])
    s = toolkit.fetch_run_stats("http://p:9090", "RID", g, now=1_000_000)
    rng = [p for u, p in g.calls if u.endswith("/api/v1/query_range")]
    assert rng and all(p["step"] == 5 for p in rng)
    assert rng[0]["start"] == 1000 - 6 * 3600 and rng[0]["end"] == 1005
    assert (s.start, s.end) == (990, 1000)
