import SwiftUI
import AppKit

// MARK: - Clone from GitHub sheet

struct CloneRepoView: View {
    /// Pre-filled repo slug or URL (optional).
    var prefilledRepo: String = ""
    /// Called with the `.kicad_pro` URL when the user selects a project.
    var onOpen: (URL) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var repoInput      = ""
    @State private var destPath       = ""
    @State private var cloneLog       = ""
    @State private var isCloning      = false
    @State private var cloneOK        = false
    @State private var foundProjects: [URL] = []
    @State private var errorMsg: String?

    // MARK: - Computed helpers

    private var normalizedURL: String {
        let s = repoInput.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.isEmpty || s.hasPrefix("http") || s.hasPrefix("git@") { return s }
        return "https://github.com/\(s)"
    }

    private var repoName: String {
        let parts = normalizedURL.split(separator: "/")
        var n = parts.last.map(String.init) ?? "repo"
        if n.hasSuffix(".git") { n = String(n.dropLast(4)) }
        return n
    }

    private var destRoot: URL {
        destPath.isEmpty
            ? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            : URL(fileURLWithPath: destPath)
    }

    private var defaultDestPlaceholder: String {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?.path ?? "~/Documents"
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            panelHeader
            Divider()
            Group {
                if cloneOK { projectSelectSection }
                else        { inputSection }
            }
            .padding(20)
        }
        .frame(width: 520, height: 420)
        .onAppear { if !prefilledRepo.isEmpty { repoInput = prefilledRepo } }
    }

    // MARK: - Header

    private var panelHeader: some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.down.to.line.compact")
                .font(.title2)
                .foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 2) {
                Text("Open from GitHub")
                    .font(.title3.bold())
                Text(cloneOK
                     ? "Select a KiCad project to open"
                     : "Clone a repository, then open its KiCad project")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(20)
        .background(.ultraThinMaterial)
    }

    // MARK: - Input section

    private var inputSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Repo field
            VStack(alignment: .leading, spacing: 5) {
                Label("Repository", systemImage: "network")
                    .font(.caption.bold()).foregroundStyle(.secondary)
                TextField("owner/repo  or  https://github.com/owner/repo",
                          text: $repoInput)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                    .disabled(isCloning)
            }

            // Destination field
            VStack(alignment: .leading, spacing: 5) {
                Label("Clone into", systemImage: "folder")
                    .font(.caption.bold()).foregroundStyle(.secondary)
                HStack {
                    TextField(defaultDestPlaceholder, text: $destPath)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                        .disabled(isCloning)
                    Button("…") { pickDestination() }
                        .disabled(isCloning)
                }
                if !repoInput.isEmpty {
                    Text("→ \(destRoot.path)/\(repoName)")
                        .font(.caption).foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }

            // Error banner
            if let err = errorMsg {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                    Text(err).font(.caption)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.red.opacity(0.07))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            // Clone log (shown after failure)
            if !cloneLog.isEmpty && !cloneOK {
                ScrollView {
                    Text(cloneLog)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .textSelection(.enabled)
                }
                .frame(height: 90)
                .background(Color(.windowBackgroundColor).opacity(0.6))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            Spacer()

            // Buttons
            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .disabled(isCloning)
                Spacer()
                Button {
                    Task { await performClone() }
                } label: {
                    if isCloning {
                        HStack(spacing: 6) {
                            ProgressView().scaleEffect(0.7)
                            Text("Cloning…")
                        }
                    } else {
                        Label("Clone", systemImage: "arrow.down.circle")
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(repoInput.trimmingCharacters(in: .whitespaces).isEmpty || isCloning)
                .buttonStyle(.borderedProminent)
            }
        }
    }

    // MARK: - Project select section

    private var projectSelectSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Cloned '\(repoName)' successfully",
                  systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green).font(.callout)

            if foundProjects.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "questionmark.folder")
                        .font(.system(size: 40)).foregroundStyle(.tertiary)
                    Text("No .kicad_pro found in the repository")
                        .foregroundStyle(.secondary)
                    Text("The repo was cloned to \(destRoot.appendingPathComponent(repoName).path).\nOpen it manually from the Project panel.")
                        .font(.caption).foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
            } else {
                Text("Found \(foundProjects.count) KiCad project\(foundProjects.count > 1 ? "s" : "") — tap one to open:")
                    .font(.caption).foregroundStyle(.secondary)

                ForEach(foundProjects, id: \.path) { url in
                    Button {
                        onOpen(url)
                        dismiss()
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "folder.fill")
                                .foregroundStyle(Color.accentColor).font(.title3)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(url.deletingPathExtension().lastPathComponent)
                                    .font(.callout.bold())
                                Text(url.path)
                                    .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Spacer()
                            Image(systemName: "arrow.right.circle.fill")
                                .foregroundStyle(Color.accentColor)
                        }
                        .padding(12)
                        .background(Color(.controlBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                }
            }

            Spacer()

            HStack {
                Button("Close") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
            }
        }
    }

    // MARK: - Folder picker

    private func pickDestination() {
        let panel = NSOpenPanel()
        panel.canChooseFiles        = false
        panel.canChooseDirectories  = true
        panel.canCreateDirectories  = true
        panel.prompt  = "Clone Here"
        panel.message = "Select the folder where the repository will be cloned"
        if panel.runModal() == .OK, let url = panel.url {
            destPath = url.path
        }
    }

    // MARK: - Clone logic

    private func performClone() async {
        errorMsg = nil
        cloneLog = ""
        isCloning = true

        let result = await runGitClone(repoURL: normalizedURL, into: destRoot)
        cloneLog  = result.output
        isCloning = false

        if result.ok {
            foundProjects = scanForProjects(in: destRoot.appendingPathComponent(repoName))
            cloneOK = true
        } else {
            errorMsg = "Clone failed — check the URL and your network connection."
        }
    }

    private struct CloneResult { let ok: Bool; let output: String }

    private func runGitClone(repoURL: String, into dest: URL) async -> CloneResult {
        await withCheckedContinuation { cont in
            Task.detached {
                let p = Process()
                p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
                p.arguments     = ["git", "clone", "--progress", repoURL]
                p.currentDirectoryURL = dest

                var env = ProcessInfo.processInfo.environment
                env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:" + (env["PATH"] ?? "")
                p.environment = env

                let outPipe = Pipe(); let errPipe = Pipe()
                p.standardOutput = outPipe
                p.standardError  = errPipe

                do {
                    try p.run()
                    p.waitUntilExit()
                } catch {
                    cont.resume(returning: CloneResult(ok: false, output: error.localizedDescription))
                    return
                }

                let out = String(data: outPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                let err = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                cont.resume(returning: CloneResult(
                    ok: p.terminationStatus == 0,
                    output: (err + out).trimmingCharacters(in: .whitespacesAndNewlines)
                ))
            }
        }
    }

    private func scanForProjects(in dir: URL) -> [URL] {
        let fm = FileManager.default
        guard let iter = fm.enumerator(at: dir,
                                       includingPropertiesForKeys: nil,
                                       options: [.skipsHiddenFiles]) else { return [] }
        var found: [URL] = []
        for case let url as URL in iter {
            if url.pathExtension == "kicad_pro" { found.append(url) }
        }
        return found.sorted { $0.path < $1.path }
    }
}
