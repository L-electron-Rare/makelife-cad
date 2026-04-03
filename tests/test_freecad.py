"""Tests for FreeCAD integration endpoints and runtime status."""
from unittest.mock import patch

from fastapi.testclient import TestClient

from gateway.app import app
from gateway.freecad_runner import FreecadExportError

client = TestClient(app)


def test_freecad_status_unavailable():
    with patch("gateway.app.freecad_runtime_status") as mock_status:
        mock_status.return_value = {
            "status": "unavailable",
            "installed": False,
            "version": None,
            "compatible": False,
            "path": None,
            "source": "unavailable",
            "preferred_export_mode": "unavailable",
        }
        response = client.get("/freecad/status")

    assert response.status_code == 200
    data = response.json()
    assert data["installed"] is False
    assert data["status"] == "unavailable"


def test_freecad_status_compatible_target_version():
    with patch("gateway.app.freecad_runtime_status") as mock_status:
        mock_status.return_value = {
            "status": "available",
            "installed": True,
            "version": "1.1.0",
            "compatible": True,
            "path": "/Applications/FreeCAD.app/Contents/MacOS/FreeCADCmd",
            "source": "app_bundle",
            "preferred_export_mode": "gateway",
        }
        response = client.get("/freecad/status")

    assert response.status_code == 200
    data = response.json()
    assert data["compatible"] is True
    assert data["version"] == "1.1.0"


def test_freecad_status_compatible_patch_version():
    with patch("gateway.app.freecad_runtime_status") as mock_status:
        mock_status.return_value = {
            "status": "available",
            "installed": True,
            "version": "1.1.2",
            "compatible": True,
            "path": "/usr/local/bin/freecadcmd",
            "source": "path",
            "preferred_export_mode": "gateway",
        }
        response = client.get("/freecad/status")

    assert response.status_code == 200
    assert response.json()["version"] == "1.1.2"


def test_freecad_status_incompatible_version():
    with patch("gateway.app.freecad_runtime_status") as mock_status:
        mock_status.return_value = {
            "status": "incompatible",
            "installed": True,
            "version": "1.2.0",
            "compatible": False,
            "path": "/usr/local/bin/freecadcmd",
            "source": "path",
            "preferred_export_mode": "unavailable",
        }
        response = client.get("/freecad/status")

    assert response.status_code == 200
    data = response.json()
    assert data["status"] == "incompatible"
    assert data["compatible"] is False


def test_freecad_tool_snapshot_includes_runtime_fields():
    with patch("gateway.app.freecad_runtime_status") as mock_status:
        mock_status.return_value = {
            "status": "available",
            "installed": True,
            "version": "1.1.0",
            "compatible": True,
            "path": "/usr/local/bin/freecadcmd",
            "source": "path",
            "preferred_export_mode": "gateway",
        }
        response = client.get("/tools/freecad")

    assert response.status_code == 200
    data = response.json()
    assert data["status"] == "available"
    assert data["version"] == "1.1.0"
    assert data["preferred_export_mode"] == "gateway"


def test_freecad_export_calls_runner():
    fake_result = {
        "status": "ok",
        "output_path": "/tmp/out.step",
        "returncode": 0,
        "stdout": "done",
        "stderr": "",
        "version_used": "1.1.0",
        "source": "app_bundle",
    }
    with patch("gateway.app.freecad_export_model") as mock_export:
        mock_export.return_value = fake_result
        response = client.post(
            "/freecad/export",
            json={"input_path": "tests/fixtures/simple.kicad_sch", "format": "step"},
        )

    assert response.status_code == 200
    data = response.json()
    assert data["output_path"] == "/tmp/out.step"
    assert data["version_used"] == "1.1.0"
    assert data["source"] == "app_bundle"
    mock_export.assert_called_once()


def test_freecad_export_invalid_path():
    response = client.post("/freecad/export", json={"input_path": "missing/file.FCStd"})
    assert response.status_code == 400


def test_freecad_export_incompatible_runtime():
    with patch("gateway.app.freecad_export_model", side_effect=FreecadExportError("Incompatible FreeCAD version")):
        response = client.post(
            "/freecad/export",
            json={"input_path": "tests/fixtures/simple.kicad_sch", "format": "step"},
        )
    assert response.status_code == 409


def test_freecad_export_missing_runtime():
    with patch("gateway.app.freecad_export_model", side_effect=FileNotFoundError("FreeCAD CLI not found")):
        response = client.post(
            "/freecad/export",
            json={"input_path": "tests/fixtures/simple.kicad_sch", "format": "step"},
        )
    assert response.status_code == 400
