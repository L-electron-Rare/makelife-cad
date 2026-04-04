"""Tests for makelife-cad gateway."""

import pytest
from unittest.mock import AsyncMock, patch
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


def test_design_request_kicad_schematic_not_implemented():
    """kicad+schematic is in the capabilities list but has no dispatcher yet — returns 400."""
    response = client.post("/design", json={
        "tool": "kicad",
        "action": "schematic",
        "parameters": {},
    })
    assert response.status_code == 400


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


def test_bom_validate_valid_lcsc_part():
    """BOM entry with a valid LCSC part format should pass without issues."""
    response = client.post("/bom/validate", json=[
        {"reference": "U1", "value": "ESP32", "footprint": "QFN-48", "lcsc_part": "C701341"},
    ])
    assert response.status_code == 200
    data = response.json()
    assert data["status"] == "pass"
    assert data["issues"] == []


def test_bom_validate_invalid_lcsc_part():
    """BOM entry with a malformed LCSC part number should produce an issue."""
    response = client.post("/bom/validate", json=[
        {"reference": "R1", "value": "10k", "footprint": "0402", "lcsc_part": "INVALID"},
    ])
    assert response.status_code == 200
    data = response.json()
    assert data["status"] == "fail"
    assert any("LCSC" in issue["issue"] for issue in data["issues"])


def test_bom_validate_no_availability_check_by_default():
    """Without check_availability=true, no HTTP calls should be made."""
    with patch("gateway.app._check_lcsc_availability", new_callable=AsyncMock) as mock_check:
        response = client.post("/bom/validate", json=[
            {"reference": "U1", "value": "ESP32", "footprint": "QFN-48", "lcsc_part": "C701341"},
        ])
    assert response.status_code == 200
    mock_check.assert_not_called()
    assert "availability" not in response.json()


def test_bom_validate_with_availability_check():
    """With check_availability=true, _check_lcsc_availability should be called and results returned."""
    mock_result = {"available": True, "stock": 500}
    with patch("gateway.app._check_lcsc_availability", new_callable=AsyncMock, return_value=mock_result) as mock_check:
        response = client.post(
            "/bom/validate?check_availability=true",
            json=[
                {"reference": "U1", "value": "ESP32", "footprint": "QFN-48", "lcsc_part": "C701341"},
            ],
        )
    assert response.status_code == 200
    data = response.json()
    assert data["status"] == "pass"
    mock_check.assert_called_once_with("C701341")
    assert data["availability"]["U1"] == mock_result


# --- /design dispatcher tests ---

def test_design_dispatch_kicad_drc():
    """kicad+drc should dispatch to the DRC handler and return completed status."""
    with patch("subprocess.run") as mock_run:
        mock_run.return_value.returncode = 0
        mock_run.return_value.stdout = "DRC complete"
        mock_run.return_value.stderr = ""
        response = client.post("/design", json={
            "tool": "kicad",
            "action": "drc",
            "parameters": {"project_path": "hardware/makelife-main/makelife-main.kicad_pcb"},
        })
    assert response.status_code == 200
    data = response.json()
    assert data["tool"] == "kicad"
    assert data["action"] == "drc"
    assert data["status"] == "completed"
    assert "returncode" in data["result"]


def test_design_dispatch_kicad_export_svg():
    """kicad+export-svg should dispatch to the SVG export handler."""
    with patch("subprocess.run") as mock_run:
        mock_run.return_value.returncode = 0
        mock_run.return_value.stdout = ""
        mock_run.return_value.stderr = ""
        response = client.post("/design", json={
            "tool": "kicad",
            "action": "export-svg",
            "parameters": {"project_path": "hardware/makelife-main/makelife-main.kicad_sch"},
        })
    assert response.status_code == 200
    data = response.json()
    assert data["tool"] == "kicad"
    assert data["action"] == "export-svg"
    assert data["status"] == "completed"


def test_design_dispatch_bom_validate():
    """bom+validate should dispatch to the BOM validation handler."""
    response = client.post("/design", json={
        "tool": "bom",
        "action": "validate",
        "parameters": {
            "entries": [
                {"reference": "R1", "value": "10k", "footprint": "0402"},
                {"reference": "C1", "value": "", "footprint": ""},
            ]
        },
    })
    assert response.status_code == 200
    data = response.json()
    assert data["tool"] == "bom"
    assert data["action"] == "validate"
    assert data["status"] == "error"  # fail normalised to error
    assert data["result"]["total_entries"] == 2
    assert len(data["result"]["issues"]) == 2


def test_design_dispatch_unknown_tool():
    """Completely unknown tool should return 404."""
    response = client.post("/design", json={
        "tool": "nonexistent",
        "action": "drc",
    })
    assert response.status_code == 404


def test_design_dispatch_unknown_action_for_known_tool():
    """Known tool but unknown action (not in capabilities or dispatch table) returns 400."""
    response = client.post("/design", json={
        "tool": "kicad",
        "action": "totally-unknown-action",
    })
    assert response.status_code == 400


def test_design_dispatch_kicad_drc_kicad_cli_unavailable():
    """When kicad-cli is not installed, dispatch returns 200 with status=error and message in result."""
    with patch("subprocess.run", side_effect=FileNotFoundError):
        response = client.post("/design", json={
            "tool": "kicad",
            "action": "drc",
            "parameters": {},
        })
    assert response.status_code == 200
    data = response.json()
    assert data["status"] == "error"
    assert "kicad-cli" in data["result"].get("message", "").lower()
