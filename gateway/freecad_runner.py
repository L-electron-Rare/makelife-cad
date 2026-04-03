"""FreeCAD runtime detection and export helpers."""
from __future__ import annotations

import os
import re
import shutil
import subprocess
import tempfile
from pathlib import Path
from typing import Literal

DEFAULT_TIMEOUT = int(os.getenv("FREECAD_TIMEOUT", "120"))
TARGET_VERSION = "1.1.0"
SUPPORTED_VERSION_PREFIX = "1.1."
APP_BUNDLE_CANDIDATES = (
    "/Applications/FreeCAD.app/Contents/MacOS/FreeCADCmd",
    "/Applications/FreeCAD 1.1.app/Contents/MacOS/FreeCADCmd",
)


class FreecadExportError(Exception):
    """Raised when FreeCAD export fails."""


def _candidate_commands() -> list[tuple[str, str]]:
    candidates: list[tuple[str, str]] = []
    env_command = os.getenv("FREECAD_CMD")
    if env_command:
        candidates.append((env_command, "env"))
    for bundle_path in APP_BUNDLE_CANDIDATES:
        candidates.append((bundle_path, "app_bundle"))
    candidates.extend(
        [
            ("FreeCADCmd", "path"),
            ("freecadcmd", "path"),
        ]
    )
    return candidates


def _resolve_command_path(command: str) -> str | None:
    if os.path.isabs(command) or "/" in command:
        return command if Path(command).exists() else None
    return shutil.which(command)


def resolve_freecad_command() -> tuple[str | None, str]:
    """Resolve the best FreeCAD command path and its source."""
    for command, source in _candidate_commands():
        resolved = _resolve_command_path(command)
        if resolved:
            return resolved, source
    return None, "unavailable"


def parse_version(raw: str) -> str | None:
    """Extract a semantic version from FreeCAD output."""
    match = re.search(r"(\d+\.\d+\.\d+)", raw)
    return match.group(1) if match else None


def is_compatible_version(version: str | None) -> bool:
    """Accept FreeCAD 1.1.x only."""
    return bool(version and version.startswith(SUPPORTED_VERSION_PREFIX))


def _version_script() -> str:
    return (
        "import FreeCAD\n"
        "version = FreeCAD.Version()\n"
        'print(".".join(str(part) for part in version[:3]))\n'
    )


def _export_script() -> str:
    return (
        "import FreeCAD, Part, Mesh, sys\n"
        "input_path, output_path, fmt = sys.argv[1], sys.argv[2], sys.argv[3]\n"
        "doc = FreeCAD.openDocument(input_path)\n"
        "objs = [obj for obj in doc.Objects if hasattr(obj, 'Shape') or hasattr(obj, 'Mesh')]\n"
        "if not objs:\n"
        "    raise RuntimeError('No exportable objects found in document')\n"
        "if fmt.lower() == 'stl':\n"
        "    Mesh.export(objs, output_path)\n"
        "else:\n"
        "    Part.export(objs, output_path)\n"
        "doc.close()\n"
        "print(output_path)\n"
    )


def _run_script(
    executable: str,
    script_content: str,
    args: list[str],
    timeout: int,
) -> subprocess.CompletedProcess[str]:
    with tempfile.NamedTemporaryFile("w", suffix=".py", delete=False) as script_file:
        script_file.write(script_content)
        script_path = Path(script_file.name)

    try:
        return subprocess.run(
            [executable, "-c", str(script_path), *args],
            capture_output=True,
            text=True,
            timeout=timeout,
            check=False,
        )
    finally:
        try:
            script_path.unlink(missing_ok=True)
        except OSError:
            pass


def detect_runtime_status(timeout: int = 15) -> dict[str, object]:
    """Return FreeCAD runtime status for the gateway and UI."""
    executable, source = resolve_freecad_command()
    if executable is None:
        return {
            "status": "unavailable",
            "installed": False,
            "version": None,
            "compatible": False,
            "path": None,
            "source": source,
            "preferred_export_mode": "unavailable",
        }

    try:
        result = _run_script(executable, _version_script(), [], timeout)
    except subprocess.TimeoutExpired:
        return {
            "status": "unavailable",
            "installed": True,
            "version": None,
            "compatible": False,
            "path": executable,
            "source": source,
            "preferred_export_mode": "unavailable",
        }

    version = parse_version("\n".join([result.stdout or "", result.stderr or ""]))
    compatible = is_compatible_version(version)
    status = "available" if compatible else "incompatible"
    return {
        "status": status,
        "installed": True,
        "version": version,
        "compatible": compatible,
        "path": executable,
        "source": source,
        "preferred_export_mode": "gateway" if compatible else "unavailable",
    }


def export_model(
    input_path: Path,
    fmt: Literal["step", "stl"] = "step",
    output_dir: Path | None = None,
    timeout: int = DEFAULT_TIMEOUT,
) -> dict[str, object]:
    """Run FreeCAD CLI to export a model to STEP or STL."""
    if not input_path.exists():
        raise FileNotFoundError(f"Input file not found: {input_path}")

    fmt_norm = fmt.lower()
    if fmt_norm not in ("step", "stl"):
        raise ValueError("format must be 'step' or 'stl'")

    runtime_status = detect_runtime_status()
    if not runtime_status["installed"]:
        raise FileNotFoundError("FreeCAD CLI not found")
    if not runtime_status["compatible"]:
        version = runtime_status.get("version") or "unknown"
        raise FreecadExportError(
            f"Incompatible FreeCAD version '{version}'. Expected {SUPPORTED_VERSION_PREFIX}x."
        )

    executable = str(runtime_status["path"])

    if output_dir is None:
        target_dir = Path(tempfile.mkdtemp(prefix="freecad-export-"))
    else:
        output_dir.mkdir(parents=True, exist_ok=True)
        target_dir = output_dir

    output_ext = ".step" if fmt_norm == "step" else ".stl"
    output_path = target_dir / f"{input_path.stem}{output_ext}"

    try:
        result = _run_script(
            executable,
            _export_script(),
            [str(input_path), str(output_path), fmt_norm],
            timeout,
        )
    except subprocess.TimeoutExpired as exc:
        raise FreecadExportError(f"FreeCAD export timed out after {timeout}s") from exc

    status = "ok" if result.returncode == 0 else "error"
    return {
        "status": status,
        "output_path": str(output_path) if status == "ok" else None,
        "returncode": result.returncode,
        "stdout": (result.stdout or "")[:800],
        "stderr": (result.stderr or "")[:800],
        "version_used": runtime_status["version"],
        "source": runtime_status["source"],
    }
