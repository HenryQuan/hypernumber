from __future__ import annotations

import json
import time
from collections.abc import Callable
from typing import Any
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen


class HyperliquidError(RuntimeError):
    pass


class HyperliquidClient:
    """Small client for the public Hyperliquid info API (no API key required)."""

    def __init__(
        self,
        base_url: str = "https://api.hyperliquid.xyz",
        timeout: int = 30,
        delay: float = 0.5,
    ):
        self.url = base_url.rstrip("/") + "/info"
        self.timeout = timeout
        self.delay = delay
        self._last_request = 0.0

    def info(self, payload: dict) -> Any:
        body = json.dumps(payload).encode()
        request = Request(
            self.url, body, {"Content-Type": "application/json"}, method="POST"
        )
        # Avoid hammering the public API: leave at least `delay` seconds between
        # requests (large accounts paginate dozens of pages).
        wait = self.delay - (time.monotonic() - self._last_request)
        if wait > 0:
            time.sleep(wait)
        self._last_request = time.monotonic()
        try:
            with urlopen(request, timeout=self.timeout) as response:
                return json.loads(response.read())
        except HTTPError as exc:
            if exc.code == 429:
                raise HyperliquidError(
                    "Hyperliquid rate limit reached - please wait a moment and try again"
                ) from exc
            # Hyperliquid's useful validation message is in the response body.
            try:
                detail = exc.read().decode("utf-8", "replace")
            except (OSError, UnicodeDecodeError):
                detail = str(exc.reason)
            raise HyperliquidError(
                f"Hyperliquid API request failed: {exc.reason} ({detail})"
            ) from exc
        except (URLError, TimeoutError) as exc:
            detail = getattr(exc, "reason", exc)
            raise HyperliquidError(f"Hyperliquid API request failed: {detail}") from exc
        except json.JSONDecodeError as exc:
            raise HyperliquidError("Hyperliquid returned invalid JSON") from exc

    def fills(
        self,
        address: str,
        start_ms: int | None = None,
        on_page: Callable[[str, int], None] | None = None,
    ) -> list[dict]:
        """Fetch the full public fill history, paging by timestamp."""
        result: list[dict] = []
        # userFillsByTime requires startTime in the request body. A zero
        # timestamp means "all available history".
        cursor = 0 if start_ms is None else start_ms
        seen: set[tuple] = set()
        page_no = 0
        while True:
            page_no += 1
            if on_page:
                on_page("fills", page_no)
            payload = {"type": "userFillsByTime", "user": address}
            if cursor is not None:
                payload["startTime"] = cursor
            page = self.info(payload)
            if not isinstance(page, list):
                raise HyperliquidError("Unexpected fills response")
            fresh = []
            for fill in page:
                key = (
                    fill.get("hash"),
                    fill.get("tid"),
                    fill.get("time"),
                    fill.get("oid"),
                )
                if key not in seen:
                    seen.add(key)
                    fresh.append(fill)
            result.extend(fresh)
            if len(page) < 2000 or not page:
                break
            newest = max(int(f.get("time", 0)) for f in page)
            if cursor is not None and newest <= cursor:
                break
            cursor = newest + 1
        return sorted(result, key=lambda f: int(f.get("time", 0)))

    def clearinghouse_state(self, address: str) -> dict:
        value = self.info({"type": "clearinghouseState", "user": address})
        return value if isinstance(value, dict) else {}

    def portfolio(self, address: str) -> list:
        value = self.info({"type": "portfolio", "user": address})
        return value if isinstance(value, list) else []

    def funding(
        self,
        address: str,
        start_ms: int | None = None,
        on_page: Callable[[str, int], None] | None = None,
    ) -> list[dict]:
        # userFunding caps responses at 500 entries, so advance the cursor as
        # long as new data keeps arriving (no page-size assumption).
        result, cursor, seen = [], (0 if start_ms is None else start_ms), set()
        page_no = 0
        while True:
            page_no += 1
            if on_page:
                on_page("funding", page_no)
            value = self.info(
                {"type": "userFunding", "user": address, "startTime": cursor}
            )
            if not isinstance(value, list) or not value:
                break
            for item in value:
                key = (item.get("time"), item.get("hash"), str(item.get("delta")))
                if key not in seen:
                    seen.add(key)
                    result.append(item)
            newest = max(int(x.get("time", 0)) for x in value)
            if newest <= cursor:
                break
            cursor = newest + 1
        return sorted(result, key=lambda x: int(x.get("time", 0)))
