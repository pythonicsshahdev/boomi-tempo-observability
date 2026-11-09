class BackendDetectionError(Exception):
    pass


def detect_backend(probe_tempo, probe_opensearch, override=None):
    """'tempo' or 'opensearch'. An override wins without probing; both or neither answering is an error."""
    if override:
        return override
    tempo, opensearch = probe_tempo(), probe_opensearch()
    if tempo and opensearch:
        raise BackendDetectionError("both the Tempo and the OpenSearch stack answer; pass --backend tempo|opensearch")
    if not tempo and not opensearch:
        raise BackendDetectionError("neither the Tempo nor the OpenSearch stack answers; start one "
                                    "(scripts/switch-stack.sh) or pass --backend with the right URL")
    return "tempo" if tempo else "opensearch"
