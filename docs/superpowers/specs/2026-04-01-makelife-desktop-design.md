# MakeLife Desktop — Design Spec

**Date**: 2026-04-01
**Repo**: L-electron-Rare/makelife-cad
**Author**: Clement Saillant / Claude Opus 4.6

## Goal

Open-source Electron desktop app that unifies KiCad (EDA), FreeCAD (MCAD), firmware development, AI-assisted design (mascarade), GitHub project management, and cloud collaboration into a single hardware engineering platform. Core open-source (MIT), cloud collaboration premium (freemium).

## Target

- Open-source public distribution (competitor to Altium/Fusion360)
- Freemium: core free, cloud sync/collaboration/managed CI paid
- Platforms: macOS (ARM+x64), Linux (AppImage), Windows (NSIS)

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│ MakeLife Desktop (Electron 33+)                                  │
│                                                                   │
│  ┌────────────────────────────────────────────────────────┐      │
│  │ React 19 UI (Chromium)                                  │      │
│  │  ├── Project Dashboard (kanban, issues, milestones)     │      │
│  │  ├── File Explorer (KiCad/FreeCAD/firmware aware)       │      │
│  │  ├── Git Panel (branches, visual diff, PR, review)      │      │
│  │  ├── CI Status (DRC/ERC, Gerber, BOM, 3D renders)      │      │
│  │  ├── AI Panel (mascarade chat, RAG, design review)      │      │
│  │  ├── Firmware IDE (Monaco editor + PlatformIO)          │      │
│  │  └── Terminal / Build logs                              │      │
│  └────────────────────────────────────────────────────────┘      │
│                                                                   │
│  ┌────────────────────────────────────────────────────────┐      │
│  │ Node.js Backend (main process)                          │      │
│  │  ├── Process Manager (KiCad, FreeCAD, PlatformIO)       │      │
│  │  ├── File Watcher (chokidar: .kicad_sch, .FCStd, .cpp) │      │
│  │  ├── Git Engine (isomorphic-git + CLI fallback)         │      │
│  │  ├── GitHub API (Octokit: issues, PR, Actions, Releases)│      │
│  │  ├── KiCad CLI bridge (erc, drc, export, thumbnail)     │      │
│  │  ├── FreeCAD CLI bridge (freecadcmd, export STEP/STL)   │      │
│  │  ├── Mascarade Client (HTTP → mascarade-core:8100)      │      │
│  │  ├── PlatformIO bridge (pio run, pio test, pio upload)  │      │
│  │  └── Cloud Sync (WebSocket, premium)                    │      │
│  └────────────────────────────────────────────────────────┘      │
│                                                                   │
│  Side-by-side native processes:                                   │
│  ┌────────────┐  ┌────────────┐  ┌────────────┐                │
│  │ KiCad GUI  │  │ FreeCAD GUI│  │ PlatformIO │                │
│  │ (fork)     │  │ (fork)     │  │ (CLI)      │                │
│  └────────────┘  └────────────┘  └────────────┘                │
└─────────────────────────────────────────────────────────────────┘
         │                                    │
         ▼                                    ▼
