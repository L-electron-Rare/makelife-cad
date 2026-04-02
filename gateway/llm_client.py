"""HTTP client for life-core LLM proxy."""
from __future__ import annotations
import logging
import os
import httpx

logger = logging.getLogger("makelife_cad.llm_client")

class LLMClientError(Exception):
    """Raised when life-core LLM call fails."""

async def chat(messages: list[dict], model: str) -> str:
    base_url = os.getenv("LIFE_CORE_URL", "http://life-core:8000")
    url = f"{base_url}/chat"
    payload = {"messages": messages, "model": model, "use_rag": False}
    try:
        async with httpx.AsyncClient(timeout=60.0) as client:
            response = await client.post(url, json=payload)
            response.raise_for_status()
            data = response.json()
            return data["content"]
    except httpx.TimeoutException as e:
        logger.error("LLM call timeout: %s", e)
        raise LLMClientError(f"timeout: {e}") from e
    except httpx.HTTPError as e:
        logger.error("LLM call failed: %s", e)
        raise LLMClientError(f"life-core error: {e}") from e
    except KeyError:
        logger.error("Unexpected response format from life-core")
        raise LLMClientError("unexpected response format — missing 'content' field")
