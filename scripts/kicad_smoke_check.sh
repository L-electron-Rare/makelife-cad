#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCHEMATIC="${ROOT_DIR}/tests/fixtures/simple.kicad_sch"
ARTIFACT_DIR="${ROOT_DIR}/.ci_artifacts/kicad-smoke"

mkdir -p "${ARTIFACT_DIR}"

if ! command -v kicad-cli >/dev/null 2>&1; then
  echo "[kicad-smoke] kicad-cli introuvable"
  exit 1
fi

echo "[kicad-smoke] kicad-cli version:"
kicad-cli --version | tee "${ARTIFACT_DIR}/kicad-version.txt"

if [[ ! -f "${SCHEMATIC}" ]]; then
  echo "[kicad-smoke] fixture introuvable: ${SCHEMATIC}"
  exit 1
fi

echo "[kicad-smoke] export SVG depuis ${SCHEMATIC}"
kicad-cli sch export svg --output "${ARTIFACT_DIR}" "${SCHEMATIC}"

SVG_COUNT=$(find "${ARTIFACT_DIR}" -maxdepth 1 -name '*.svg' | wc -l | tr -d ' ')
if [[ "${SVG_COUNT}" == "0" ]]; then
  echo "[kicad-smoke] aucun SVG généré"
  exit 1
fi

echo "[kicad-smoke] OK - ${SVG_COUNT} fichier(s) SVG généré(s)"
