import Foundation

// MARK: - NewProjectScaffolder

/// Creates the standard FineFab/MakeLife project directory structure.
///
/// Produced layout:
/// ```
/// {dest}/{repoName}/
/// ├── .gitignore
/// ├── .github/workflows/ci.yml
/// ├── hardware/
/// │   ├── pcb/{boardName}/
/// │   │   ├── {boardName}.kicad_pro
/// │   │   ├── {boardName}.kicad_sch
/// │   │   ├── {boardName}.kicad_pcb
/// │   │   ├── fp-lib-table
/// │   │   └── library/
/// │   ├── simulation/
/// │   └── bom/
/// ├── firmware/
/// ├── docs/
/// └── fabrication/
/// ```
struct NewProjectScaffolder {

    enum RepoVisibility { case `public`, `private` }

    let repoName: String
    let boardName: String
    let destination: URL
    let gitInit: Bool
    let createGitHubRepo: Bool
    let repoVisibility: RepoVisibility
    let ghOrg: String   // empty = personal account

    // MARK: - Result

    struct ScaffoldResult {
        let repoURL: URL
        let projectFileURL: URL   // the .kicad_pro to open
        let log: String
    }

    // MARK: - Scaffold (runs synchronously on a background thread)

    func scaffold() throws -> ScaffoldResult {
        let fm  = FileManager.default
        let repoURL = destination.appendingPathComponent(repoName)
        var log = ""

        // Helpers
        func mkdir(_ url: URL) throws {
            try fm.createDirectory(at: url, withIntermediateDirectories: true)
            log += "mkdir  \(url.path.replacingOccurrences(of: destination.path, with: ""))\n"
        }
        func write(_ url: URL, _ content: String) throws {
            try content.write(to: url, atomically: true, encoding: .utf8)
            log += "write  \(url.path.replacingOccurrences(of: repoURL.path + "/", with: ""))\n"
        }

        // ── Guard: repo folder must not already exist ──────────────────────────
        if fm.fileExists(atPath: repoURL.path) {
            throw CocoaError(.fileWriteFileExists,
                             userInfo: [NSFilePathErrorKey: repoURL.path,
                                        NSLocalizedDescriptionKey:
                                            "Folder \"\(repoName)\" already exists at destination."])
        }

        // ── Top-level structure ────────────────────────────────────────────────
        try mkdir(repoURL)
        try mkdir(repoURL.appendingPathComponent(".github/workflows"))

        // ── hardware/ ─────────────────────────────────────────────────────────
        let boardDir = repoURL.appendingPathComponent("hardware/pcb/\(boardName)")
        try mkdir(boardDir)
        try mkdir(boardDir.appendingPathComponent("library"))
        try mkdir(repoURL.appendingPathComponent("hardware/simulation"))
        try mkdir(repoURL.appendingPathComponent("hardware/bom"))

        // ── Other top-level dirs ───────────────────────────────────────────────
        try mkdir(repoURL.appendingPathComponent("firmware"))
        try mkdir(repoURL.appendingPathComponent("docs"))
        try mkdir(repoURL.appendingPathComponent("fabrication"))

        // ── .gitignore ─────────────────────────────────────────────────────────
        try write(repoURL.appendingPathComponent(".gitignore"), gitignoreContent)

        // ── CI workflow ────────────────────────────────────────────────────────
        try write(
            repoURL.appendingPathComponent(".github/workflows/ci.yml"),
            ciWorkflowContent(boardName: boardName)
        )

        // ── KiCad project files ────────────────────────────────────────────────
        let proURL = boardDir.appendingPathComponent("\(boardName).kicad_pro")
        try write(proURL,                                  kicadProContent(boardName: boardName))
        try write(boardDir.appendingPathComponent("\(boardName).kicad_sch"), kicadSchContent(boardName: boardName))
        try write(boardDir.appendingPathComponent("\(boardName).kicad_pcb"), kicadPcbContent(boardName: boardName))
        try write(boardDir.appendingPathComponent("fp-lib-table"),            fpLibTable)

        // ── docs/README ────────────────────────────────────────────────────────
        try write(repoURL.appendingPathComponent("docs/README.md"),
                  "# \(repoName)\n\nKiCad project: `hardware/pcb/\(boardName)/`\n")

        // ── git init ───────────────────────────────────────────────────────────
        if gitInit {
            log += "\n--- git init ---\n"
            log += shell("/usr/bin/git", ["-C", repoURL.path, "init"]).output
            log += shell("/usr/bin/git", ["-C", repoURL.path, "add", "."]).output
            log += shell("/usr/bin/git", ["-C", repoURL.path,
                "commit", "-m",
                "chore: initial scaffold (\(boardName) KiCad project)"]).output
        }

        // ── gh repo create ─────────────────────────────────────────────────────
        if createGitHubRepo {
            log += "\n--- gh repo create ---\n"
            var ghArgs = ["repo", "create"]
            let slug   = ghOrg.isEmpty ? repoName : "\(ghOrg)/\(repoName)"
            ghArgs += [slug,
                       "--\(repoVisibility == .public ? "public" : "private")",
                       "--source", repoURL.path,
                       "--remote", "origin",
                       "--push"]
            let ghPath = resolveGH()
            log += shell(ghPath, ghArgs).output
        }

        return ScaffoldResult(repoURL: repoURL, projectFileURL: proURL, log: log)
    }

