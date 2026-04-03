# Repository Guidelines

## Project Structure & Module Organization
The macOS app lives under `MakelifeCAD/MakelifeCAD/`. `App.swift` is the SwiftUI entry point. UI code is organized in `Views/` with feature-focused files such as `PCBEditorView.swift`, `SchematicView.swift`, and `AIPanel.swift`. State and integration logic live in `Models/`, including view models, API clients, and command execution helpers. Native bridge code is in `Bridge/`, including `KiCadBridge.swift` and `MakelifeCAD-Bridging-Header.h`. Shared assets are stored in `Assets.xcassets`. Tests are in `MakelifeCAD/MakelifeCADTests/`.

## Build, Test, and Development Commands
Use Xcode for day-to-day development on the `MakelifeCAD` scheme. Typical local commands:

`xcodebuild -project MakelifeCAD.xcodeproj -scheme MakelifeCAD build`
Builds the macOS app from the command line.

`xcodebuild -project MakelifeCAD.xcodeproj -scheme MakelifeCAD test`
Runs the XCTest suite, including `FreeCADSupportTests.swift`.

`xcodebuild -project MakelifeCAD.xcodeproj -scheme MakelifeCAD -destination 'platform=macOS' build`
Useful for CI-style local verification.

## Coding Style & Naming Conventions
Use Swift conventions throughout: 4-space indentation, `PascalCase` for types and view files, and `camelCase` for properties and methods. Keep one primary type per file where practical. Group code by responsibility: UI in `Views/`, state and services in `Models/`, bridge interop in `Bridge/`. Prefer SwiftUI-native patterns, avoid force unwraps, and keep comments limited to non-obvious logic.

## Testing Guidelines
Tests currently use XCTest. Add new unit tests under `MakelifeCAD/MakelifeCADTests/` and name them after the feature under test, for example `KiCadProjectTests.swift`. Keep test methods descriptive, such as `testLoadsProjectMetadata()`. Run the full test suite before opening a PR; for risky changes in bridge or document logic, add focused regression coverage.

## Commit & Pull Request Guidelines
Recent history follows short conventional prefixes like `fix:`, `chore:`, `docs:`, and scoped forms such as `fix(gateway):`. Continue using concise, imperative subjects, for example `fix: handle empty PCB selection`. PRs should include a short summary, impacted areas, validation steps, and screenshots for SwiftUI changes affecting panels, editors, or previews.

## Configuration & Integration Notes
Do not hardcode machine-specific paths, tokens, or KiCad/FreeCAD installation details. Isolate external tool access in model or bridge layers so views remain focused on presentation. When changing bridge headers or native integration, verify both build success and the affected UI workflow.
