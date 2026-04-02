"""Tests for AI-assisted CAD endpoints."""
import json
import os
from pathlib import Path
from unittest.mock import AsyncMock, patch
import pytest
from fastapi.testclient import TestClient
from gateway.app import app

client = TestClient(app)

def _mock_chat(return_value: str):
    return AsyncMock(return_value=return_value)

class TestComponentSuggest:
    def test_basic_suggest(self):
        llm_response = json.dumps([{"name": "AMS1117-3.3", "manufacturer": "AMS", "package": "SOT-223", "key_specs": {"Vout": "3.3V"}, "reason": "Standard regulator"}])
        with patch("gateway.app.llm_chat", new=_mock_chat(llm_response)):
            response = client.post("/ai/component-suggest", json={"description": "3.3V regulator for ESP32"})
        assert response.status_code == 200
        data = response.json()
        assert len(data["suggestions"]) == 1
        assert data["suggestions"][0]["name"] == "AMS1117-3.3"

    def test_suggest_with_constraints(self):
        llm_response = json.dumps([{"name": "AP2112K-3.3", "manufacturer": "Diodes Inc", "package": "SOT-23-5", "key_specs": {"Iout": "600mA"}, "reason": "Small"}])
        with patch("gateway.app.llm_chat", new=_mock_chat(llm_response)):
            response = client.post("/ai/component-suggest", json={"description": "LDO", "constraints": {"voltage_out": "3.3V", "current": "500mA"}})
        assert response.status_code == 200
        assert response.json()["suggestions"][0]["name"] == "AP2112K-3.3"

    def test_suggest_with_project_context(self):
        llm_response = json.dumps([{"name": "LM1117-3.3", "manufacturer": "TI", "package": "SOT-223", "key_specs": {}, "reason": "Matches existing"}])
        with patch("gateway.app.llm_chat", new=_mock_chat(llm_response)):
            response = client.post("/ai/component-suggest", json={"description": "voltage regulator", "project_context": "tests/fixtures/simple.kicad_sch"})
        assert response.status_code == 200
        assert response.json()["context_used"] is True

    def test_suggest_missing_description(self):
        response = client.post("/ai/component-suggest", json={})
        assert response.status_code == 422

    def test_suggest_llm_error(self):
        from gateway.llm_client import LLMClientError
        with patch("gateway.app.llm_chat", new=AsyncMock(side_effect=LLMClientError("timeout"))):
            response = client.post("/ai/component-suggest", json={"description": "resistor"})
        assert response.status_code == 502

class TestSchematicReview:
    def test_review_with_project_path(self):
        llm_response = json.dumps([{"severity": "high", "category": "decoupling", "component": "C1", "message": "Value may be insufficient", "suggestion": "Consider 1uF"}])
        with patch("gateway.app.llm_chat", new=_mock_chat(llm_response)):
            response = client.post("/ai/schematic-review", json={"project_path": "tests/fixtures/simple.kicad_sch"})
        assert response.status_code == 200
        data = response.json()
        assert len(data["issues"]) == 1
        assert data["issues"][0]["severity"] == "high"
        assert data["components_analyzed"] == 2

    def test_review_with_upload(self):
        fixture = Path("tests/fixtures/simple.kicad_sch")
        llm_response = json.dumps([])
        with patch("gateway.app.llm_chat", new=_mock_chat(llm_response)):
            with open(fixture, "rb") as f:
                response = client.post("/ai/schematic-review", files={"file": ("test.kicad_sch", f, "application/octet-stream")})
        assert response.status_code == 200
        assert response.json()["components_analyzed"] == 2

    def test_review_with_focus(self):
        llm_response = json.dumps([{"severity": "medium", "category": "power", "component": "R1", "message": "Check power rating", "suggestion": "Verify wattage"}])
        with patch("gateway.app.llm_chat", new=_mock_chat(llm_response)):
            response = client.post("/ai/schematic-review", json={"project_path": "tests/fixtures/simple.kicad_sch", "focus": ["power"]})
        assert response.status_code == 200
        assert response.json()["issues"][0]["category"] == "power"

    def test_review_no_file_no_path(self):
        response = client.post("/ai/schematic-review", json={})
        assert response.status_code == 400

    def test_review_llm_error(self):
        from gateway.llm_client import LLMClientError
        with patch("gateway.app.llm_chat", new=AsyncMock(side_effect=LLMClientError("down"))):
            response = client.post("/ai/schematic-review", json={"project_path": "tests/fixtures/simple.kicad_sch"})
        assert response.status_code == 502
