# Project Guidelines

## Scope
makelife-cad est le gateway CAD/EDA de FineFab.
Le repo combine un backend FastAPI (`gateway/`), une UI web Next.js (`web/`) et des integrations outillage CAD externes (`vendor/`, KiCad/FreeCAD/YiACAD/free-code).

## Code Style
- Langue principale de la documentation: francais.
- Code et noms de symboles: anglais.
- Pour les commandes locales, preferer les cibles `make` deja definies plutot que des commandes ad hoc.

## Architecture
- Backend: `gateway/app.py` expose les endpoints CAD (design, BOM, DRC, export SVG).
- Frontend: `web/` (Next.js 15 / React 19) pour l'interface collaborative.
- Integrations externes: `vendor/` (symlink YiACAD, plugin KiCad, forks KiCad/FreeCAD, `free-code`).
- Tests: `tests/` (pytest + FastAPI TestClient).

## Build and Test
Utiliser en priorite les cibles du `Makefile`:

```bash
make setup        # venv Python + deps web
make dev-gateway  # FastAPI port 8001
make dev-web      # UI web Next.js
make test         # pytest tests/ -v
make build-web    # build frontend
make doctor       # checks environnement local
```

Integrations CAD externes:

```bash
make yiacad-link YIACAD_DIR=../YiACAD
make yiacad-plugin-clone
make free-code-clone
make forks-clone
make forks-pull
```

## Conventions
- Link, don't embed: referencer les docs existantes au lieu de dupliquer leur contenu.
- Garder les frontieres backend/web nettes: `gateway/` pour API/outillage, `web/` pour UI.
- Ne pas supposer la presence de dependances externes (YiACAD, kicad-cli, forks, free-code): verifier explicitement et documenter les fallback.
- Pour les workflows locaux multi-process, utiliser deux terminaux (`make dev-gateway` + `make dev-web`).

## Environment Notes
- Dependance critique: `kicad-cli` requis pour `POST /kicad/drc` et `GET /kicad/export/svg`.
- `YIACAD_DIR` peut etre override pour `make yiacad-link`.
- `FREE_CODE_URL` et `FREE_CODE_BRANCH` peuvent etre overrides pour `make free-code-clone`.
- Tracing optionnel via `OTEL_EXPORTER_OTLP_ENDPOINT`.
- Les chemins workspace contiennent des espaces (`Factory 4 Life`): toujours citer les chemins shell.

## Key References
- Vue d'ensemble: `README.md`
- Commandes et architecture detaillee: `CLAUDE.md`
- Orchestration locale: `Makefile`
- CI actuelle: `.github/workflows/ci.yml`
