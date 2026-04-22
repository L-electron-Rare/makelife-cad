import Foundation
import AppKit

// MARK: - Plugin descriptor

struct MakelifePlugin: Identifiable, Hashable {
    let id: URL
    let name: String
    let description: String
    let fileExtension: String

    /// File URL of the script.
    var url: URL { id }

    var icon: String {
        switch fileExtension {
        case "py":    return "chevron.left.forwardslash.chevron.right"
        case "swift": return "swift"
        default:      return "doc.text"
        }
    }
}

// MARK: - PluginManager

/// Discovers and runs user plugins from `~/.makelife/plugins/`.
@MainActor
final class PluginManager: ObservableObject {

    static let pluginsDir: URL = FileManager.default
        .homeDirectoryForCurrentUser
        .appendingPathComponent(".makelife/plugins")

    @Published private(set) var plugins: [MakelifePlugin] = []
    @Published private(set) var isRunning = false
    @Published private(set) var lastOutput = ""
    @Published private(set) var lastExitCode: Int32?

    // MARK: - Discovery

    func refresh() {
        let dir = Self.pluginsDir
        guard FileManager.default.fileExists(atPath: dir.path) else {
            plugins = []
            return
        }
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil
        ) else {
            plugins = []
            return
        }

        let supported = Set(["py", "swift", "sh"])
        plugins = contents
            .filter { supported.contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .map { url in
                let (name, desc) = Self.parseHeader(url)
                return MakelifePlugin(
                    id: url,
                    name: name,
                    description: desc,
                    fileExtension: url.pathExtension.lowercased()
                )
            }
    }

    // MARK: - Execution

    /// Runs a plugin script, injecting project context via environment variables.
    func run(
        plugin: MakelifePlugin,
        projectRoot: URL? = nil,
        schematicPath: String? = nil,
        pcbPath: String? = nil,
        componentsJSON: String? = nil
    ) {
        guard !isRunning else { return }
        isRunning = true
        lastOutput = ""
        lastExitCode = nil

        let scriptURL = plugin.url

        // Determine interpreter
        let executable: String
        let args: [String]
        switch plugin.fileExtension {
        case "py":
            executable = "/usr/bin/env"
            args = ["python3", scriptURL.path]
        case "swift":
            executable = "/usr/bin/env"
            args = ["swift", scriptURL.path]
        case "sh":
            executable = "/bin/sh"
            args = [scriptURL.path]
        default:
            lastOutput = "Unsupported script type: .\(plugin.fileExtension)"
            lastExitCode = -1
            isRunning = false
            return
        }

        // Build environment
        var env = ProcessInfo.processInfo.environment
        if let root = projectRoot?.path { env["MAKELIFE_PROJECT_ROOT"] = root }
        if let sch = schematicPath { env["MAKELIFE_SCHEMATIC_PATH"] = sch }
        if let pcb = pcbPath { env["MAKELIFE_PCB_PATH"] = pcb }
        if let json = componentsJSON { env["MAKELIFE_COMPONENTS_JSON"] = json }

        Task.detached { [weak self] in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = args
            process.environment = env
            if let root = projectRoot {
                process.currentDirectoryURL = root
            }

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe

            let result: (output: String, code: Int32)
            do {
                try process.run()
                process.waitUntilExit()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let out = String(data: data, encoding: .utf8) ?? ""
                result = (out, process.terminationStatus)
            } catch {
                result = ("Failed to launch: \(error.localizedDescription)", -1)
            }

            await MainActor.run { [weak self] in
                self?.lastOutput = result.output
                self?.lastExitCode = result.code
                self?.isRunning = false
            }
        }
    }

    /// Creates the plugins directory if it doesn't exist.
    func ensurePluginsDir() {
        let dir = Self.pluginsDir
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }

    /// Opens the plugins directory in Finder.
    func revealInFinder() {
        ensurePluginsDir()
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: Self.pluginsDir.path)
    }

    // MARK: - Header parsing

    /// Reads the first 10 lines of a script looking for a name/description comment.
    /// Convention:
    /// ```
    /// # Plugin: My Plugin Name
    /// # Description: Does something useful
    /// ```
    private static func parseHeader(_ url: URL) -> (name: String, description: String) {
        let fallbackName = url.deletingPathExtension().lastPathComponent
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .capitalized

        guard let content = try? String(contentsOf: url, encoding: .utf8) else {
            return (fallbackName, "")
        }

        let lines = content.components(separatedBy: .newlines).prefix(15)
        var name = fallbackName
        var desc = ""

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            // Python/Shell: # Plugin: ...
            // Swift: // Plugin: ...
            let stripped: String
            if trimmed.hasPrefix("//") {
                stripped = String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
            } else if trimmed.hasPrefix("#") && !trimmed.hasPrefix("#!") {
                stripped = String(trimmed.dropFirst(1)).trimmingCharacters(in: .whitespaces)
            } else {
                continue
            }

            if stripped.lowercased().hasPrefix("plugin:") {
                name = String(stripped.dropFirst(7)).trimmingCharacters(in: .whitespaces)
            } else if stripped.lowercased().hasPrefix("description:") {
                desc = String(stripped.dropFirst(12)).trimmingCharacters(in: .whitespaces)
            }
        }

        return (name, desc)
    }
}
