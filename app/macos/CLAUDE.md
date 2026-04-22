# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

Native macOS SwiftUI app (macOS 14+) for viewing and editing KiCad schematics and PCB layouts, with FreeCAD 3D model management and AI-assisted design. Wraps a custom C library (`libkicad_bridge.a`) compiled from `../../kicad-bridge/` via CMake.

## Build commands

### C bridge (prerequisite — must build before Xcode)
```bash
cmake -B ../../kicad-bridge/build -S ../../kicad-bridge -DCMAKE_OSX_DEPLOYMENT_TARGET=14.0
cmake --build ../../kicad-bridge/build
# Produces: ../../kicad-bridge/build/libkicad_bridge.a (arm64)
```

### Xcode build

The Xcode project is generated from `project.yml` via xcodegen:
```bash
xcodegen generate   # regenerate MakelifeCAD.xcodeproj from project.yml
```

Build via Xcode IDE (MakelifeCAD scheme) or command line:
```bash
xcodebuild -project MakelifeCAD.xcodeproj -scheme MakelifeCAD -configuration Debug build
```

### Run tests
```bash
# All tests (XCTest)
xcodebuild test -scheme MakelifeCAD -destination 'platform=macOS'

# Single test class
xcodebuild test -scheme MakelifeCAD -destination 'platform=macOS' \
  -only-testing:MakelifeCADTests/FreeCADSupportTests

# Single test method
xcodebuild test -scheme MakelifeCAD -destination 'platform=macOS' \
  -only-testing:MakelifeCADTests/FreeCADSupportTests/testParseVersionAndCompatibility
```

Tests live in `MakelifeCADTests/FreeCADSupportTests.swift` — covers `YiacadProject`, `FreeCADRuntimeResolver`, and `FreeCADExportPlanner`.

### Run the app (after build)
```bash
open /Users/electron/Library/Developer/Xcode/DerivedData/MakelifeCAD-*/Build/Products/Debug/MakelifeCAD.app
```

## Project configuration (`project.yml`)

- **Bundle ID:** `cc.saillant.makelife-cad`
- **Deployment target:** macOS 14.0
- **Swift version:** 5.10
- **Bridging header:** `MakelifeCAD/Bridge/MakelifeCAD-Bridging-Header.h`
- **C library:** links `-lkicad_bridge` from `../../kicad-bridge/build`
- **Header search:** `../../kicad-bridge/include`

## Architecture

### Three-layer stack

```
SwiftUI Views  (Views/*.swift)
      │  ObservableObject bindings
ViewModels     (Models/*.swift) + Swift Bridges (Bridge/KiCadBridge.swift)
      │  C function calls via bridging header
C Library      (../../kicad-bridge/ → libkicad_bridge.a)
```

### C bridge modules (`../../kicad-bridge/src/`)

| Source file         | API prefix                  | Responsibility                                          |
|--------------------|-----------------------------|----------------------------------------------------------|
| `bridge_sch.c`     | `kicad_sch_`                | Open/parse/render `.kicad_sch`                           |
| `bridge_sch_edit.c`| `kicad_sch_`                | Add/move/delete symbols, wires, labels; undo/redo/save   |
| `bridge_pcb.c`     | `kicad_pcb_`                | Open/parse `.kicad_pcb`, layer/footprint JSON, SVG render|
| `bridge_pcb_edit.c`| `kicad_pcb_`                | Add footprint/track/via/zone; undo/redo/save/netlist     |
| `bridge_drc.c`     | `kicad_run_`                | DRC (PCB) and ERC (schematic) → JSON violations          |
| `bridge_3d.c`      | `kicad_pcb_export_3d_json`  | Export PCB as 3D-ready JSON                              |
| `bridge_swift.c`   | `kbs_`                      | Swift-friendly aliases (`kbs_sch_*`)                     |

The bridging header imports both `kicad_bridge.h` and `kicad_bridge_swift.h`. **`KiCadBridge.swift` uses `kbs_` prefixed aliases** for all schematic operations.

All C strings returned by the bridge are owned by the handle (do not free); valid until the next mutating call or `close()`.

### Swift bridge classes (`Bridge/KiCadBridge.swift`)

| Class               | Handle type                  | Covers                                      |
|--------------------|------------------------------|---------------------------------------------|
| `KiCadBridge`       | `UnsafeMutableRawPointer?`   | Read-only schematic (components JSON + SVG) |
| `KiCadSchEditBridge`| `UnsafeMutableRawPointer?`   | Full schematic edit, undo/redo, save        |
| `KiCadPCBBridge`    | `kicad_pcb_handle?`          | PCB read + edit, layers, footprints, DRC    |

All bridge classes are `@MainActor final class` with `@Published` state. Undo/redo depth is tracked in Swift (the C layer owns the truth).

### ViewModels (`Models/`)

| Class                        | Role                                                                       |
|-----------------------------|----------------------------------------------------------------------------|
| `YiacadProjectManager`       | Opens `.kicad_pro` files; manages recent projects list (UserDefaults)      |
| `FreeCADViewModel`           | FreeCAD runtime detection + STEP/STL export (local or gateway mode)        |
| `AppleIntelligenceViewModel` | On-device AI via `FoundationModels` (macOS 26+)                            |
| `FineFabViewModel`           | Factory AI gateway at `http://localhost:8001` — suggest/review/status      |
| `GitHubLibraryViewModel`     | GitHub component library browser                                           |
| `GitHubRepoViewModel`        | Git status, staging, commits, push/pull, PR list via `gh` CLI              |
| `CommandRunner`              | Shell command execution for the Terminal window                            |
| `GitDiffViewModel`           | Schematic diff vs HEAD                                                     |
| `PCBEditorViewModel`         | Interactive PCB canvas — 5 tools: select/track/via/footprint/zone          |
| `NewProjectScaffolder`       | Creates FineFab directory structure with KiCad templates + optional GitHub repo |

