"""Async client to relay design actions to YiACAD gateway."""

from __future__ import annotations

import os
from typing import Any

import httpx


class YiacadClientError(Exception):
    """Raised when YiACAD gateway call fails."""


def _gateway_base_url() -> str:
    return os.getenv("YIACAD_GATEWAY_URL", "http://127.0.0.1:8100").rstrip("/")


def _build_request(action: str, payload: dict[str, Any]) -> tuple[str, dict[str, Any]]:
    if action == "ai_design":
        # YiACAD endpoint: POST /ai/review/schematic
        body = {
            "schematic_path": payload.get("schematic_path", ""),
            "components": payload.get("components", []),
            "labels": payload.get("labels", []),
            "erc": payload.get("erc", {}),
        }
        return "/ai/review/schematic", body

    if action == "component_suggest":
        # YiACAD endpoint: POST /components/search
        body = {
            "query": payload.get("query") or payload.get("description") or "",
            "limit": payload.get("limit", 10),
            "sources": payload.get("sources", ["nexar", "lcsc"]),
        }
        return "/components/search", body

    if action == "layout_optimize":
        # YiACAD endpoint: POST /ai/review/pcb
        body = {
            "board_path": payload.get("board_path", ""),
        }
        return "/ai/review/pcb", body

    raise YiacadClientError(f"unsupported yiacad action: {action}")


async def execute_action(action: str, payload: dict[str, Any]) -> dict[str, Any]:
    """Execute a YiACAD action by relaying to its FastAPI gateway."""
    route, body = _build_request(action, payload)
    url = f"{_gateway_base_url()}{route}"

    try:
        async with httpx.AsyncClient(timeout=45.0) as client:
            response = await client.post(url, json=body)
            response.raise_for_status()
            data = response.json()
    except httpx.TimeoutException as e:
        raise YiacadClientError(f"timeout calling YiACAD gateway: {e}") from e
    except httpx.HTTPStatusError as e:
        detail = e.response.text[:500] if e.response is not None else str(e)
        raise YiacadClientError(f"YiACAD gateway returned error: {detail}") from e
    except httpx.HTTPError as e:
        raise YiacadClientError(f"YiACAD gateway unreachable: {e}") from e
    except ValueError as e:
        raise YiacadClientError(f"invalid JSON from YiACAD gateway: {e}") from e

    return {
        "route": route,
        "gateway_url": _gateway_base_url(),
        "payload": body,
        "response": data,
    }


async def gateway_health() -> dict[str, Any]:
    """Check YiACAD gateway health endpoint."""
    return await relay("GET", "/healthz", {})


async def relay(method: str, path: str, payload: dict[str, Any] | None = None) -> dict[str, Any]:
    """Generic relay to any YiACAD gateway route."""
    method_norm = method.upper().strip()
    if not path.startswith("/"):
        path = "/" + path
    url = f"{_gateway_base_url()}{path}"

    try:
        async with httpx.AsyncClient(timeout=45.0) as client:
            if method_norm == "GET":
                response = await client.get(url, params=payload or {})
            elif method_norm == "POST":
                response = await client.post(url, json=payload or {})
            elif method_norm == "PUT":
                response = await client.put(url, json=payload or {})
            elif method_norm == "DELETE":
                response = await client.delete(url, json=payload or {})
            else:
                raise YiacadClientError(f"unsupported relay method: {method_norm}")

            response.raise_for_status()
            data = response.json()
    except httpx.TimeoutException as e:
        raise YiacadClientError(f"timeout calling YiACAD gateway: {e}") from e
    except httpx.HTTPStatusError as e:
        detail = e.response.text[:500] if e.response is not None else str(e)
        raise YiacadClientError(f"YiACAD gateway returned error: {detail}") from e
    except httpx.HTTPError as e:
        raise YiacadClientError(f"YiACAD gateway unreachable: {e}") from e
    except ValueError as e:
        raise YiacadClientError(f"invalid JSON from YiACAD gateway: {e}") from e

    return {
        "method": method_norm,
        "path": path,
        "gateway_url": _gateway_base_url(),
        "payload": payload or {},
        "response": data,
    }
