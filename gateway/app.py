"""MakeLife CAD Gateway — FastAPI backend for CAD/EDA operations."""

from __future__ import annotations

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

app = FastAPI(
    title="MakeLife CAD Gateway",
    description="EDA gateway for YiACAD, KiCad, FreeCAD, OpenSCAD integrations",
    version="0.1.0",
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.get("/health")
async def health():
    return {"status": "ok", "service": "makelife-cad-gateway"}


@app.get("/tools")
async def list_tools():
    """List available CAD/EDA tools."""
    return {
        "tools": [
            {"name": "kicad", "status": "planned", "description": "KiCad EDA schematic/PCB"},
            {"name": "freecad", "status": "planned", "description": "FreeCAD 3D parametric"},
            {"name": "openscad", "status": "planned", "description": "OpenSCAD programmatic 3D"},
            {"name": "yiacad", "status": "planned", "description": "YiACAD AI-assisted design"},
        ]
    }
