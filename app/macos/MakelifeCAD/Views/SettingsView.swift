import SwiftUI
import AppKit

// MARK: - Dependency status model

struct DependencyStatus: Identifiable {
    var id: String { name }
    let name: String
    let installCmd: String
    var path: String?
    var found: Bool { path != nil }
}

// MARK: - UserDefaults keys

enum Prefs {
    static let gatewayURL    = "finefab.gateway.url"
    static let ghCLIPath     = "tools.gh.path"
    static let kicadCLIPath  = "tools.kicad.cli.path"
    static let freecadPath   = "tools.freecad.path"
    static let defaultBranch = "git.default.branch"
    static let autoStage     = "git.auto.stage"
    static let githubPAT     = "github.pat"
}

// MARK: - Root

struct SettingsView: View {
    @EnvironmentObject var fineFabVM: FineFabViewModel
    @EnvironmentObject var gitRepoVM: GitHubRepoViewModel

    var body: some View {
        TabView {
            GeneralPane(fineFabVM: fineFabVM)
                .tabItem { Label("General", systemImage: "gear") }

            GitHubPane(gitRepoVM: gitRepoVM)
                .tabItem { Label("GitHub", systemImage: "arrow.triangle.branch") }

            ToolsPane()
                .tabItem { Label("Tools", systemImage: "wrench.and.screwdriver") }

            SetupPane()
                .tabItem { Label("Setup", systemImage: "shippingbox") }
        }
        .frame(width: 580, height: 460)
    }
}

// MARK: - General

private struct GeneralPane: View {
    @ObservedObject var fineFabVM: FineFabViewModel
    @AppStorage(Prefs.defaultBranch) var defaultBranch = "main"
    @AppStorage(Prefs.autoStage)     var autoStage     = false
    @State private var gatewayInput  = ""
    @State private var isCheckingGW  = false
    @State private var gwStatus: GatewayStatus = .unknown

    enum GatewayStatus { case unknown, ok, error }

    var body: some View {
        Form {
            Section("AI Gateway") {
                HStack(spacing: 8) {
                    TextField("http://localhost:8001", text: $gatewayInput)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                    Circle()
                        .fill(gwStatusColor)
                        .frame(width: 8, height: 8)
                }
                HStack {
                    Button("Apply") {
                        fineFabVM.baseURL = gatewayInput
                        gwStatus = .unknown
                    }
                    .disabled(gatewayInput == fineFabVM.baseURL)

                    Button {
                        isCheckingGW = true
                        Task {
                            await fineFabVM.checkStatus()
                            gwStatus = fineFabVM.isConnected ? .ok : .error
                            isCheckingGW = false
                        }
                    } label: {
                        if isCheckingGW {
                            ProgressView().scaleEffect(0.7)
                        } else {
                            Text("Check Connection")
                        }
                    }
                    .disabled(isCheckingGW)

                    Spacer()
                    Text(fineFabVM.baseURL)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }

            Section("Git Defaults") {
                LabeledContent("Default Branch") {
                    TextField("main", text: $defaultBranch)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 160)
                }
                Toggle("Auto-stage KiCad files on save", isOn: $autoStage)
                    .help("Automatically run `git add` on .kicad_sch/.kicad_pcb after saving")
            }
        }
        .formStyle(.grouped)
        .onAppear { gatewayInput = fineFabVM.baseURL }
        .padding(20)
    }

    private var gwStatusColor: Color {
        switch gwStatus {
        case .unknown: return .secondary
        case .ok:      return .green
        case .error:   return .red
        }
    }
}

// MARK: - GitHub

private struct GitHubPane: View {
    @ObservedObject var gitRepoVM: GitHubRepoViewModel
    @AppStorage(Prefs.githubPAT)   var githubPAT  = ""
    @AppStorage(Prefs.ghCLIPath)   var ghCLIPath  = ""
    @State private var isChecking = false
    @State private var showPAT    = false

