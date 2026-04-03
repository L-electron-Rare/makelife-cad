#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PCB_FILE="${ROOT_DIR}/tests/fixtures/simple.kicad_pcb"
ARTIFACT_DIR="${ROOT_DIR}/.ci_artifacts/kicad-drc"
REPORT_FILE="${ARTIFACT_DIR}/drc-report.json"
STATUS_FILE="${ARTIFACT_DIR}/status.txt"

mkdir -p "${ARTIFACT_DIR}"

if ! command -v kicad-cli >/dev/null 2>&1; then
  echo "[kicad-drc] kicad-cli introuvable"
  exit 1
fi

if [[ ! -f "${PCB_FILE}" ]]; then
  echo "[kicad-drc] fixture PCB introuvable: ${PCB_FILE}"
  exit 1
fi

PCB_HELP="$(kicad-cli pcb -h 2>&1 || true)"
printf '%s\n' "${PCB_HELP}" > "${ARTIFACT_DIR}/kicad-pcb-help.txt"
if ! printf '%s\n' "${PCB_HELP}" | grep -Eq '(^|[[:space:],{}])drc([[:space:],}]|$)'; then
  echo "[kicad-drc] la commande 'kicad-cli pcb drc' n'est pas disponible sur ce runtime, verification sautee" | tee "${STATUS_FILE}"
  exit 0
fi

echo "[kicad-drc] lancement DRC sur ${PCB_FILE}"
kicad-cli pcb drc --output "${REPORT_FILE}" "${PCB_FILE}"

if [[ ! -f "${REPORT_FILE}" ]]; then
  echo "[kicad-drc] rapport DRC absent: ${REPORT_FILE}"
  exit 1
fi

echo "ok" > "${STATUS_FILE}"
echo "[kicad-drc] OK - rapport genere: ${REPORT_FILE}"
