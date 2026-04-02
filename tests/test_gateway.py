"""Tests for makelife-cad gateway."""

import pytest
from unittest.mock import patch
from fastapi.testclient import TestClient
from gateway.app import app

client = TestClient(app)


def test_health():
    response = client.get("/health")
    assert response.status_code == 200
    data = response.json()
    assert data["status"] == "ok"
    assert data["tools"] == 4


def test_list_tools():
    response = client.get("/tools")
    assert response.status_code == 200
    tools = response.json()["tools"]
    assert len(tools) == 4
    names = [t["name"] for t in tools]
    assert "KiCad" in names
    assert "FreeCAD" in names
    assert "YiACAD" in names


def test_get_tool():
    response = client.get("/tools/kicad")
    assert response.status_code == 200
    assert response.json()["name"] == "KiCad"


def test_get_tool_yiacad_has_runtime_status():
    response = client.get("/tools/yiacad")
    assert response.status_code == 200
    data = response.json()
    assert data["name"] == "YiACAD"
    assert data["status"] in ("available", "unavailable")


def test_get_tool_not_found():
    response = client.get("/tools/nonexistent")
    assert response.status_code == 404


def test_design_request():
    response = client.post("/design", json={
        "tool": "kicad",
        "action": "schematic",
        "parameters": {},
    })
    assert response.status_code == 200
    assert response.json()["status"] == "queued"


def test_design_request_yiacad_executes_relay():
    fake_result = {
        "gateway_url": "http://127.0.0.1:8100",
        "route": "/components/search",
        "payload": {"query": "esp32", "limit": 5},
        "response": {"ok": True, "items": []},
    }
    with patch("gateway.app.yiacad_execute_action") as mock_exec:
        mock_exec.return_value = fake_result
        response = client.post("/design", json={
            "tool": "yiacad",
            "action": "component_suggest",
            "parameters": {"query": "esp32", "limit": 5},
        })

    assert response.status_code == 200
    data = response.json()
    assert data["status"] == "done"
    assert data["result"]["route"] == "/components/search"
    assert mock_exec.called


def test_design_invalid_action():
    response = client.post("/design", json={
        "tool": "kicad",
        "action": "nonexistent",
    })
    assert response.status_code == 400


def test_bom_validate():
    response = client.post("/bom/validate", json=[
        {"reference": "R1", "value": "10k", "footprint": "0402", "quantity": 1},
        {"reference": "C1", "value": "", "footprint": "0402", "quantity": 1},
    ])
    assert response.status_code == 200
    data = response.json()
    assert data["total_entries"] == 2
    assert len(data["issues"]) == 1


def test_list_projects():
    response = client.get("/projects")
    assert response.status_code == 200
    assert len(response.json()["projects"]) >= 1


def test_yiacad_status_endpoint():
    response = client.get("/yiacad/status")
    assert response.status_code == 200
    data = response.json()
    assert data["status"] in ("available", "unavailable")
    assert "configured_path" in data
    assert "hint" in data


def test_yiacad_health_endpoint():
    with patch("gateway.app.yiacad_gateway_health") as mock_health:
        mock_health.return_value = {
            "path": "/healthz",
            "gateway_url": "http://127.0.0.1:8100",
            "response": {"ok": True},
        }
        response = client.get("/yiacad/health")

    assert response.status_code == 200
    assert response.json()["response"]["ok"] is True


def test_yiacad_relay_endpoint():
    with patch("gateway.app.yiacad_relay") as mock_relay:
        mock_relay.return_value = {
            "method": "POST",
            "path": "/components/search",
            "gateway_url": "http://127.0.0.1:8100",
            "payload": {"query": "resistor"},
            "response": {"results": []},
        }
        response = client.post("/yiacad/relay", json={
            "method": "POST",
            "path": "/components/search",
            "payload": {"query": "resistor"},
        })

    assert response.status_code == 200
    assert response.json()["path"] == "/components/search"


def test_yiacad_ai_status_endpoint():
    with patch("gateway.app.yiacad_relay") as mock_relay:
        mock_relay.return_value = {
            "method": "GET",
            "path": "/ai/status",
            "gateway_url": "http://127.0.0.1:8100",
            "payload": {},
            "response": {"status": "ok"},
        }
        response = client.get("/yiacad/ai/status")

    assert response.status_code == 200
    assert response.json()["path"] == "/ai/status"


def test_yiacad_components_search_endpoint():
    with patch("gateway.app.yiacad_relay") as mock_relay:
        mock_relay.return_value = {
            "method": "POST",
            "path": "/components/search",
            "gateway_url": "http://127.0.0.1:8100",
            "payload": {"query": "stm32"},
            "response": {"results": []},
        }
        response = client.post("/yiacad/components/search", json={"query": "stm32"})

    assert response.status_code == 200
    assert response.json()["path"] == "/components/search"


def test_yiacad_status_with_env_override_unavailable(monkeypatch, tmp_path):
    custom_path = tmp_path / "missing_yiacad"
    monkeypatch.setenv("YIACAD_DIR", str(custom_path))

    response = client.get("/yiacad/status")
    assert response.status_code == 200
    data = response.json()
    assert data["configured_path"] == str(custom_path)
    assert data["status"] == "unavailable"


def test_yiacad_status_with_env_override_available(monkeypatch, tmp_path):
    yiacad_dir = tmp_path / "yiacad"
    yiacad_dir.mkdir()
    monkeypatch.setenv("YIACAD_DIR", str(yiacad_dir))

    response = client.get("/yiacad/status")
    assert response.status_code == 200
    data = response.json()
    assert data["configured_path"] == str(yiacad_dir)
    assert data["resolved_exists"] is True
    assert data["status"] == "available"


def test_kicad_drc_unavailable():
    """DRC should return unavailable when kicad-cli is not installed."""
    response = client.post("/kicad/drc")
    assert response.status_code == 200
    assert response.json()["status"] in ("unavailable", "fail", "pass")


def test_kicad_export_unavailable():
    response = client.get("/kicad/export/svg")
    assert response.status_code == 200
    assert response.json()["status"] in ("unavailable", "error", "ok")


def test_kicad_drc_custom_path_forwarded():
    with patch("subprocess.run") as mock_run:
        mock_run.return_value.returncode = 0
        mock_run.return_value.stdout = "ok"
        mock_run.return_value.stderr = ""

        target = "tests/fixtures/simple.kicad_pcb"
        response = client.post("/kicad/drc", params={"project_path": target})

        assert response.status_code == 200
        assert response.json()["status"] == "pass"
        args = mock_run.call_args.args[0]
        assert target in args
