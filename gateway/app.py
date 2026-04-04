"""MakeLife CAD Gateway — FastAPI backend for CAD/EDA operations."""

from __future__ import annotations

import json as json_module
import logging
import os
import re
from pathlib import Path
from typing import Any

import httpx
from fastapi import FastAPI, HTTPException, Query, Request
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel

from gateway.freecad_runner import (
    detect_runtime_status as freecad_runtime_status,
    export_model as freecad_export_model,
    FreecadExportError,
)
from gateway.llm_client import chat as llm_chat, LLMClientError
from gateway.kicad_parser import parse_schematic, SchematicContext
from gateway.prompts import build_component_prompt, build_review_prompt
from gateway.yiacad_client import (
    YiacadClientError,
    execute_action as yiacad_execute_action,
    gateway_health as yiacad_gateway_health,
    relay as yiacad_relay,
)
from gateway.routers import kicad as kicad_router

logger = logging.getLogger("makelife_cad.gateway")

PROJECT_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_YIACAD_DIR = PROJECT_ROOT / "vendor" / "yiacad"


def init_telemetry(app_instance):
    """Initialize OTEL auto-instrumentation for FastAPI if endpoint is configured."""
    endpoint = os.getenv("OTEL_EXPORTER_OTLP_ENDPOINT")
    if not endpoint:
        return

    try:
        from opentelemetry import trace
        from opentelemetry.sdk.trace import TracerProvider
        from opentelemetry.sdk.trace.export import BatchSpanProcessor
        from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter
        from opentelemetry.sdk.resources import Resource
        from opentelemetry.instrumentation.fastapi import FastAPIInstrumentor

        resource = Resource.create({"service.name": os.getenv("OTEL_SERVICE_NAME", "makelife-cad")})
        provider = TracerProvider(resource=resource)
        provider.add_span_processor(BatchSpanProcessor(OTLPSpanExporter(endpoint=endpoint, insecure=True)))
        trace.set_tracer_provider(provider)

        FastAPIInstrumentor.instrument_app(app_instance)
    except ImportError:
        pass


app = FastAPI(
    title="MakeLife CAD Gateway",
    description="EDA gateway for YiACAD, KiCad, FreeCAD, OpenSCAD integrations",
    version="0.1.0",
)

init_telemetry(app)

app.include_router(kicad_router.router)

