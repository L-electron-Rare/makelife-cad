#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCHEMATIC="${ROOT_DIR}/tests/fixtures/simple.kicad_sch"
ARTIFACT_DIR="${ROOT_DIR}/.ci_artifacts/kicad-smoke"
STATUS_FILE="${ARTIFACT_DIR}/status.txt"

mkdir -p "${ARTIFACT_DIR}"

if ! command -v kicad-cli >/dev/null 2>&1; then
  echo "[kicad-smoke] kicad-cli introuvable"
  exit 1
fi

echo "[kicad-smoke] kicad-cli version:"
KICAD_VERSION="$(kicad-cli version 2>/dev/null || kicad-cli --version)"
printf '%s\n' "${KICAD_VERSION}" | tee "${ARTIFACT_DIR}/kicad-version.txt"
KICAD_SEMVER="$(printf '%s\n' "${KICAD_VERSION}" | grep -Eo '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -n1 || true)"
KICAD_MAJOR="${KICAD_SEMVER%%.*}"

if [[ ! -f "${SCHEMATIC}" ]]; then
  echo "[kicad-smoke] fixture introuvable: ${SCHEMATIC}"
  exit 1
fi

if [[ -n "${KICAD_MAJOR}" && "${KICAD_MAJOR}" -lt 8 ]]; then
  echo "[kicad-smoke] KiCad ${KICAD_SEMVER} detecte: export SVG du fixture 20231120 saute sur KiCad < 8" | tee "${STATUS_FILE}"
  exit 0
fi

echo "[kicad-smoke] export SVG depuis ${SCHEMATIC}"
kicad-cli sch export svg --output "${ARTIFACT_DIR}" "${SCHEMATIC}"

SVG_COUNT=$(find "${ARTIFACT_DIR}" -maxdepth 1 -name '*.svg' | wc -l | tr -d ' ')
if [[ "${SVG_COUNT}" == "0" ]]; then
  echo "[kicad-smoke] aucun SVG généré"
  exit 1
fi

echo "ok" > "${STATUS_FILE}"
echo "[kicad-smoke] OK - ${SVG_COUNT} fichier(s) SVG généré(s)"
