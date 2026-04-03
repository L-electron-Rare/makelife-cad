# makelife-cad

Web-based CAD/EDA platform with FastAPI gateway and Next.js 15 frontend for AI-assisted electronic design.

Part of the [FineFab](https://github.com/L-electron-Rare) platform (FineFab).

## What it does

- Provides a collaborative web interface for schematic and PCB design
- Integrates KiCad and FreeCAD through a FastAPI gateway
- Supports AI-assisted design suggestions via LLM integration
- Renders interactive board viewers with KiCanvas
- Connects design workflows to the FineFab runtime pipeline

## Tech stack

Python 3.12+ | FastAPI | TypeScript | Next.js 15 | KiCanvas

## Quick start

```bash
# Backend
python -m venv .venv && source .venv/bin/activate
pip install -e .

# Frontend
pnpm install && pnpm dev
```

## Environment flags (CLI CAD)

- `FREECAD_CMD`: chemin vers `freecadcmd` ou `FreeCADCmd` (défaut: `freecadcmd`, détecte aussi `/Applications/FreeCAD.app/...` sur macOS).
- `FREECAD_TIMEOUT`: délai (s) pour l’export FreeCAD (défaut 120).
- FreeCAD ciblé par YiACAD: `1.1.0` ; les versions `1.1.x` restent supportées mais sont signalées comme non-cibles dans l’app macOS.
- `OTEL_EXPORTER_OTLP_ENDPOINT`, `ALLOWED_ORIGINS`, `AI_*_MODEL`, `YIACAD_*`: voir `gateway/app.py`.

## FreeCAD 1.1.0 workflow

```bash
# miroir source local du fork FreeCAD
make freecad-clone-fork
make freecad-pin-1.1.0

# verification runtime local
make freecad-check

# push de la branche de travail du fork
make freecad-push-branch
```

## Project structure

```
gateway/   FastAPI backend and CAD API routes
web/       Next.js collaborative CAD UI
tools/     Plugin integrations and utilities
```

## Related repos

| Repo | Role |
|------|------|
| [makelife-hard](https://github.com/L-electron-Rare/makelife-hard) | Hardware design files (KiCad) |
| [makelife-firmware](https://github.com/L-electron-Rare/makelife-firmware) | Embedded firmware |
| [KIKI-models-tuning](https://github.com/L-electron-Rare/KIKI-models-tuning) | Model fine-tuning pipeline |
| [finefab-life](https://github.com/L-electron-Rare/finefab-life) | Integration runtime and ops |

## License

MIT
