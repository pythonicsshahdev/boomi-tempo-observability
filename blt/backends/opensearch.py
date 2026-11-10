class OpenSearchBackend:
    name = "opensearch"
    settle_seconds = 5

    def __init__(self, base_url, post_json, index="ss4o_traces-*"):
        self.base, self._post, self.index = base_url.rstrip("/"), post_json, index

    def _count(self, filters, start, end):
        """Distinct trace ids: the gateway and the Atom each emit a span on the route inside one trace.
        Cardinality is exact below precision_threshold."""
        filters = filters + [{"range": {"startTime": {"gte": int(start * 1000), "lte": int(end * 1000),
                                                       "format": "epoch_millis"}}}]
        body = self._post("%s/%s/_search" % (self.base, self.index), {
            "size": 0, "query": {"bool": {"filter": filters}},
            "aggs": {"n": {"cardinality": {"field": "traceId.keyword", "precision_threshold": 40000}}}})
        return int(body["aggregations"]["n"]["value"])

    def count_route_traces(self, route, start, end, method=None):
        filters = [{"term": {"attributes.http.route.keyword": route}}]
        if method:
            filters.append({"term": {"attributes.http.request.method.keyword": method}})
        return self._count(filters, start, end)

    def count_route_prefix_traces(self, prefix, start, end):
        return self._count([{"prefix": {"attributes.http.route.keyword": prefix}}], start, end)

    def count_process_traces(self, process, start, end):
        return self._count([{"match_phrase": {"name": "Execute process"}},
                            {"match_phrase": {"attributes.process.name": process}}], start, end)
