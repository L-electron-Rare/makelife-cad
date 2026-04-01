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