`KiCadProject` and `KiCadProjectManager` are typealiases for `YiacadProject` / `YiacadProjectManager` (transitional names kept for older views).

### SwiftUI tab structure

`App.swift` → `ContentView` → `NavigationSplitView` with 7 tabs via `AppTab` enum:

| Tab | Sidebar | Detail |
|-----|---------|--------|
| `schematic` | `ComponentList` | `SchematicView` |
| `pcb` | `LayerPanel` | `PCBView` |
| `viewer3d` | — | `PCB3DView` |
| `freecad` | `FreeCADSidebarView` | `FreeCADDetailView` |
| `ai` | `AISidebarView` | `AIDetailView` |
| `github` | `GitHubSidebarView` | `GitHubDetailView` |
| `git` | `GitRepoSidebarView` | (git panel) |

**Violations panel** (collapsible bottom strip): `ViolationsView` with ERC (schematic) or DRC (PCB) results.

### Window model

Three patterns used in `App.swift`:

- **Utility windows** (`Window`): BOM, Terminal, AI Chat, Fab Preview, Git Diff, Sch↔PCB Cross-Ref, Design Notes — opened via toolbar buttons
- **Document windows** (`WindowGroup` with `URL` value): `sch-doc` / `pcb-doc` — detach schematic or PCB into its own window via `openWindow(id:value:)`
- **DocumentGroup** scaffold: commented out, not yet active

### Inter-view notifications

Views communicate via `Notification.Name` extensions:
- `.makelifeGoToGitTab` — switches active tab to git
- `.makelifeShowCloneSheet` — opens clone repo dialog
- `.makelifeShowNewProjectSheet` — opens new project dialog

### File open flow

Two entry points:
1. **Single file**: `fileImporter` (`.kicad_sch` / `.kicad_pcb`) → `handleFileImport` in `ContentView` → `KiCadBridge.openSchematic()` or `KiCadPCBBridge.openPCB()`
2. **Project**: `openProjectPanel()` (⇧⌘O) → NSOpenPanel (`.kicad_pro`) → `YiacadProjectManager.open()` → auto-opens schematic + PCB + scans `mechanical/` for `.FCStd` files

### FreeCAD integration

`FreeCADViewModel` supports two execution modes:
- **local** — uses `FreeCADCmd` binary (searches `FREECAD_CMD` env var, then `/Applications/FreeCAD.app`, then PATH); requires FreeCAD 1.1.x
- **gateway** — delegates export to the FastAPI gateway at `http://localhost:8001`; preferred when gateway is reachable locally

`FreeCADExportPlanner.chooseMode()` picks the mode: gateway is preferred when both local FreeCAD is compatible AND gateway URL is localhost. Only probes the gateway when a project is open (or `force: true`).

FreeCAD documents are discovered recursively under `<project_root>/mechanical/` (any `*.FCStd` file).

### AI stack

Two providers selectable in the AI tab:
- **On-device** (`AppleIntelligenceViewModel`): uses `FoundationModels.SystemLanguageModel.default`; requires macOS 26 (Tahoe) with Apple Intelligence enabled
- **Factory AI** (`FineFabViewModel`): calls `FineFabClient` at the configured gateway URL (`finefab.gateway.url` in UserDefaults, default `http://localhost:8001`)

The active schematic is automatically injected as context into AI prompts when a schematic is loaded (`schematicSummary` / `schematicContext`).

## UserDefaults keys

| Key | Default | Purpose |
|-----|---------|---------|
| `finefab.gateway.url` | `http://localhost:8001` | AI gateway URL |
| `tools.gh.path` | auto-detect | Override `gh` binary path |
| `tools.kicad.cli.path` | auto-detect | Override `kicad-cli` path |
| `tools.freecad.path` | auto-detect | Override FreeCAD app path |
| `git.default.branch` | — | Default branch for new projects |
| `git.auto.stage` | — | Auto-stage KiCad files on save |
| `github.pat` | — | GitHub PAT fallback (when `gh auth` unavailable) |

Settings UI: `SettingsView` with 4 tabs — General (gateway URL), GitHub (auth + PAT), Tools (KiCad/FreeCAD/gh paths), Setup (dependency status checks).

## Key constraints

- All bridge calls must be on `@MainActor` — no background threads for C API calls
- C-owned string pointers must not be used after the next mutating bridge call
- `kicad-bridge/build/libkicad_bridge.a` must exist **before** the Xcode build links
- The app targets macOS 14+ (`NavigationSplitView`, structured concurrency); Apple Intelligence features gated on macOS 26
- FreeCAD integration requires FreeCAD 1.1.x; version check uses `FreeCADRuntimeResolver.supportedPrefix = "1.1."`
- Isolate external tool access in model/bridge layers — views must remain presentation-only

## Conventions

- Commit prefixes: `feat:`, `fix:`, `chore:`, `docs:` (scoped forms ok: `fix(gateway):`)
- PascalCase for types/files, camelCase for properties/methods
- One primary type per file; group by responsibility (Views/, Models/, Bridge/)
- Add new tests under `MakelifeCADTests/`, name after feature (e.g. `KiCadProjectTests.swift`)
- PRs: short summary, impacted areas, validation steps, screenshots for UI changes
