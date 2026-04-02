# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

makelife-cad is the CAD/EDA gateway for FineFab — a FastAPI backend (port 8001) with tool integrations (KiCad, FreeCAD, OpenSCAD, YiACAD) and a Next.js 15 web UI for collaborative design.

## Commands

```bash
# Backend (Python)
source .venv/bin/activate
pip install -e ".[dev]"                          # Install with dev deps
PYTHONPATH=$PWD:$PYTHONPATH pytest tests/ -v     # Run tests (10 tests)
uvicorn gateway.app:app --reload --port 8001     # Dev server

# Frontend (Node)
npm install --prefix web
npm run web:dev                                   # Next.js dev server
npm run web:build                                 # Production build
npm run lint                                      # tsc --noEmit

# Docker
docker build -t makelife-cad .
docker run -p 8001:8001 makelife-cad
```

## Architecture

```
gateway/app.py     FastAPI application — tool registry, design endpoints, BOM validation
                   KiCad DRC/SVG export via subprocess (requires kicad-cli)
web/               Next.js 15 / React 19 / App Router — CAD collaboration UI (shell)
tests/             pytest + FastAPI TestClient (10 tests)
```

### Tool Registry

4 CAD tools declared in `TOOLS` dict in `gateway/app.py`:

| Tool | Capabilities |
|------|-------------|
| `kicad` | Schematic, PCB, BOM, Gerber, DRC, ERC |
| `freecad` | 3D modeling, Mesh, STEP/STL export |
| `openscad` | CSG, STL export, parametric |
| `yiacad` | AI-assisted design (planned) |

### Key Endpoints

- `POST /design` — Execute design action (tool + action + params)
- `POST /bom/validate` — Bill of Materials validation
- `POST /kicad/drc` — Design Rule Check (subprocess, 30s timeout)
- `GET /kicad/export/svg` — Schematic SVG export

## Environment Variables

- `OTEL_EXPORTER_OTLP_ENDPOINT` — OpenTelemetry collector (optional)
- `ALLOWED_ORIGINS` — CORS origins (default: `*`)

## Dependencies

Python: fastapi, uvicorn, pydantic, opentelemetry-*. Frontend: next 15, react 19, typescript 5.7.
External: `kicad-cli` required for DRC/export endpoints.
