# makelife-cad

Plateforme CAD/EDA FineFab (gateway + experiences web CAO).

## Role
- Porter les capacites CAD issues de YiACAD.
- Integrer routes FastAPI, viewers et collaboration.
- Connecter les flux CAD avec `life-core`.

## Stack
- Python 3.12+
- TypeScript
- FastAPI gateway
- Next.js 15

## Structure cible
- `gateway/`: backend CAD/API
- `web/`: UI CAD collaborative
- `tools/`: integrations plugin/outillage

## Demarrage rapide
```bash
# backend
python -m venv .venv && source .venv/bin/activate
pip install -e .

# frontend
pnpm install
pnpm dev
```

## Roadmap immediate
- Migrer les routes CAD prioritaires.
- Integrer plugin KiCad et KiCanvas.
- Stabiliser tests E2E collaboration.
