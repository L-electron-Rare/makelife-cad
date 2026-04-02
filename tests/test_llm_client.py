"""Tests for life-core LLM client."""
import os
from unittest.mock import AsyncMock, patch, MagicMock
import pytest
import httpx
from gateway.llm_client import chat, LLMClientError

@pytest.mark.asyncio
async def test_chat_returns_content():
    mock_response = MagicMock()
    mock_response.status_code = 200
    mock_response.json.return_value = {"content": "AMS1117-3.3 is a good choice", "model": "m", "provider": "p"}
    mock_response.raise_for_status = MagicMock()
    mock_client = AsyncMock()
    mock_client.post = AsyncMock(return_value=mock_response)
    mock_client.__aenter__ = AsyncMock(return_value=mock_client)
    mock_client.__aexit__ = AsyncMock(return_value=False)
    with patch("gateway.llm_client.httpx.AsyncClient", return_value=mock_client):
        result = await chat(messages=[{"role": "user", "content": "suggest a regulator"}], model="openai/qwen-14b-awq")
    assert "AMS1117" in result

@pytest.mark.asyncio
async def test_chat_uses_configured_url():
    mock_response = MagicMock()
    mock_response.status_code = 200
    mock_response.json.return_value = {"content": "ok", "model": "m", "provider": "p"}
    mock_response.raise_for_status = MagicMock()
    mock_client = AsyncMock()
    mock_client.post = AsyncMock(return_value=mock_response)
    mock_client.__aenter__ = AsyncMock(return_value=mock_client)
    mock_client.__aexit__ = AsyncMock(return_value=False)
    with patch.dict(os.environ, {"LIFE_CORE_URL": "http://custom:9999"}), \
         patch("gateway.llm_client.httpx.AsyncClient", return_value=mock_client):
        await chat(messages=[{"role": "user", "content": "test"}], model="m")
    call_args = mock_client.post.call_args
    assert "http://custom:9999/chat" in str(call_args)

@pytest.mark.asyncio
async def test_chat_raises_on_error():
    mock_client = AsyncMock()
    mock_client.post = AsyncMock(side_effect=httpx.ConnectError("refused"))
    mock_client.__aenter__ = AsyncMock(return_value=mock_client)
    mock_client.__aexit__ = AsyncMock(return_value=False)
    with patch("gateway.llm_client.httpx.AsyncClient", return_value=mock_client):
        with pytest.raises(LLMClientError):
            await chat(messages=[{"role": "user", "content": "test"}], model="m")

@pytest.mark.asyncio
async def test_chat_raises_on_timeout():
    mock_client = AsyncMock()
    mock_client.post = AsyncMock(side_effect=httpx.ReadTimeout("timeout"))
    mock_client.__aenter__ = AsyncMock(return_value=mock_client)
    mock_client.__aexit__ = AsyncMock(return_value=False)
    with patch("gateway.llm_client.httpx.AsyncClient", return_value=mock_client):
        with pytest.raises(LLMClientError, match="timeout"):
            await chat(messages=[{"role": "user", "content": "test"}], model="m")
