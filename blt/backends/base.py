from typing import Optional, Protocol


class TruncatedResult(Exception):
    """The store may have returned a capped result; a count taken from it cannot be trusted."""


class SpanBackend(Protocol):
    name: str
    settle_seconds: int

    def count_route_traces(self, route: str, start: float, end: float, method: Optional[str] = None) -> int: ...

    def count_process_traces(self, process: str, start: float, end: float) -> int: ...
