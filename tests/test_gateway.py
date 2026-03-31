"""Tests for makelife-cad gateway."""

import pytest
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


def test_get_tool():
    response = client.get("/tools/kicad")
    assert response.status_code == 200
    assert response.json()["name"] == "KiCad"


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