    // MARK: - Shell helpers

    private struct ShellResult { let output: String; let ok: Bool }

    private func shell(_ executable: String, _ args: [String]) -> ShellResult {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: executable)
        proc.arguments = args
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
        proc.environment = env
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError  = pipe
        try? proc.run()
        proc.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let out  = String(data: data, encoding: .utf8) ?? ""
        return ShellResult(output: out, ok: proc.terminationStatus == 0)
    }

    private func resolveGH() -> String {
        let candidates = ["/opt/homebrew/bin/gh", "/usr/local/bin/gh", "/usr/bin/gh"]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
            ?? "/opt/homebrew/bin/gh"
    }

    // MARK: - File templates

    private var gitignoreContent: String {
        """
        # ── KiCad ────────────────────────────────────────────────────────────────
        *.bak
        *.kicad_prl
        *-backups/
        fp-info-cache
        _autosave-*
        *.lck

        # ── macOS ─────────────────────────────────────────────────────────────────
        .DS_Store
        .AppleDouble
        .LSOverride

        # ── Fabrication outputs (keep in fabrication/, not under pcb/) ────────────
        hardware/pcb/**/*.gbr
        hardware/pcb/**/*.drl
        hardware/pcb/**/*.zip
        hardware/pcb/**/*.rpt

        # ── Firmware build artefacts ───────────────────────────────────────────────
        firmware/**/.pio/
        firmware/**/build/
        firmware/**/.cache/
        """
    }

    private func ciWorkflowContent(boardName: String) -> String {
        """
        name: KiCad CI

        on:
          push:
            branches: [main]
          pull_request:
            branches: [main]

        jobs:
          drc-erc:
            runs-on: ubuntu-latest
            container: ghcr.io/inti-cmnb/kicad8_auto:latest

            steps:
              - uses: actions/checkout@v4

              - name: Run ERC
                run: |
                  kicad-cli sch erc \\
                    --output hardware/pcb/\(boardName)/erc.rpt \\
                    hardware/pcb/\(boardName)/\(boardName).kicad_sch

              - name: Run DRC
                run: |
                  kicad-cli pcb drc \\
                    --output hardware/pcb/\(boardName)/drc.rpt \\
                    hardware/pcb/\(boardName)/\(boardName).kicad_pcb

              - name: Upload reports
                if: always()
                uses: actions/upload-artifact@v4
                with:
                  name: drc-erc-reports
                  path: hardware/pcb/\(boardName)/*.rpt
        """
    }

    private func kicadProContent(boardName: String) -> String {
        """
        {
          "board": {
            "3dviewports": [],
            "design_settings": {},
            "layer_presets": [],
            "viewports": []
          },
          "boards": [],
          "cvpcb": {
            "equivalence_files": []
          },
          "libraries": {
            "pinned_footprint_libs": [],
            "pinned_symbol_libs": []
          },
          "meta": {
            "filename": "\(boardName).kicad_pro",
            "version": 1
          },
          "net_settings": {
            "classes": [
              {
                "bus_width": 12,
                "clearance": 0.2,
                "diff_pair_gap": 0.25,
                "diff_pair_via_gap": 0.25,
                "diff_pair_width": 0.2,
                "line_style": 0,
                "microvia_diameter": 0.3,
                "microvia_drill": 0.1,
                "name": "Default",
                "pcb_color": "rgba(0, 0, 0, 0.000)",
                "schematic_color": "rgba(0, 0, 0, 0.000)",
                "track_width": 0.25,
                "via_diameter": 0.8,
                "via_drill": 0.4,
                "wire_width": 6
              }
            ],
            "meta": { "version": 3 },
            "net_colors": null,
            "netclass_assignments": null,
            "netclass_patterns": []
          },
          "pcbnew": {
            "last_paths": {},
            "page_layout_descr_file": ""
          },
          "schematic": {
            "annotate_start_num": 0,
            "drawing": {
              "dashed_lines_dash_length_ratio": 12.0,
              "dashed_lines_gap_length_ratio": 3.0,
              "default_bus_thickness": 12.0,
              "default_junction_size": 40.0,
              "default_line_thickness": 6.0,
              "default_text_size": 50.0,
              "default_wire_thickness": 6.0,
              "field_names": [],
              "intersheets_ref_own_page": false,
              "intersheets_ref_prefix": "",
              "intersheets_ref_short": false,
              "intersheets_ref_show": false,
              "intersheets_ref_suffix": "",
              "junction_size_choice": 3,
              "label_size_ratio": 0.375,
              "pin_symbol_size": 0.0,
              "text_offset_ratio": 0.15
            },
            "legacy_lib_dir": "",
            "legacy_lib_list": []
          },
          "sheets": [],
          "text_variables": {}
        }
        """
    }

    private func kicadSchContent(boardName: String) -> String {
        let title = boardName.replacingOccurrences(of: "\"", with: "\\\"")
        return """
        (kicad_sch
          (version 20231120)
          (generator "MakelifeCAD")
          (generator_version "1.0")
          (paper "A4")
          (title_block
            (title "\(title)")
            (date "")
            (rev "v1.0")
            (company "")
          )
          (lib_symbols
          )
          (sheet_instances
            (path "/" (page "1"))
          )
          (symbol_instances
          )
        )
        """
    }

    private func kicadPcbContent(boardName: String) -> String {
        let title = boardName.replacingOccurrences(of: "\"", with: "\\\"")
        return """
        (kicad_pcb
          (version 20231120)
          (generator "MakelifeCAD")
          (generator_version "1.0")
          (general
            (thickness 1.6)
            (legacy_teardrops no)
          )
          (paper "A4")
          (title_block
            (title "\(title)")
            (date "")
            (rev "v1.0")
            (company "")
          )
          (layers
            (0 "F.Cu" signal)
            (31 "B.Cu" signal)
            (32 "B.Adhes" user "B.Adhesive")
            (33 "F.Adhes" user "F.Adhesive")
            (34 "B.Paste" user)
            (35 "F.Paste" user)
            (36 "B.SilkS" user "B.Silkscreen")
            (37 "F.SilkS" user "F.Silkscreen")
            (38 "B.Mask" user)
            (39 "F.Mask" user)
            (40 "Dwgs.User" user "User.Drawings")
            (41 "Cmts.User" user "User.Comments")
            (42 "Eco1.User" user "User.Eco1")
            (43 "Eco2.User" user "User.Eco2")
            (44 "Edge.Cuts" user)
            (45 "Margin" user)
            (46 "B.CrtYd" user "B.Courtyard")
            (47 "F.CrtYd" user "F.Courtyard")
            (48 "B.Fab" user)
            (49 "F.Fab" user)
          )
          (setup
            (pad_to_mask_clearance 0.05)
            (allow_soldermask_bridges_in_footprints no)
          )
          (net 0 "")
        )
        """
    }

    private var fpLibTable: String {
        """
        (fp_lib_table
          (version 7)
          (lib (name "library")(type "KiCad")(uri "${KIPRJMOD}/library")(options "")(descr "Local project library"))
        )
        """
    }
}
