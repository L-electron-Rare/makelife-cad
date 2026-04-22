import SwiftUI
import UniformTypeIdentifiers

// MARK: - Gerber export layer presets

struct GerberLayerPreset: Identifiable {
    let id: String
    let label: String
    var enabled: Bool
}

// MARK: - GerberExportView

struct GerberExportView: View {
    @EnvironmentObject var pcbBridge: KiCadPCBBridge
    @EnvironmentObject var projectManager: YiacadProjectManager

    @AppStorage(Prefs.kicadCLIPath) private var kicadCLIOverride = ""

    @State private var outputDir: URL?
    @State private var isExporting = false
    @State private var exportLog = ""
    @State private var exportSuccess: Bool?
    @State private var includeDrills = true

    @State private var layerPresets: [GerberLayerPreset] = [
        GerberLayerPreset(id: "F.Cu",     label: "Front Copper",    enabled: true),
        GerberLayerPreset(id: "B.Cu",     label: "Back Copper",     enabled: true),
        GerberLayerPreset(id: "F.Paste",  label: "Front Paste",     enabled: true),
        GerberLayerPreset(id: "B.Paste",  label: "Back Paste",      enabled: true),
        GerberLayerPreset(id: "F.SilkS",  label: "Front Silkscreen", enabled: true),
        GerberLayerPreset(id: "B.SilkS",  label: "Back Silkscreen", enabled: true),
        GerberLayerPreset(id: "F.Mask",   label: "Front Mask",      enabled: true),
        GerberLayerPreset(id: "B.Mask",   label: "Back Mask",       enabled: true),
        GerberLayerPreset(id: "Edge.Cuts", label: "Board Outline",  enabled: true),
    ]

    var body: some View {
        if !pcbBridge.isLoaded {
            emptyState
        } else {
            mainContent
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "cpu")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)
            Text("No PCB loaded")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("Open a .kicad_pcb file first")
                .font(.callout)
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Main content

    private var mainContent: some View {
        HSplitView {
            // Left: layer selection
            layerSelection
                .frame(minWidth: 200, idealWidth: 240, maxWidth: 280)

            // Right: output config + actions + log
            VStack(alignment: .leading, spacing: 16) {
                outputConfig
                actionButtons
                if !exportLog.isEmpty {
                    logView
                }
                Spacer()
            }
            .padding(16)
            .frame(maxWidth: .infinity)
        }
        .frame(minWidth: 600, minHeight: 400)
        .navigationTitle("Gerber Export")
        .onAppear {
            // Default output to project's gerber/ directory
            if outputDir == nil, let root = projectManager.currentProject?.rootURL {
                outputDir = root.appendingPathComponent("gerber")
            }
        }
    }

    // MARK: - Layer selection

    private var layerSelection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Layers")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .padding(.bottom, 6)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach($layerPresets) { $preset in
                        Toggle(isOn: $preset.enabled) {
                            HStack(spacing: 8) {
                                Text(preset.label)
                                    .font(.callout)
                                Spacer()
                                Text(preset.id)
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 3)
                    }

                    Divider().padding(.vertical, 6)

