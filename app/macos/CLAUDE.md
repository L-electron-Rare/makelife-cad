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

### Xcode build (preferred)

The Xcode project is generated from `project.yml` via xcodegen:
```bash
xcodegen generate   # regenerate MakelifeCAD.xcodeproj from project.yml
```

**Known `project.yml` bug:** `OTHER_LINKER_FLAGS` is not a valid Xcode build setting (correct key: `OTHER_LDFLAGS`). Until fixed in `project.yml`, build via command line with the override:
```bash
cd app/macos
xcodebuild -project MakelifeCAD.xcodeproj -scheme MakelifeCAD \
  -configuration Debug OTHER_LDFLAGS="-lkicad_bridge" build
```

Or in Xcode Build Settings: **Target → Build Settings → Other Linker Flags** → add `-lkicad_bridge`.

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

The bridging header (`Bridge/MakelifeCAD-Bridging-Header.h`) imports both `kicad_bridge.h` and `kicad_bridge_swift.h`. **`KiCadBridge.swift` uses `kbs_` prefixed aliases** for all schematic operations.

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
| `CommandRunner`              | Shell command execution for the Terminal window                            |
| `GitDiffViewModel`           | Schematic diff vs HEAD                                                     |
| `PCBEditorViewModel`         | Interactive PCB canvas — 5 tools: select/track/via/footprint/zone          |

`KiCadProject` and `KiCadProjectManager` are typealiases for `YiacadProject` / `YiacadProjectManager` (transitional names kept for older views).

### SwiftUI tab structure

`App.swift` → `ContentView` → `NavigationSplitView`:

- **Sidebar** varies per `AppTab`: `ComponentList` (schematic), `LayerPanel` (PCB), `FreeCADSidebarView`, `AISidebarView`, `GitHubSidebarView`
- **Detail** via `AppTab` enum: `SchematicView` / `PCBView` / `PCB3DView` / `FreeCADDetailView` / `AIDetailView` / `GitHubDetailView`
- **Violations panel** (collapsible bottom strip): `ViolationsView` with ERC (schematic) or DRC (PCB) results

### Window model

Three patterns used in `App.swift`:

- **Model 1 — Utility windows** (`Window`): BOM, Terminal, AI Chat, Fab Preview, Git Diff, Sch↔PCB Cross-Ref, Design Notes — opened via toolbar buttons
- **Model 2 — DocumentGroup** scaffold: commented out, not yet active
- **Model 3 — Document windows** (`WindowGroup` with `URL` value): `sch-doc` / `pcb-doc` — detach schematic or PCB into its own window via `openWindow(id:value:)`

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

## Key constraints

- All bridge calls must be on `@MainActor` — no background threads for C API calls
- C-owned string pointers must not be used after the next mutating bridge call
- `kicad-bridge/build/libkicad_bridge.a` must exist **before** the Xcode build links
- The app targets macOS 14+ (`NavigationSplitView`, structured concurrency); Apple Intelligence features gated on macOS 26
- FreeCAD integration requires FreeCAD 1.1.x; version check uses `FreeCADRuntimeResolver.supportedPrefix = "1.1."`
