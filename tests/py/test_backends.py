import pytest
from blt.backends import base, tempo, opensearch, detect


def test_tempo_route_count_is_traces_not_spans():
    """The gateway and the Atom both emit a span with the route inside one trace: one request, one trace."""
    seen = {}

    def get_json(url, params=None):
        seen["url"], seen["params"] = url, params
        return {"traces": [{"spanSet": {"matched": 2}}, {"spanSet": {"matched": 2}}, {"spanSet": {"matched": 1}}]}

    b = tempo.TempoBackend("http://t:3200", get_json)
    assert b.count_route_traces("/x/ping", 1000.0, 2000.0) == 3
    assert seen["url"] == "http://t:3200/api/search"      # search, never the metrics endpoint
    assert 'span.http.route = "/x/ping"' in seen["params"]["q"]
    assert seen["params"]["start"] == 1000 and seen["params"]["end"] == 2000


def test_tempo_method_filter_is_added():
    seen = {}
    b = tempo.TempoBackend("http://t:3200", lambda u, params=None: seen.update(p=params) or {"traces": []})
    b.count_route_traces("/x", 1, 2, method="GET")
    assert 'span.http.request.method = "GET"' in seen["p"]["q"]


def test_tempo_process_count_filters_execute_process():
    seen = {}
    b = tempo.TempoBackend("http://t:3200", lambda u, params=None: seen.update(p=params) or {"traces": []})
    b.count_process_traces("My Proc", 1, 2)
    assert 'name = "Execute process"' in seen["p"]["q"] and 'span.process.name = "My Proc"' in seen["p"]["q"]


def test_tempo_zero_when_nothing_matches():
    b = tempo.TempoBackend("http://t:3200", lambda u, params=None: {"traces": []})
    assert b.count_route_traces("/x", 1, 2) == 0


def test_tempo_truncated_search_raises():
    traces = [{"spanSet": {"matched": 1}}] * 5
    b = tempo.TempoBackend("http://t:3200", lambda u, params=None: {"traces": traces}, limit=5)
    with pytest.raises(base.TruncatedResult):
        b.count_route_traces("/x", 1, 2)


def test_tempo_settle_is_fifteen_seconds():
    assert tempo.TempoBackend("http://t", lambda *a, **k: {}).settle_seconds == 15


def test_opensearch_route_count_is_distinct_trace_ids():
    seen = {}

    def post_json(url, body):
        seen["url"], seen["body"] = url, body
        return {"aggregations": {"n": {"value": 42}}}

    b = opensearch.OpenSearchBackend("http://o:9200", post_json)
    assert b.count_route_traces("/x/ping", 1000.0, 2000.0) == 42
    assert seen["url"] == "http://o:9200/ss4o_traces-*/_search"
    assert seen["body"]["size"] == 0
    agg = seen["body"]["aggs"]["n"]["cardinality"]
    assert agg["field"] == "traceId.keyword" and agg["precision_threshold"] >= 40000
    f = seen["body"]["query"]["bool"]["filter"]
    assert {"term": {"attributes.http.route.keyword": "/x/ping"}} in f
    rng = [x for x in f if "range" in x][0]["range"]["startTime"]
    assert rng["gte"] == 1_000_000 and rng["lte"] == 2_000_000 and rng["format"] == "epoch_millis"


def test_opensearch_settle_is_five_seconds():
    assert opensearch.OpenSearchBackend("http://o", lambda *a: {}).settle_seconds == 5


def test_detect_only_tempo():
    assert detect.detect_backend(lambda: True, lambda: False) == "tempo"


def test_detect_only_opensearch():
    assert detect.detect_backend(lambda: False, lambda: True) == "opensearch"


def test_detect_both_up_needs_the_flag():
    with pytest.raises(detect.BackendDetectionError):
        detect.detect_backend(lambda: True, lambda: True)


def test_detect_neither_up_raises():
    with pytest.raises(detect.BackendDetectionError):
        detect.detect_backend(lambda: False, lambda: False)


def test_detect_override_wins_without_probing():
    def boom():
        raise AssertionError("must not probe")
    assert detect.detect_backend(boom, boom, override="opensearch") == "opensearch"
