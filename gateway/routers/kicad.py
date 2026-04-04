"""KiCad schematic viewer router — wraps kbs_sch_render_svg from the C bridge."""

from __future__ import annotations

import ctypes
import os
import re
import tempfile
from pathlib import Path

from fastapi import APIRouter, HTTPException, UploadFile, File
from fastapi.responses import Response

router = APIRouter(prefix="/kicad", tags=["kicad"])

_LIB_PATH = os.getenv(
    "KICAD_BRIDGE_LIB",
    str(Path(__file__).parent.parent.parent / "kicad-bridge/build/libkicad_bridge.so"),
)

_lib = None


def _load_lib():
    lib = ctypes.CDLL(_LIB_PATH)
    lib.kbs_sch_render_svg.argtypes = [ctypes.c_char_p]
    lib.kbs_sch_render_svg.restype = ctypes.c_char_p
    lib.kbs_free_string.argtypes = [ctypes.c_char_p]
    lib.kbs_free_string.restype = None
    return lib


def get_lib():
    global _lib
    if _lib is None:
        _lib = _load_lib()
    return _lib


@router.get("/view")
def view_schematic(path: str):
    """Render a .kicad_sch file to SVG using the C bridge."""
    sch_path = Path(path).resolve()
    if not sch_path.exists():
        raise HTTPException(status_code=404, detail="File not found")
    if sch_path.suffix not in (".kicad_sch", ".sch"):
        raise HTTPException(status_code=400, detail="Not a schematic file")

    lib = get_lib()
    svg_bytes = lib.kbs_sch_render_svg(str(sch_path).encode())
    if not svg_bytes:
        raise HTTPException(status_code=500, detail="Render failed")
    svg = svg_bytes.decode("utf-8")
    lib.kbs_free_string(svg_bytes)
    return Response(content=svg, media_type="image/svg+xml")


@router.post("/upload")
async def upload_schematic(file: UploadFile = File(...)):
    """Upload a .kicad_sch, render to SVG, return SVG + component list."""
    if not file.filename or not file.filename.endswith((".kicad_sch", ".sch")):
        raise HTTPException(status_code=400, detail="Only .kicad_sch files accepted")

    with tempfile.NamedTemporaryFile(suffix=".kicad_sch", delete=False) as tmp:
        tmp.write(await file.read())
        tmp_path = tmp.name

    try:
        lib = get_lib()
        svg_bytes = lib.kbs_sch_render_svg(tmp_path.encode())
        if not svg_bytes:
            raise HTTPException(status_code=500, detail="Render failed")
        svg = svg_bytes.decode("utf-8")
        lib.kbs_free_string(svg_bytes)
    finally:
        os.unlink(tmp_path)

    # Extract component references from SVG text nodes (simple heuristic)
    refs = list(dict.fromkeys(re.findall(r'\b([A-Z]{1,3}\d+)\b', svg)))

    return {"svg": svg, "components": refs}
