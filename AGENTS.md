# AGENTS.md

This file provides guidance to Codex (Codex.ai/code) when working with code in this repository.

## Overview

makelife-cad is the CAD/EDA platform for FineFab. It has four components:

1. **Gateway** — FastAPI backend (port 8001) with CAD tool integrations and AI endpoints
2. **Electron app** — Desktop app (terminal, AI sidebar, inline triggers)
3. **YiACAD native macOS** — Native macOS app built with kicad-bridge C engine (xcodegen + CMake)
4. **Web UI** — Next.js 15 governance dashboard

## Commands

```bash
# Backend (Python)
source .venv/bin/activate
pip install -e ".[dev]"                          # Install with dev deps
PYTHONPATH=$PWD:$PYTHONPATH pytest tests/ -v     # Run tests (10 tests)
uvicorn gateway.app:app --reload --port 8001     # Dev server

# Frontend Next.js (Node)
npm install --prefix web
npm run web:dev                                   # Next.js dev server
npm run web:build                                 # Production build
npm run lint                                      # tsc --noEmit

# Electron app
npm install
npm run electron:dev                              # Electron dev mode
npm run electron:build                            # Package Electron app

# YiACAD native macOS (kicad-bridge)
xcodegen generate                                 # Generate Xcode project
cmake -B kicad-bridge/build -S kicad-bridge -DCMAKE_OSX_DEPLOYMENT_TARGET=14.0
cmake --build kicad-bridge/build

# Docker
docker build -t makelife-cad .
docker run -p 8001:8001 makelife-cad
```

## Architecture

```
gateway/app.py         FastAPI app — tool registry, design endpoints, BOM validation,
                       AI endpoints, KiCad DRC/SVG via subprocess (requires kicad-cli)
gateway/ai_routes.py   AI endpoints: /ai/component-suggest, /ai/schematic-review
web/                   Next.js 15 / React 19 / App Router — governance dashboard
electron/              Electron desktop app — terminal, AI sidebar, inline triggers
kicad-bridge/          C engine bridging YiACAD to KiCad (6 integration phases)
tests/                 pytest + FastAPI TestClient (10 tests)
```

### Tool Registry

4 CAD tools declared in `TOOLS` dict in `gateway/app.py`:

| Tool | Capabilities |
|------|-------------|
| `kicad` | Schematic, PCB, BOM, Gerber, DRC, ERC |
| `freecad` | 3D modeling, Mesh, STEP/STL export |
| `openscad` | CSG, STL export, parametric |
| `yiacad` | AI-assisted design (native macOS, kicad-bridge C engine) |

### Key Endpoints

- `POST /design` — Execute design action (tool + action + params)
- `POST /bom/validate` — Bill of Materials validation
- `POST /kicad/drc` — Design Rule Check (subprocess, 30s timeout)
- `GET /kicad/export/svg` — Schematic SVG export
- `POST /ai/component-suggest` — AI component suggestion
- `POST /ai/schematic-review` — AI schematic review

## Environment Variables

- `OTEL_EXPORTER_OTLP_ENDPOINT` — OpenTelemetry collector (optional)
- `ALLOWED_ORIGINS` — CORS origins (default: `*`)

## Dependencies

Python: fastapi, uvicorn, pydantic, opentelemetry-*. Frontend: next 15, react 19, typescript 5.7.
Electron: electron, vite. Native: xcodegen, cmake (kicad-bridge C engine).
External: `kicad-cli` required for DRC/export endpoints.