┌─────────────────┐              ┌─────────────────────┐
│ mascarade-core   │              │ MakeLife Cloud       │
│ (local or remote)│              │ (premium, future)    │
│ LLM routing, RAG │              │ sync, collab, CI     │
│ MCP tools        │              │ managed runners      │
└─────────────────┘              └─────────────────────┘
```

## Features — All v1

### 1. Project Manager
- `.makelife` project config (JSON): paths, tools, remotes, team
- Project template: `hardware/` (KiCad), `mechanical/` (FreeCAD), `firmware/` (PlatformIO), `docs/`
- Auto-detect existing KiCad/FreeCAD/PlatformIO projects on open
- Recent projects, favorites, quick open

### 2. KiCad + FreeCAD Integration
- Auto-detect installed KiCad and FreeCAD (macOS, Linux, Windows paths)
- Launch GUI with correct file on double-click from file explorer
- File watching: detect saves, trigger thumbnail regeneration, auto-stage
- KiCad CLI bridge:
  - `kicad-cli sch erc` — ERC check
  - `kicad-cli pcb drc` — DRC check
  - `kicad-cli sch export pdf/svg` — schematic export
  - `kicad-cli pcb export gerbers` — Gerber generation
  - `kicad-cli pcb export svg` — PCB thumbnail
- FreeCAD CLI bridge:
  - `freecadcmd` — STEP/STL/OBJ export
  - Screenshot/render generation
- BOM viewer: parse KiCad BOM XML, display in React table, export CSV

### 3. Git + GitHub Integration (Full DevOps)
- **Git operations**: clone, branch, commit, push, pull, merge, rebase, stash
- **Visual diff for hardware**: generate PNG of schematics/PCB before+after via kicad-cli, show side-by-side
- **GitHub Issues**: create, edit, close, label, assign — kanban board view
- **GitHub Milestones**: progress tracking, burndown
- **GitHub PR**: create from branch, request review, merge — with DRC/ERC status checks
- **GitHub Actions**:
  - Ship workflow templates with the app (`.github/workflows/`)
  - `makelife-drc.yml` — ERC + DRC on every PR
  - `makelife-gerber.yml` — Gerber + drill + BOM + pick-and-place artifact
  - `makelife-3d.yml` — 3D render via FreeCAD headless
  - `makelife-firmware.yml` — PlatformIO build + test
  - Display CI status inline (green/red badges per PR)
- **GitHub Releases**: package Gerber + BOM + 3D + firmware binary, publish release from app

### 4. AI Panel (mascarade)
- Chat interface connected to mascarade-core (local or remote)
- Context-aware: knows which project/file is open, can read schematics
- MCP tools integration:
  - KiCad MCP (5 tools): component search, schematic analysis, DRC interpretation
  - SPICE MCP (28 tools): simulation assistance
  - FreeCAD MCP: 3D model assistance
- RAG over project documentation (design rules, datasheets, specs)
- Design review: "review this schematic for issues" → mascarade analyzes via fine-tuned EE models
- Mascarade connection config: local (localhost:8100) or remote (cloud, premium)

### 5. Firmware IDE
- Monaco editor (same engine as VS Code) embedded in Electron
- File tree for `firmware/` directory
- Syntax highlighting for C/C++, Python, Arduino
- PlatformIO integration:
  - `pio run` — build
  - `pio test` — unit tests
  - `pio run -t upload` — flash to device
  - `pio device monitor` — serial monitor
- Build output / serial monitor in integrated terminal
- Detects `platformio.ini` automatically

### 6. Cloud Collaboration (Freemium boundary)

| Feature | Free | Premium |
|---------|------|---------|
| Local project management | Yes | Yes |
| Git + GitHub (full) | Yes | Yes |
| KiCad/FreeCAD launch + CLI | Yes | Yes |
| AI panel (local mascarade) | Yes | Yes |
| Firmware IDE | Yes | Yes |
| CI workflow templates | Yes | Yes |
| **Cloud project sync** | No | Yes |
| **Real-time collaboration** | No | Yes |
| **Managed CI runners** | No | Yes |
| **Cloud visual diff history** | No | Yes |
| **Team management** | No | Yes |
| **AI panel (cloud mascarade)** | No | Yes |

### 7. Design Blocks Library
- Ships with makelife-hard blocks (22 blocks, 8 categories)
- Browse blocks from within the app
- Insert block into current KiCad project (copy hierarchical sheet)
- Community blocks: discover + install from GitHub repos (future)

## Tech Stack

| Layer | Technology |
|-------|-----------|
| Shell | Electron 33+ |
| UI framework | React 19 + TypeScript |
| Styling | Tailwind CSS + shadcn/ui |
| State management | Zustand |
| Code editor | Monaco Editor (@monaco-editor/react) |
| Git | isomorphic-git + git CLI fallback |
| GitHub API | Octokit |
| File watching | chokidar |
| KiCad bridge | kicad-cli subprocess |
| FreeCAD bridge | freecadcmd subprocess |
| PlatformIO | pio CLI subprocess |
| Mascarade client | HTTP fetch → mascarade-core API |
| Terminal | xterm.js |
| Build/package | electron-builder |
| Auto-update | electron-updater + GitHub Releases |
| Testing | Vitest + Playwright (E2E) |

## Packaging

- KiCad and FreeCAD are NOT bundled — app detects system installation or prompts download
- PlatformIO CLI detected or prompted (`pip install platformio`)
- App size target: ~150 MB (Electron + React + Monaco)
- Auto-update via GitHub Releases

## Repo Structure

```
makelife-cad/
├── electron/
│   ├── main.ts              ← Electron main process
│   ├── preload.ts            ← Preload script (IPC bridge)
│   ├── bridges/
│   │   ├── kicad.ts          ← KiCad CLI wrapper
│   │   ├── freecad.ts        ← FreeCAD CLI wrapper
│   │   ├── platformio.ts     ← PlatformIO CLI wrapper
│   │   ├── git.ts            ← Git operations
│   │   ├── github.ts         ← GitHub API (Octokit)
│   │   ├── mascarade.ts      ← Mascarade HTTP client
│   │   └── file-watcher.ts   ← Chokidar file watching
│   └── utils/
│       ├── process-manager.ts
│       └── detect-tools.ts   ← Find KiCad/FreeCAD/PIO paths
├── src/
│   ├── App.tsx
│   ├── pages/
│   │   ├── Dashboard.tsx     ← Project overview + kanban
│   │   ├── Explorer.tsx      ← File tree + preview
│   │   ├── Git.tsx           ← Git panel + visual diff
│   │   ├── CI.tsx            ← GitHub Actions status
│   │   ├── AI.tsx            ← Mascarade chat panel
│   │   ├── Firmware.tsx      ← Monaco editor + PIO
│   │   └── Settings.tsx
│   ├── components/
│   │   ├── kanban/
│   │   ├── diff-viewer/
│   │   ├── bom-viewer/
│   │   ├── terminal/
│   │   └── blocks-browser/
│   └── stores/
│       ├── project.ts
│       ├── git.ts
│       └── ai.ts
├── workflows/                ← GitHub Actions templates shipped with app
│   ├── makelife-drc.yml
│   ├── makelife-gerber.yml
│   ├── makelife-3d.yml
│   └── makelife-firmware.yml
├── package.json
├── electron-builder.yml
├── vite.config.ts
└── tsconfig.json
```

## Success Criteria

1. App launches, detects KiCad + FreeCAD + PlatformIO installations
2. Can create a MakeLife project, open KiCad/FreeCAD files from explorer
3. Git clone/commit/push works, visual diff generates schematic images
4. GitHub issues/PR/kanban visible and editable from the app
5. AI panel connects to mascarade-core and answers EE questions with project context
6. Monaco editor opens firmware files, PlatformIO build/test/flash works
7. CI templates install into project, Actions status visible in app
8. Builds and packages for macOS/Linux/Windows
9. Auto-update works via GitHub Releases
