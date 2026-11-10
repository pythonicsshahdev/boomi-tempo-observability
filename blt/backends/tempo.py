import re

from blt.backends.base import TruncatedResult


def _q(value):
    return value.replace("\\", "\\\\").replace('"', '\\"')


class TempoBackend:
    """Counts traces (one per request) with the search API. TraceQL metrics ignore the trace-id regex (spike finding), and a
    search is exact about 15 s after the last span was sent."""
    name = "tempo"
    settle_seconds = 15

    def __init__(self, base_url, get_json, limit=20000):
        self.base, self._get, self.limit = base_url.rstrip("/"), get_json, limit

    def _count(self, traceql, start, end):
        body = self._get(self.base + "/api/search",
                         {"q": traceql, "start": int(start), "end": int(end), "limit": self.limit})
        traces = body.get("traces") or []
        if len(traces) >= self.limit:
            raise TruncatedResult("Tempo returned %d traces, the search limit; the count is not reliable" % len(traces))
        return len(traces)          # one trace per request, however many spans on the route it holds

    def count_route_traces(self, route, start, end, method=None):
        q = '{ span.http.route = "%s"' % _q(route)
        if method:
            q += ' && span.http.request.method = "%s"' % _q(method)
        return self._count(q + " }", start, end)

    def count_route_prefix_traces(self, prefix, start, end):
        # TraceQL regexes are fully anchored, so "<prefix>.*" means: starts with prefix
        return self._count('{ span.http.route =~ "%s.*" }' % _q(re.sub(r"([.+*?()|\[\]{}^$])", r"\\\1", prefix)), start, end)

    def count_process_traces(self, process, start, end):
        return self._count('{ name = "Execute process" && span.process.name = "%s" }' % _q(process), start, end)