app.add_middleware(
    CORSMiddleware,
    allow_origins=os.environ.get("ALLOWED_ORIGINS", "https://cad.saillant.cc,https://life.saillant.cc").split(","),
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
        "version": "1.1.0",
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


def _yiacad_dir() -> Path:
    """Resolve YiACAD location from env or default vendor path."""
    return Path(os.getenv("YIACAD_DIR", str(DEFAULT_YIACAD_DIR))).expanduser()


def yiacad_status() -> dict[str, Any]:
    """Return runtime status of YiACAD integration for diagnostics and tool listing."""
    yiacad_dir = _yiacad_dir()
    exists = yiacad_dir.exists()
    is_symlink = yiacad_dir.is_symlink()
    resolved_path = yiacad_dir.resolve() if exists else yiacad_dir
    resolved_exists = resolved_path.exists()

    status = "available" if exists and resolved_exists else "unavailable"
    return {
        "status": status,
        "configured_path": str(yiacad_dir),
        "resolved_path": str(resolved_path),
        "exists": exists,
        "is_symlink": is_symlink,
        "resolved_exists": resolved_exists,
        "hint": "make yiacad-link YIACAD_DIR=../YiACAD",
    }


def freecad_status() -> dict[str, Any]:
    """Detect FreeCAD CLI availability for runtime tool registry."""
    status = freecad_runtime_status()
    status["hint"] = "Install FreeCAD 1.1.x locally or set FREECAD_CMD"
    return status


def tools_snapshot() -> dict[str, dict[str, Any]]:
    """Return tool registry with runtime-updated values."""
    snapshot = {key: value.copy() for key, value in TOOLS.items()}
    snapshot["yiacad"].update(yiacad_status())
    snapshot["freecad"].update(freecad_status())
    return snapshot


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
    lcsc_part: str | None = None


class YiacadRelayRequest(BaseModel):
    method: str = "GET"
    path: str
    payload: dict[str, Any] = {}


class FreecadExportRequest(BaseModel):
    input_path: str
    format: str = "step"  # step | stl
    output_dir: str | None = None


# Design action dispatcher
# Maps (tool, action) → internal handler coroutine.
# Handlers must return a dict compatible with DesignResult.result.
# Raise HTTPException(400) for unknown combinations.

async def _dispatch_kicad_drc(params: dict[str, Any]) -> dict[str, Any]:
    import subprocess
    project_path = params.get("project_path", "hardware/makelife-main/makelife-main.kicad_pcb")
    try:
        result = subprocess.run(
            ["kicad-cli", "pcb", "drc", "--output", "/tmp/drc-report.json", project_path],
            capture_output=True, text=True, timeout=30,
        )
        return {
            "status": "pass" if result.returncode == 0 else "fail",
            "returncode": result.returncode,
            "stdout": result.stdout[:500],
            "stderr": result.stderr[:500],
        }
    except FileNotFoundError:
        return {"status": "unavailable", "message": "kicad-cli not installed"}
    except subprocess.TimeoutExpired:
        return {"status": "timeout", "message": "DRC took too long"}


async def _dispatch_kicad_export_svg(params: dict[str, Any]) -> dict[str, Any]:
    import subprocess
    project_path = params.get("project_path", "hardware/makelife-main/makelife-main.kicad_sch")
    output_dir = params.get("output_dir", "/tmp/")
    try:
        result = subprocess.run(
            ["kicad-cli", "sch", "export", "svg", "--output", output_dir, project_path],
            capture_output=True, text=True, timeout=30,
        )
        return {
            "status": "ok" if result.returncode == 0 else "error",
            "returncode": result.returncode,
            "output": result.stdout[:500],
            "stderr": result.stderr[:500],
        }
    except FileNotFoundError:
        return {"status": "unavailable", "message": "kicad-cli not installed"}
    except subprocess.TimeoutExpired:
        return {"status": "timeout", "message": "SVG export took too long"}


async def _dispatch_kicad_parse(params: dict[str, Any]) -> dict[str, Any]:
    project_path = params.get("project_path")
    if not project_path:
        return {"status": "error", "message": "project_path is required for parse action"}
    resolved = _safe_resolve(project_path)
    if resolved is None:
        return {"status": "error", "message": "Invalid or out-of-scope project_path"}
    try:
        content = resolved.read_text()
        ctx: SchematicContext = parse_schematic(content)
        return {
            "status": "ok",
            "components": len(ctx.components),
            "nets": len(ctx.nets),
            "component_list": [c for c in ctx.components[:50]],
            "net_list": [n for n in ctx.nets[:50]],
        }
    except Exception as exc:
        return {"status": "error", "message": str(exc)}


async def _dispatch_freecad_export(params: dict[str, Any]) -> dict[str, Any]:
    input_path = params.get("input_path")
    if not input_path:
        return {"status": "error", "message": "input_path is required for freecad export"}
    resolved_input = _safe_resolve(input_path)
    if resolved_input is None:
        return {"status": "error", "message": "Invalid or out-of-scope input_path"}
    output_dir = None
    if params.get("output_dir"):
        output_dir = _safe_resolve(params["output_dir"])
        if output_dir is None:
            return {"status": "error", "message": "Invalid or out-of-scope output_dir"}
    try:
        result = freecad_export_model(
            input_path=resolved_input,
            fmt=params.get("format", "step"),
            output_dir=output_dir,
        )
        return result
    except FileNotFoundError as exc:
        return {"status": "error", "message": str(exc)}
    except FreecadExportError as exc:
        return {"status": "error", "message": str(exc)}
    except Exception as exc:
        return {"status": "error", "message": f"FreeCAD export failed: {exc}"}


async def _dispatch_bom_validate(params: dict[str, Any]) -> dict[str, Any]:
    entries_raw = params.get("entries", [])
    issues = []
    for entry in entries_raw:
        ref = entry.get("reference", "?")
        if not entry.get("value"):
            issues.append({"reference": ref, "issue": "Missing value"})
        if not entry.get("footprint"):
            issues.append({"reference": ref, "issue": "Missing footprint"})
    return {
        "status": "pass" if not issues else "fail",
        "total_entries": len(entries_raw),
        "valid": len(entries_raw) - len(issues),
        "issues": issues,
    }


async def _dispatch_ai_component_suggest(params: dict[str, Any]) -> dict[str, Any]:
    description = params.get("description", "")
    constraints = params.get("constraints", {})
    project_context = params.get("project_context")

    project_ctx = None
    if project_context:
        try:
            ctx_path = _safe_resolve(project_context)
            if ctx_path is not None:
                project_ctx = parse_schematic(ctx_path.read_text())
        except Exception as exc:
            logger.warning("Failed to parse project context: %s", exc)

    messages = build_component_prompt(
        description=description,
        constraints=constraints or None,
        project_context=project_ctx,
    )
    try:
        import json as _json
        raw = await llm_chat(messages=messages, model=AI_COMPONENT_MODEL)
        try:
            suggestions = _json.loads(raw)
        except (_json.JSONDecodeError, TypeError):
            suggestions = [{"name": "raw_response", "reason": raw[:500]}]
        return {
            "status": "ok",
            "suggestions": suggestions,
            "model_used": AI_COMPONENT_MODEL,
            "context_used": project_ctx is not None,
        }
    except LLMClientError as exc:
        return {"status": "error", "message": f"LLM service error: {exc}"}


async def _dispatch_ai_schematic_review(params: dict[str, Any]) -> dict[str, Any]:
    project_path = params.get("project_path")
    if not project_path:
        return {"status": "error", "message": "project_path is required for schematic-review"}
    resolved = _safe_resolve(project_path)
    if resolved is None:
        return {"status": "error", "message": "Invalid or out-of-scope project_path"}
    try:
        content = resolved.read_text()
    except OSError as exc:
        return {"status": "error", "message": str(exc)}

    schematic = parse_schematic(content)
    focus = params.get("focus")
    messages = build_review_prompt(schematic, focus=focus)

    model = AI_REVIEW_MODEL
    try:
        import json as _json
        raw = await llm_chat(messages=messages, model=model)
        try:
            issues = _json.loads(raw)
        except (_json.JSONDecodeError, TypeError):
            issues = [{"severity": "info", "category": "parse_error", "message": raw[:200]}]
        high = sum(1 for i in issues if i.get("severity") == "high")
        medium = sum(1 for i in issues if i.get("severity") == "medium")
        low = sum(1 for i in issues if i.get("severity") == "low")
        return {
            "status": "ok",
            "issues": issues,
            "summary": f"{len(issues)} issues found: {high} high, {medium} medium, {low} low",
            "model_used": model,
            "components_analyzed": len(schematic.components),
            "nets_analyzed": len(schematic.nets),
        }
    except LLMClientError as exc:
        return {"status": "error", "message": f"LLM service error: {exc}"}


# Dispatch table: (tool, action) → async handler(params) -> dict
_DISPATCH_TABLE: dict[tuple[str, str], Any] = {
    ("kicad", "drc"): _dispatch_kicad_drc,
    ("kicad", "export-svg"): _dispatch_kicad_export_svg,
    ("kicad", "parse"): _dispatch_kicad_parse,
    ("freecad", "export"): _dispatch_freecad_export,
    ("bom", "validate"): _dispatch_bom_validate,
    ("ai", "component-suggest"): _dispatch_ai_component_suggest,
    ("ai", "schematic-review"): _dispatch_ai_schematic_review,
}


async def _dispatch_design_action(request: "DesignRequest") -> "DesignResult":
    """Dispatch a design request to the appropriate real handler."""
    key = (request.tool, request.action)
    handler = _DISPATCH_TABLE.get(key)
    if handler is None:
        raise HTTPException(
            status_code=400,
            detail=f"Action '{request.action}' is not yet implemented for tool '{request.tool}'",
        )
    params = {**(request.context or {}), **(request.parameters or {})}
    result = await handler(params)
    status = result.pop("status", "completed") if isinstance(result, dict) else "completed"
    # Normalise status to completed/error for backward compatibility
    if status not in ("completed", "error"):
        status = "completed" if status not in ("error", "fail", "unavailable", "timeout") else "error"
    return DesignResult(
        tool=request.tool,
        action=request.action,
        status=status,
        result=result,
    )


# Endpoints
@app.get("/health")
async def health():
    y_status = yiacad_status()
    return {
        "status": "ok",
        "service": "makelife-cad-gateway",
        "tools": len(TOOLS),
        "yiacad_status": y_status["status"],
    }


@app.get("/tools")
async def list_tools():
    """List available CAD/EDA tools and their capabilities."""
    return {"tools": list(tools_snapshot().values())}


@app.get("/tools/{tool_id}")
async def get_tool(tool_id: str):
    """Get details for a specific tool."""
    runtime_tools = tools_snapshot()
    if tool_id not in runtime_tools:
        raise HTTPException(status_code=404, detail=f"Tool '{tool_id}' not found")
    return runtime_tools[tool_id]


@app.get("/yiacad/status")
async def get_yiacad_status():
    """Return integration status for local YiACAD repository/link."""
    return yiacad_status()


@app.get("/yiacad/health")
async def get_yiacad_health():
    """Probe the YiACAD gateway availability from makelife-cad."""
    try:
        return await yiacad_gateway_health()
    except YiacadClientError as e:
        raise HTTPException(status_code=502, detail=f"YiACAD health check failed: {e}")


@app.post("/yiacad/relay")
async def relay_to_yiacad(request: YiacadRelayRequest):
    """Generic relay for any YiACAD gateway endpoint."""
    try:
        return await yiacad_relay(request.method, request.path, request.payload)
    except YiacadClientError as e:
        raise HTTPException(status_code=502, detail=f"YiACAD relay failed: {e}")


@app.post("/design", response_model=DesignResult)
async def execute_design(request: DesignRequest):
    """Execute a design action on a CAD tool."""
    # Accept any (tool, action) pair that is in the dispatch table OR the TOOLS registry.
    dispatch_key = (request.tool, request.action)
    in_dispatch = dispatch_key in _DISPATCH_TABLE
    in_tools_registry = request.tool in TOOLS

    if not in_dispatch and not in_tools_registry:
        raise HTTPException(status_code=404, detail=f"Tool '{request.tool}' not found")

    if not in_dispatch and in_tools_registry:
        tool = TOOLS[request.tool]
        if request.action not in tool["capabilities"]:
            raise HTTPException(
                status_code=400,
                detail=f"Action '{request.action}' not supported by {request.tool}. Available: {tool['capabilities']}",
            )

    logger.info(f"Design request: tool={request.tool} action={request.action}")

    if request.tool == "yiacad":
        try:
            relay_result = await yiacad_execute_action(
                action=request.action,
                payload={
                    **(request.context or {}),
                    **(request.parameters or {}),
                },
            )
        except YiacadClientError as e:
            raise HTTPException(status_code=502, detail=f"YiACAD execution failed: {e}")

        yiacad_response = relay_result.get("response", {})
        status = "done" if yiacad_response.get("ok", True) else "error"
        return DesignResult(
            tool=request.tool,
            action=request.action,
            status=status,
            result={
                "gateway_url": relay_result.get("gateway_url"),
                "route": relay_result.get("route"),
                "payload": relay_result.get("payload"),
                "response": yiacad_response,
            },
        )

    return await _dispatch_design_action(request)


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


_LCSC_PART_RE = re.compile(r"^C[0-9]+$")

_JLCPCB_API_URL = (
    "https://jlcpcb.com/api/overseas-pcb-order/v1/shoppingCart/smtGood/selectSmtComponentList"
)


async def _check_lcsc_availability(part_number: str) -> dict:
    """Query JLCPCB parts API for stock availability of a LCSC part number."""
    try:
        async with httpx.AsyncClient(timeout=5.0) as client:
            resp = await client.post(
                _JLCPCB_API_URL,
                json={"keyword": part_number, "pageSize": 1, "currentPage": 1},
            )
            resp.raise_for_status()
            data = resp.json()
            # Response shape: {"data": {"list": [{"stockCount": N, ...}], "total": N}, ...}
            items = (data.get("data") or {}).get("list") or []
            if items:
                stock = items[0].get("stockCount", 0)
                return {"available": stock > 0, "stock": stock}
            return {"available": False, "stock": 0}
    except Exception:
        return {"available": None, "error": "lookup failed"}


@app.post("/bom/validate")
async def validate_bom(
    entries: list[BOMEntry],
    check_availability: bool = Query(False, description="Query JLCPCB for LCSC part availability"),
):
    """Validate a Bill of Materials."""
    issues = []
    availability: dict[str, dict] = {}

    for entry in entries:
        if not entry.value:
            issues.append({"reference": entry.reference, "issue": "Missing value"})
        if not entry.footprint:
            issues.append({"reference": entry.reference, "issue": "Missing footprint"})
        if entry.lcsc_part is not None:
            if not _LCSC_PART_RE.match(entry.lcsc_part):
                issues.append({
                    "reference": entry.reference,
                    "issue": f"Invalid LCSC part format: '{entry.lcsc_part}' (expected C[0-9]+)",
                })
            elif check_availability:
                availability[entry.reference] = await _check_lcsc_availability(entry.lcsc_part)

    result: dict[str, Any] = {
        "total_entries": len(entries),
        "valid": len(entries) - len(issues),
        "issues": issues,
        "status": "pass" if not issues else "fail",
    }
    if availability:
        result["availability"] = availability
    return result


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


@app.post("/kicad/drc")
async def run_drc(project_path: str = "hardware/makelife-main/makelife-main.kicad_pcb"):
    """Run KiCad DRC on a project (requires kicad-cli on the host)."""
    import subprocess
    try:
        result = subprocess.run(
            ["kicad-cli", "pcb", "drc", "--output", "/tmp/drc-report.json", project_path],
            capture_output=True, text=True, timeout=30,
        )
        return {
            "status": "pass" if result.returncode == 0 else "fail",
            "returncode": result.returncode,
            "stdout": result.stdout[:500],
            "stderr": result.stderr[:500],
        }
    except FileNotFoundError:
        return {"status": "unavailable", "message": "kicad-cli not installed"}
    except subprocess.TimeoutExpired:
        return {"status": "timeout", "message": "DRC took too long"}


@app.get("/kicad/export/svg")
async def export_svg(project_path: str = "hardware/makelife-main/makelife-main.kicad_sch"):
    """Export schematic to SVG (requires kicad-cli)."""
    import subprocess
    try:
        result = subprocess.run(
            ["kicad-cli", "sch", "export", "svg", "--output", "/tmp/", project_path],
            capture_output=True, text=True, timeout=30,
        )
        return {
            "status": "ok" if result.returncode == 0 else "error",
            "returncode": result.returncode,
            "output": result.stdout[:500],
        }
    except FileNotFoundError:
        return {"status": "unavailable", "message": "kicad-cli not installed"}


# --- AI-assisted endpoints ---

CAD_PROJECTS_DIR = Path(os.getenv("CAD_PROJECTS_DIR", "/projects"))


def _safe_resolve(user_path: str) -> Path | None:
    """Resolve a user-provided path, ensuring it stays under CAD_PROJECTS_DIR or cwd."""
    candidate = CAD_PROJECTS_DIR / user_path
    if not candidate.exists():
        candidate = Path(user_path)
    try:
        resolved = candidate.resolve(strict=True)
    except (OSError, ValueError):
        return None
    # Allow paths under CAD_PROJECTS_DIR or under the project root
    allowed_roots = [CAD_PROJECTS_DIR.resolve(), PROJECT_ROOT]
    if not any(str(resolved).startswith(str(root)) for root in allowed_roots):
        return None
    return resolved


AI_COMPONENT_MODEL = os.getenv("AI_COMPONENT_MODEL", "openai/qwen-14b-awq")
AI_REVIEW_MODEL = os.getenv("AI_REVIEW_MODEL", "openai/mascarade-kicad")
AI_REVIEW_FALLBACK = os.getenv("AI_REVIEW_FALLBACK_MODEL", "openai/qwen-14b-awq")


class ComponentSuggestRequest(BaseModel):
    description: str
    constraints: dict[str, str] = {}
    project_context: str | None = None


class ComponentSuggestion(BaseModel):
    name: str
    manufacturer: str = ""
    package: str = ""
    key_specs: dict[str, str] = {}
    reason: str = ""


class ComponentSuggestResponse(BaseModel):
    suggestions: list[ComponentSuggestion]
    model_used: str
    context_used: bool


@app.post("/ai/component-suggest", response_model=ComponentSuggestResponse)
async def component_suggest(request: ComponentSuggestRequest):
    """AI-powered electronic component suggestion."""
    project_ctx = None
    if request.project_context:
        try:
            ctx_path = _safe_resolve(request.project_context)
            if ctx_path is not None:
                project_ctx = parse_schematic(ctx_path.read_text())
        except Exception as e:
            logger.warning("Failed to parse project context: %s", e)

    messages = build_component_prompt(
        description=request.description,
        constraints=request.constraints or None,
        project_context=project_ctx,
    )

    try:
        raw = await llm_chat(messages=messages, model=AI_COMPONENT_MODEL)
    except LLMClientError as e:
        raise HTTPException(status_code=502, detail=f"LLM service error: {e}")

    try:
        suggestions_raw = json_module.loads(raw)
        suggestions = [ComponentSuggestion(**s) for s in suggestions_raw]
    except (json_module.JSONDecodeError, TypeError, KeyError):
        suggestions = [ComponentSuggestion(name="raw_response", reason=raw[:500])]

    return ComponentSuggestResponse(
        suggestions=suggestions,
        model_used=AI_COMPONENT_MODEL,
        context_used=project_ctx is not None,
    )


class SchematicReviewRequest(BaseModel):
    project_path: str | None = None
    focus: list[str] | None = None


class ReviewIssue(BaseModel):
    severity: str
    category: str
    component: str = ""
    message: str
    suggestion: str = ""


class SchematicReviewResponse(BaseModel):
    issues: list[ReviewIssue]
    summary: str
    model_used: str
    components_analyzed: int
    nets_analyzed: int


class FreecadExportResponse(BaseModel):
    status: str
    output_path: str | None = None
    returncode: int | None = None
    stdout: str | None = None
    stderr: str | None = None
    version_used: str | None = None
    source: str | None = None


class FreecadStatusResponse(BaseModel):
    status: str
    installed: bool
    version: str | None = None
    compatible: bool
    path: str | None = None
    source: str
    preferred_export_mode: str


@app.post("/ai/schematic-review", response_model=SchematicReviewResponse)
async def schematic_review(raw_request: Request):
    """AI-powered schematic design review."""
    content = None
    review_request: SchematicReviewRequest | None = None

    content_type = raw_request.headers.get("content-type", "")
    if "multipart/form-data" in content_type:
        form = await raw_request.form()
        file = form.get("file")
        if file and hasattr(file, "read"):
            content = (await file.read()).decode("utf-8")
    else:
        body = await raw_request.body()
        if body:
            try:
                review_request = SchematicReviewRequest(**json_module.loads(body))
            except (json_module.JSONDecodeError, TypeError):
                pass
        if review_request and review_request.project_path:
            sch_path = _safe_resolve(review_request.project_path)
            if sch_path is not None:
                content = sch_path.read_text()

    if not content:
        raise HTTPException(status_code=400, detail="Provide either 'file' upload or 'project_path'")

    schematic = parse_schematic(content)
    focus = review_request.focus if review_request else None
    messages = build_review_prompt(schematic, focus=focus)

    model = AI_REVIEW_MODEL
    try:
        raw = await llm_chat(messages=messages, model=model)
    except LLMClientError:
        model = AI_REVIEW_FALLBACK
        try:
            raw = await llm_chat(messages=messages, model=model)
        except LLMClientError as e:
            raise HTTPException(status_code=502, detail=f"LLM service error: {e}")

    try:
        issues_raw = json_module.loads(raw)
        issues = [ReviewIssue(**i) for i in issues_raw]
    except (json_module.JSONDecodeError, TypeError, KeyError):
        issues = [ReviewIssue(severity="info", category="parse_error", message=f"Could not parse LLM response: {raw[:200]}")]

    high = sum(1 for i in issues if i.severity == "high")
    medium = sum(1 for i in issues if i.severity == "medium")
    low = sum(1 for i in issues if i.severity == "low")

    return SchematicReviewResponse(
        issues=issues,
        summary=f"{len(issues)} issues found: {high} high, {medium} medium, {low} low",
        model_used=model,
        components_analyzed=len(schematic.components),
        nets_analyzed=len(schematic.nets),
    )


@app.get("/freecad/status", response_model=FreecadStatusResponse)
async def get_freecad_status():
    """Return FreeCAD runtime compatibility for local desktop clients."""
    return FreecadStatusResponse(**freecad_status())


@app.post("/freecad/export", response_model=FreecadExportResponse)
async def freecad_export(request: FreecadExportRequest):
    """Export a FreeCAD project to STEP or STL via FreeCAD CLI."""
    resolved_input = _safe_resolve(request.input_path)
    if resolved_input is None:
        raise HTTPException(status_code=400, detail="Invalid or out-of-scope input_path")

    resolved_output_dir = None
    if request.output_dir:
        resolved_output_dir = _safe_resolve(request.output_dir)
        if resolved_output_dir is None:
            raise HTTPException(status_code=400, detail="Invalid or out-of-scope output_dir")

    try:
        result = freecad_export_model(
            input_path=resolved_input,
            fmt=request.format,
            output_dir=resolved_output_dir,
        )
    except FileNotFoundError as e:
        raise HTTPException(status_code=400, detail=str(e))
    except FreecadExportError as e:
        raise HTTPException(status_code=409, detail=str(e))
    except Exception as e:
        raise HTTPException(status_code=502, detail=f"FreeCAD export failed: {e}")

    return FreecadExportResponse(**result)


if __name__ == "__main__":
    import uvicorn
    uvicorn.run("gateway.app:app", host="0.0.0.0", port=8001, reload=True)