                    Toggle("Include drill files", isOn: $includeDrills)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 3)
                }
                .padding(.vertical, 8)
            }
            Divider()
            HStack(spacing: 8) {
                Button("All") {
                    for i in layerPresets.indices { layerPresets[i].enabled = true }
                }
                .controlSize(.small)
                Button("None") {
                    for i in layerPresets.indices { layerPresets[i].enabled = false }
                }
                .controlSize(.small)
                Spacer()
                Text("\(layerPresets.filter(\.enabled).count) layers")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(10)
        }
        .adaptiveSidebarBackground()
    }

    // MARK: - Output config

    private var outputConfig: some View {
        GroupBox("Output Directory") {
            HStack {
                if let dir = outputDir {
                    Text(dir.path)
                        .font(.system(.caption, design: .monospaced))
                        .lineLimit(1)
                        .truncationMode(.middle)
                } else {
                    Text("Not selected")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Choose…") { chooseOutputDir() }
                    .controlSize(.small)
            }

            if let resolved = resolveKicadCLI() {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.caption)
                    Text(resolved)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            } else {
                HStack(spacing: 6) {
                    Image(systemName: "xmark.circle")
                        .foregroundStyle(.red)
                        .font(.caption)
                    Text("kicad-cli not found — install KiCad or set path in Settings → Tools")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
    }

    // MARK: - Action buttons

    private var actionButtons: some View {
        HStack(spacing: 12) {
            Button {
                Task { await runExport() }
            } label: {
                if isExporting {
                    ProgressView()
                        .scaleEffect(0.7)
                        .frame(width: 14, height: 14)
                    Text("Exporting…")
                } else {
                    Image(systemName: "square.and.arrow.up")
                    Text("Export Gerbers")
                }
            }
            .adaptiveGlassButtonStyle()
            .disabled(isExporting || outputDir == nil
                      || resolveKicadCLI() == nil
                      || layerPresets.filter(\.enabled).isEmpty)

            if let success = exportSuccess {
                Image(systemName: success ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(success ? .green : .red)
                Text(success ? "Export complete" : "Export failed")
                    .font(.callout)
                    .foregroundColor(success ? .secondary : .red)
            }

            Spacer()

            if exportSuccess == true, let dir = outputDir {
                Button("Reveal in Finder") {
                    NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: dir.path)
                }
                .controlSize(.small)
            }
        }
    }

    // MARK: - Log

    private var logView: some View {
        GroupBox("Export Log") {
            ScrollView {
                Text(exportLog)
                    .font(.system(.caption2, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .frame(maxHeight: 180)
        }
    }

    // MARK: - Actions

    private func chooseOutputDir() {
        let panel = NSOpenPanel()
        panel.title = "Choose Gerber Output Directory"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        if panel.runModal() == .OK, let url = panel.url {
            outputDir = url
        }
    }

    private func resolveKicadCLI() -> String? {
        if !kicadCLIOverride.isEmpty,
           FileManager.default.fileExists(atPath: kicadCLIOverride) {
            return kicadCLIOverride
        }
        let candidates = [
            "/Applications/KiCad/KiCad.app/Contents/MacOS/kicad-cli",
            "/opt/homebrew/bin/kicad-cli",
            "/usr/local/bin/kicad-cli",
        ]
        return candidates.first { FileManager.default.fileExists(atPath: $0) }
    }

    private func runExport() async {
        guard let cli = resolveKicadCLI(),
              let dir = outputDir,
              let pcbPath = projectManager.currentProject?.pcbURL.path else { return }

        isExporting = true
        exportLog = ""
        exportSuccess = nil

        // Ensure output directory exists
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let enabledLayers = layerPresets.filter(\.enabled).map(\.id)

        // Build kicad-cli gerber command
        var gerberArgs = ["pcb", "export", "gerbers",
                          "--output", dir.path + "/",
                          "--layers", enabledLayers.joined(separator: ",")]
        gerberArgs.append(pcbPath)

        exportLog += "$ \(cli) \(gerberArgs.joined(separator: " "))\n"
        let gerberResult = await runProcess(cli, arguments: gerberArgs)
        exportLog += gerberResult.output
        if gerberResult.exitCode != 0 {
            exportLog += "\nGerber export failed (exit \(gerberResult.exitCode))\n"
            exportSuccess = false
            isExporting = false
            return
        }
        exportLog += "Gerber export OK\n"

        // Drill files
        if includeDrills {
            let drillArgs = ["pcb", "export", "drill",
                             "--output", dir.path + "/",
                             pcbPath]

            exportLog += "\n$ \(cli) \(drillArgs.joined(separator: " "))\n"
            let drillResult = await runProcess(cli, arguments: drillArgs)
            exportLog += drillResult.output
            if drillResult.exitCode != 0 {
                exportLog += "\nDrill export failed (exit \(drillResult.exitCode))\n"
                exportSuccess = false
                isExporting = false
                return
            }
            exportLog += "Drill export OK\n"
        }

        exportSuccess = true
        isExporting = false
    }

    private func runProcess(_ path: String, arguments: [String]) async -> (output: String, exitCode: Int32) {
        await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: path)
            process.arguments = arguments
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            do {
                try process.run()
                process.waitUntilExit()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""
                continuation.resume(returning: (output, process.terminationStatus))
            } catch {
                continuation.resume(returning: ("Failed to launch: \(error.localizedDescription)\n", -1))
            }
        }
    }
}
