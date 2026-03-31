"""MakeLife CAD Gateway — FastAPI backend for CAD/EDA operations."""

from __future__ import annotations

import logging
import os
from typing import Any

from fastapi import FastAPI, HTTPException, UploadFile, File
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel

logger = logging.getLogger("makelife_cad.gateway")

app = FastAPI(
    title="MakeLife CAD Gateway",
    description="EDA gateway for YiACAD, KiCad, FreeCAD, OpenSCAD integrations",
    version="0.1.0",
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=os.environ.get("ALLOWED_ORIGINS", "*").split(","),
    allow_methods=["*"],
    allow_headers=["*"],
)

# Tool registry
TOOLS = {
    "kicad": {
        "name": "KiCad",
        "description": "Electronic Design Automation — schematic + PCB",
        "version": "8.0",
        "capabilities": ["schematic", "pcb", "bom", "gerber", "drc", "erc"],
        "status": "available",
    },
    "freecad": {
        "name": "FreeCAD",
        "description": "3D parametric CAD modeling",
        "version": "1.0",
        "capabilities": ["3d_model", "mesh", "step_export", "stl_export"],
        "status": "available",
    },
    "openscad": {
        "name": "OpenSCAD",
        "description": "Programmatic 3D CAD with CSG",
        "version": "2024.12",
        "capabilities": ["csg", "stl_export", "parametric"],
        "status": "available",
    },
    "yiacad": {
        "name": "YiACAD",
        "description": "AI-assisted design orchestrator",
        "version": "0.1.0",
        "capabilities": ["ai_design", "component_suggest", "layout_optimize"],
        "status": "planned",
    },
}


# Models
class DesignRequest(BaseModel):
    tool: str
    action: str
    parameters: dict[str, Any] = {}
    context: dict[str, Any] = {}


class DesignResult(BaseModel):
    tool: str
    action: str
    status: str
    result: dict[str, Any] = {}
    artifacts: list[str] = []


class ComponentQuery(BaseModel):
    query: str
    category: str | None = None
    package: str | None = None
    limit: int = 10


class BOMEntry(BaseModel):
    reference: str
    value: str
    footprint: str
    quantity: int = 1
    supplier: str | None = None
    part_number: str | None = None


# Endpoints
@app.get("/health")
async def health():
    return {"status": "ok", "service": "makelife-cad-gateway", "tools": len(TOOLS)}


@app.get("/tools")
async def list_tools():
    """List available CAD/EDA tools and their capabilities."""
    return {"tools": list(TOOLS.values())}


@app.get("/tools/{tool_id}")
async def get_tool(tool_id: str):
    """Get details for a specific tool."""
    if tool_id not in TOOLS:
        raise HTTPException(status_code=404, detail=f"Tool '{tool_id}' not found")
    return TOOLS[tool_id]


@app.post("/design", response_model=DesignResult)
async def execute_design(request: DesignRequest):
    """Execute a design action on a CAD tool."""
    if request.tool not in TOOLS:
        raise HTTPException(status_code=404, detail=f"Tool '{request.tool}' not found")

    tool = TOOLS[request.tool]
    if request.action not in tool["capabilities"]:
        raise HTTPException(
            status_code=400,
            detail=f"Action '{request.action}' not supported by {request.tool}. Available: {tool['capabilities']}",
        )

    # Dispatch to tool-specific handler (placeholder for now)
    logger.info(f"Design request: tool={request.tool} action={request.action}")

    return DesignResult(
        tool=request.tool,
        action=request.action,
        status="queued",
        result={"message": f"Action '{request.action}' queued for {request.tool}"},
    )


@app.post("/components/search")
async def search_components(query: ComponentQuery):
    """Search electronic components (stub — will connect to component DB)."""
    return {
        "query": query.query,
        "results": [
            {
                "name": f"Example {query.query}",
                "category": query.category or "passive",
                "package": query.package or "0402",
                "manufacturer": "Example Mfg",
                "datasheet_url": None,
            }
        ],
        "total": 1,
    }


@app.post("/bom/validate")
async def validate_bom(entries: list[BOMEntry]):
    """Validate a Bill of Materials."""
    issues = []
    for entry in entries:
        if not entry.value:
            issues.append({"reference": entry.reference, "issue": "Missing value"})
        if not entry.footprint:
            issues.append({"reference": entry.reference, "issue": "Missing footprint"})

    return {
        "total_entries": len(entries),
        "valid": len(entries) - len(issues),
        "issues": issues,
        "status": "pass" if not issues else "fail",
    }


@app.get("/projects")
async def list_projects():
    """List CAD projects (stub)."""
    return {
        "projects": [
            {
                "id": "makelife-main",
                "name": "MakeLife Main Board",
                "tool": "kicad",
                "status": "in_progress",
                "last_modified": "2026-03-31",
            }
        ]
    }


if __name__ == "__main__":
    import uvicorn
    uvicorn.run("gateway.app:app", host="0.0.0.0", port=8001, reload=True)