    var body: some View {
        Form {
            Section("Authentication") {
                authStatusRow
                Divider()
                    .padding(.vertical, 2)
                HStack(spacing: 8) {
                    Button("Authenticate via Browser") {
                        openTerminalWith(command: "gh auth login --web")
                    }
                    .help("Opens Terminal and runs `gh auth login --web`")

                    Button {
                        isChecking = true
                        Task {
                            await gitRepoVM.checkAuth()
                            isChecking = false
                        }
                    } label: {
                        if isChecking { ProgressView().scaleEffect(0.7) }
                        else { Text("Refresh Status") }
                    }
                    .disabled(isChecking)
                }
            }

            Section("Personal Access Token (optional)") {
                HStack {
                    if showPAT {
                        TextField("ghp_…", text: $githubPAT)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.body, design: .monospaced))
                    } else {
                        SecureField("ghp_…", text: $githubPAT)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.body, design: .monospaced))
                    }
                    Button { showPAT.toggle() } label: {
                        Image(systemName: showPAT ? "eye.slash" : "eye")
                    }
                    .buttonStyle(.plain)
                }
                Text("Used as fallback when gh CLI is not authenticated.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Link("Create token on GitHub", destination: URL(string: "https://github.com/settings/tokens/new?scopes=repo,read:user")!)
                    .font(.caption)
            }

            Section("gh CLI Path") {
                LabeledContent("Detected") {
                    Text(detectedGHPath)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                LabeledContent("Override") {
                    TextField("/opt/homebrew/bin/gh", text: $ghCLIPath)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.caption, design: .monospaced))
                }
                Text("Leave empty to use the auto-detected path.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(20)
        .task { await gitRepoVM.checkAuth() }
    }

    private var authStatusRow: some View {
        HStack(spacing: 8) {
            Image(systemName: gitRepoVM.authUser != nil ? "checkmark.seal.fill" : "xmark.seal")
                .foregroundStyle(gitRepoVM.authUser != nil ? Color.green : Color.red)
            if let user = gitRepoVM.authUser {
                Text("Logged in as ").font(.callout) +
                Text(user).font(.callout.bold()) +
                Text(" on github.com").font(.callout)
            } else {
                Text(gitRepoVM.authError ?? "Not authenticated")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var detectedGHPath: String {
        let candidates = ["/opt/homebrew/bin/gh", "/usr/local/bin/gh"]
        return candidates.first { FileManager.default.fileExists(atPath: $0) } ?? "not found"
    }
}

// MARK: - Tools

private struct ToolsPane: View {
    @AppStorage(Prefs.kicadCLIPath) var kicadCLIPath = ""
    @AppStorage(Prefs.freecadPath)  var freecadPath  = ""
    @AppStorage(Prefs.ghCLIPath)    var ghCLIPath    = ""

    var body: some View {
        Form {
            Section("KiCad") {
                toolRow(label: "kicad-cli",
                        detected: detect(["kicad-cli",
                                          "/Applications/KiCad/KiCad.app/Contents/MacOS/kicad-cli",
                                          "/opt/homebrew/bin/kicad-cli"]),
                        binding: $kicadCLIPath,
                        placeholder: "/Applications/KiCad/KiCad.app/Contents/MacOS/kicad-cli")
                    Link("Download KiCad", destination: URL(string: "https://www.kicad.org/download/macos/")!)
                        .font(.caption)
            }

            Section("FreeCAD") {
                toolRow(label: "FreeCAD.app",
                        detected: detect(["FreeCAD",
                                          "/Applications/FreeCAD.app/Contents/MacOS/FreeCAD"]),
                        binding: $freecadPath,
                        placeholder: "/Applications/FreeCAD.app")
                Link("Download FreeCAD 1.1.x", destination: URL(string: "https://github.com/FreeCAD/FreeCAD/releases")!)
                    .font(.caption)
            }

            Section("GitHub CLI") {
                toolRow(label: "gh",
                        detected: detect(["/opt/homebrew/bin/gh", "/usr/local/bin/gh"]),
                        binding: $ghCLIPath,
                        placeholder: "/opt/homebrew/bin/gh")
                Link("Install gh CLI", destination: URL(string: "https://cli.github.com")!)
                    .font(.caption)
            }
        }
        .formStyle(.grouped)
        .padding(20)
    }

    private func toolRow(label: String, detected: String?, binding: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: detected != nil ? "checkmark.circle.fill" : "xmark.circle")
                    .foregroundStyle(detected != nil ? Color.green : Color.red)
                    .font(.caption)
                Text(label).font(.callout.bold())
                Spacer()
                if let d = detected {
                    Text(d).font(.system(.caption2, design: .monospaced)).foregroundStyle(.secondary)
                } else {
                    Text("not found").font(.caption2).foregroundStyle(.red)
                }
            }
            TextField(placeholder, text: binding)
                .textFieldStyle(.roundedBorder)
                .font(.system(.caption, design: .monospaced))
        }
    }

    private func detect(_ paths: [String]) -> String? {
        for path in paths {
            if path.hasPrefix("/") {
                if FileManager.default.fileExists(atPath: path) { return path }
            }
        }
        return nil
    }
}

