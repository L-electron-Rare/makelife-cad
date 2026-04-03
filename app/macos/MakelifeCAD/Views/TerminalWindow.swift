import SwiftUI

// MARK: - Preset command

struct TerminalPreset: Identifiable, Hashable {
    let id = UUID()
    let label: String
    let icon: String
    let executable: String
    let args: [String]
    let cwdRelative: String?  // relative to project root, nil = home
}

// MARK: - TerminalWindowView

struct TerminalWindowView: View {
    @EnvironmentObject var runner: CommandRunner
    @EnvironmentObject var projectManager: YiacadProjectManager

    @State private var customCommand = ""
    @State private var selectedPreset: TerminalPreset?

    /// Firmware repo root — 2 levels up from app/macos, then makelife-firmware
    private var firmwareCWD: URL? {
        guard let root = projectManager.currentProject?.rootURL
                       ?? URL(string: "file:///") else { return nil }
        // Try to find makelife-firmware relative to project root
        let candidate = root
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("makelife-firmware")
        return FileManager.default.fileExists(atPath: candidate.path) ? candidate : nil
    }

    private var presets: [TerminalPreset] {
        let fw = firmwareCWD
        return [
            TerminalPreset(label: "PlatformIO Build",    icon: "hammer",
                           executable: "/usr/local/bin/pio",
                           args: ["run"],
                           cwdRelative: nil),
            TerminalPreset(label: "PlatformIO Upload",   icon: "arrow.up.to.line",
                           executable: "/usr/local/bin/pio",
                           args: ["run", "-t", "upload"],
                           cwdRelative: nil),
            TerminalPreset(label: "PlatformIO Monitor",  icon: "terminal",
                           executable: "/usr/local/bin/pio",
                           args: ["device", "monitor"],
                           cwdRelative: nil),
            TerminalPreset(label: "ESP-IDF Build",       icon: "bolt",
                           executable: "/bin/bash",
                           args: ["-c", "source ~/esp/esp-idf/export.sh && idf.py build"],
                           cwdRelative: fw?.path),
            TerminalPreset(label: "ESP-IDF Flash",       icon: "arrow.up.circle",
                           executable: "/bin/bash",
                           args: ["-c", "source ~/esp/esp-idf/export.sh && idf.py flash"],
                           cwdRelative: fw?.path),
            TerminalPreset(label: "kicad-bridge build",  icon: "wrench.and.screwdriver",
                           executable: "/usr/bin/cmake",
                           args: ["--build", "build/kicad-bridge"],
                           cwdRelative: nil),
        ]
    }

    var body: some View {
        HSplitView {
            presetList
            VStack(spacing: 0) {
                outputArea
                Divider()
                inputBar
            }
        }
        .frame(minWidth: 720, minHeight: 360)
        .navigationTitle("Terminal")
    }

    // MARK: Preset list

    private var presetList: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Presets")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .padding(.bottom, 6)
            Divider()
            List(presets, selection: $selectedPreset) { preset in
                Label(preset.label, systemImage: preset.icon)
                    .font(.callout)
                    .tag(preset)
                    .onTapGesture(count: 2) { runPreset(preset) }
            }
            .listStyle(.sidebar)
            Divider()
            Button("Run") {
                if let p = selectedPreset { runPreset(p) }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(selectedPreset == nil || runner.isRunning)
            .padding(10)
        }
        .frame(minWidth: 180, idealWidth: 200, maxWidth: 240)
    }

    // MARK: Output area

    private var outputArea: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(runner.lines) { line in
                        Text(line.text)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(line.isError ? Color.red.opacity(0.85) : .primary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id(line.id)
                    }
                    if let code = runner.exitCode {
                        Text("─── exit \(code) ───")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(code == 0 ? Color.green : Color.red)
                            .padding(.top, 4)
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(10)
            }
            .background(Color(.textBackgroundColor))
            .onChange(of: runner.lines.count) { _, _ in
                proxy.scrollTo("bottom")
            }
        }
    }

    // MARK: Input bar

    private var inputBar: some View {
        HStack(spacing: 8) {
            Text("$")
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.secondary)
            TextField("command…", text: $customCommand)
                .textFieldStyle(.plain)
                .font(.system(.body, design: .monospaced))
                .onSubmit { runCustom() }
            if runner.isRunning {
                ProgressView().scaleEffect(0.7)
                Button("Stop") { runner.stop() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            } else {
                Button("Run") { runCustom() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(customCommand.trimmingCharacters(in: .whitespaces).isEmpty)
                Button(action: { runner.clear() }) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.plain)
                .help("Clear output")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
    }

    // MARK: Actions

    private func runPreset(_ preset: TerminalPreset) {
        let cwd = preset.cwdRelative.map { URL(fileURLWithPath: $0) }
        runner.run(preset.executable, args: preset.args, cwd: cwd)
    }

    private func runCustom() {
        let cmd = customCommand.trimmingCharacters(in: .whitespaces)
        guard !cmd.isEmpty else { return }
        runner.run("/bin/bash", args: ["-c", cmd], cwd: firmwareCWD)
        customCommand = ""
    }
}