// MARK: - Setup

private struct SetupPane: View {
    @State private var statuses: [DependencyStatus] = []
    @State private var isChecking = false
    @State private var log = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Status grid
            VStack(spacing: 2) {
                ForEach(statuses, id: \.name) { tool in
                    dependencyRow(tool)
                }
            }
            .padding(.top, 16)

            Divider().padding(.top, 8)

            // Actions
            HStack(spacing: 10) {
                Button {
                    Task { await runCheck() }
                } label: {
                    if isChecking { ProgressView().scaleEffect(0.7) }
                    else { Label("Check Status", systemImage: "arrow.clockwise") }
                }
                .disabled(isChecking)

                Button {
                    installMissing()
                } label: {
                    Label("Install Missing via Homebrew", systemImage: "shippingbox")
                }
                .disabled(isChecking || statuses.filter { !$0.found }.isEmpty)
                .buttonStyle(.borderedProminent)

                Spacer()

                Button("Authenticate gh CLI") {
                    openTerminalWith(command: "gh auth login --web")
                }
                .help("Opens Terminal with `gh auth login --web`")
            }
            .padding(16)

            // Log
            if !log.isEmpty {
                Divider()
                ScrollView {
                    Text(log)
                        .font(.system(.caption2, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .textSelection(.enabled)
                }
                .frame(maxHeight: 120)
                .background(Color(.windowBackgroundColor).opacity(0.6))
            }

            Spacer()
        }
        .task { await runCheck() }
    }

    // MARK: Row view

    @ViewBuilder
    private func dependencyRow(_ tool: DependencyStatus) -> some View {
        HStack(spacing: 10) {
            Image(systemName: tool.found ? "checkmark.circle.fill" : "xmark.circle")
                .foregroundStyle(tool.found ? Color.green : Color.red)
                .frame(width: 18)
            Text(tool.name).font(.callout)
            Spacer()
            Text(tool.path ?? "not found")
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(tool.found ? Color.secondary : Color.red)
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 16)
    }

    // MARK: Checks

    private func runCheck() async {
        isChecking = true
        let defs: [(String, [String], String)] = [
            ("Homebrew",  ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"],
                          "curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh | bash"),
            ("git",       ["/usr/bin/git", "/opt/homebrew/bin/git"],
                          "brew install git"),
            ("gh",        ["/opt/homebrew/bin/gh", "/usr/local/bin/gh"],
                          "brew install gh"),
            ("kicad-cli", ["/Applications/KiCad/KiCad.app/Contents/MacOS/kicad-cli",
                           "/opt/homebrew/bin/kicad-cli"],
                          "brew install --cask kicad"),
            ("FreeCAD",   ["/Applications/FreeCAD.app/Contents/MacOS/FreeCAD"],
                          "# download from github.com/FreeCAD/FreeCAD/releases"),
        ]
        statuses = defs.map { name, paths, cmd in
            let found = paths.first { FileManager.default.fileExists(atPath: $0) }
            return DependencyStatus(name: name, installCmd: cmd, path: found)
        }
        isChecking = false
    }

    private func installMissing() {
        let missing = statuses.filter { !$0.found }
        let brewMissing = missing.filter { $0.installCmd.hasPrefix("brew") }
        guard !brewMissing.isEmpty else { return }
        let cmd = brewMissing.map(\.installCmd).joined(separator: " && ")
        openTerminalWith(command: cmd)
    }
}

// MARK: - AppleScript helper (shared)

func openTerminalWith(command: String) {
    let escaped = command.replacingOccurrences(of: "\\", with: "\\\\")
                         .replacingOccurrences(of: "\"", with: "\\\"")
    let script = """
    tell application "Terminal"
        activate
        do script "\(escaped)"
    end tell
    """
    var error: NSDictionary?
    NSAppleScript(source: script)?.executeAndReturnError(&error)
}
