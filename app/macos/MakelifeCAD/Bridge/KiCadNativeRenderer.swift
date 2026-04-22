import Foundation

/// Renders KiCad schematics and PCBs to SVG using the real KiCad rendering pipeline.
///
/// Uses `kicad-cli` (from an installed KiCad.app or a bundled copy) for
/// pixel-perfect SVG output identical to KiCad's native renderer.
/// Falls back gracefully when kicad-cli is not available.
@MainActor
final class KiCadNativeRenderer: ObservableObject {

    /// Whether a usable kicad-cli was found on this system.
    @Published private(set) var isAvailable: Bool = false

    /// The detected kicad-cli version (e.g. "10.0.0").
    @Published private(set) var kicadVersion: String = ""

    /// Last error message, if any.
    @Published private(set) var lastError: String?

    /// Path to the resolved kicad-cli binary.
    private var cliPath: String?

    /// Temporary directory for SVG output.
    private let tempDir: URL

    // MARK: - Initialization

    init() {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("makelife-svg", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDir,
                                                  withIntermediateDirectories: true)
        resolveKiCadCLI()
    }

    // MARK: - CLI Resolution

    /// Search for kicad-cli in known locations.
    private func resolveKiCadCLI() {
        let candidates = [
            // 1. Environment variable override
            ProcessInfo.processInfo.environment["KICAD_CLI"],
            // 2. Bundled in our app
            Bundle.main.path(forAuxiliaryExecutable: "kicad-cli"),
            // 3. Standard KiCad.app install
            "/Applications/KiCad/KiCad.app/Contents/MacOS/kicad-cli",
            // 4. Homebrew
            "/opt/homebrew/bin/kicad-cli",
            // 5. MacPorts
            "/opt/local/bin/kicad-cli",
        ]

        for candidate in candidates {
            guard let path = candidate, !path.isEmpty else { continue }
            if FileManager.default.isExecutableFile(atPath: path) {
                if let version = queryVersion(path: path) {
                    cliPath = path
                    kicadVersion = version
                    isAvailable = true
                    return
                }
            }
        }

        isAvailable = false
    }

    /// Query the kicad-cli version string.
    /// kicad-cli may crash during cleanup (known issue) so we accept any exit
    /// code as long as we got version output.
    private func queryVersion(path: String) -> String? {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: path)
        proc.arguments = ["version"]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = FileHandle.nullDevice

        do {
            try proc.run()
            proc.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

            // Accept any output that looks like a version number
            if !output.isEmpty, output.first?.isNumber == true {
                return output
            }

            // Fallback: if the binary exists and is a valid KiCad CLI,
            // infer the version from the KiCad.app bundle
            if path.contains("KiCad.app") {
                return inferVersionFromBundle(cliPath: path)
            }

            return nil
        } catch {
            // Can't run the process — still check if it looks valid
            if path.contains("KiCad.app") {
                return inferVersionFromBundle(cliPath: path)
            }
            return nil
        }
    }

    /// Infer KiCad version from the app bundle's Info.plist.
    private func inferVersionFromBundle(cliPath: String) -> String? {
        // Walk up from .../Contents/MacOS/kicad-cli to the .app bundle
        let url = URL(fileURLWithPath: cliPath)
        var bundleURL = url.deletingLastPathComponent() // MacOS/
            .deletingLastPathComponent() // Contents/
            .deletingLastPathComponent() // KiCad.app
        if bundleURL.pathExtension != "app" {
            // Try parent (e.g. if it's inside KiCad.app/Contents/MacOS/)
            bundleURL = url
            while bundleURL.pathExtension != "app" && bundleURL.path != "/" {
                bundleURL = bundleURL.deletingLastPathComponent()
            }
        }
        guard let bundle = Bundle(url: bundleURL) else { return nil }
        return bundle.infoDictionary?["CFBundleShortVersionString"] as? String
    }

    // MARK: - Schematic SVG Export

    /// Export a schematic to SVG using KiCad's native renderer.
    ///
    /// - Parameters:
    ///   - schematicPath: Absolute path to the `.kicad_sch` file.
    ///   - theme: Optional color theme name (default: KiCad's default).
    ///   - noBackground: If true, renders without background color.
    ///   - pages: Specific pages to export (nil = all pages).
    /// - Returns: Array of SVG file URLs (one per sheet), or empty on failure.
    func exportSchematicSVG(
        schematicPath: String,
        theme: String? = nil,
        noBackground: Bool = false,
        pages: String? = nil
    ) async -> [URL] {
        guard let cli = cliPath else {
            lastError = "kicad-cli not found"
            return []
        }

        // Create a unique output directory for this export
        let exportId = UUID().uuidString.prefix(8)
        let outputDir = tempDir.appendingPathComponent("sch-\(exportId)",
                                                       isDirectory: true)
        try? FileManager.default.createDirectory(at: outputDir,
                                                  withIntermediateDirectories: true)

        var args = ["sch", "export", "svg",
                    "--output", outputDir.path]

        if let theme = theme {
            args += ["--theme", theme]
        }
        if noBackground {
            args.append("--no-background-color")
        }
        if let pages = pages {
            args += ["--pages", pages]
        }

        args.append(schematicPath)

        let result = await runCLI(path: cli, arguments: args)

        if !result.success {
            lastError = result.stderr.isEmpty ? "SVG export failed" : result.stderr
            return []
        }

        lastError = nil

        // Collect generated SVG files
        do {
            let contents = try FileManager.default.contentsOfDirectory(
                at: outputDir, includingPropertiesForKeys: nil)
            return contents
                .filter { $0.pathExtension == "svg" }
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
        } catch {
            lastError = error.localizedDescription
            return []
        }
    }

    /// Export a schematic to a single SVG string (first page).
    /// Convenience method for the common case.
    func exportSchematicSVGString(schematicPath: String) async -> String? {
        let urls = await exportSchematicSVG(schematicPath: schematicPath)
        guard let firstURL = urls.first else { return nil }
        return try? String(contentsOf: firstURL, encoding: .utf8)
    }

    // MARK: - PCB SVG Export

    /// Export a PCB to SVG using KiCad's native renderer.
    func exportPCBSVG(
        pcbPath: String,
        layers: [String]? = nil,
        theme: String? = nil
    ) async -> [URL] {
        guard let cli = cliPath else {
            lastError = "kicad-cli not found"
            return []
        }

        let exportId = UUID().uuidString.prefix(8)
        let outputDir = tempDir.appendingPathComponent("pcb-\(exportId)",
                                                       isDirectory: true)
        try? FileManager.default.createDirectory(at: outputDir,
                                                  withIntermediateDirectories: true)

        var args = ["pcb", "export", "svg",
                    "--output", outputDir.path(percentEncoded: false)]

        if let layers = layers {
            args += ["--layers", layers.joined(separator: ",")]
        }
        if let theme = theme {
            args += ["--theme", theme]
        }

        args.append(pcbPath)

        let result = await runCLI(path: cli, arguments: args)

        if !result.success {
            lastError = result.stderr.isEmpty ? "PCB SVG export failed" : result.stderr
            return []
        }

        lastError = nil

        do {
            let contents = try FileManager.default.contentsOfDirectory(
                at: outputDir, includingPropertiesForKeys: nil)
            return contents.filter { $0.pathExtension == "svg" }
        } catch {
            lastError = error.localizedDescription
            return []
        }
    }

    // MARK: - Cleanup

    /// Remove all cached SVG exports.
    func cleanupCache() {
        try? FileManager.default.removeItem(at: tempDir)
        try? FileManager.default.createDirectory(at: tempDir,
                                                  withIntermediateDirectories: true)
    }

    // MARK: - Private helpers

    private struct CLIResult {
        let success: Bool
        let stdout: String
        let stderr: String
    }

    private func runCLI(path: String, arguments: [String]) async -> CLIResult {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let proc = Process()
                proc.executableURL = URL(fileURLWithPath: path)
                proc.arguments = arguments

                // Clean environment: remove Xcode dylib injection and other
                // debug variables that could interfere with kicad-cli.
                var env = ProcessInfo.processInfo.environment
                env.removeValue(forKey: "DYLD_INSERT_LIBRARIES")
                env.removeValue(forKey: "DYLD_LIBRARY_PATH")
                env.removeValue(forKey: "DYLD_FRAMEWORK_PATH")
                proc.environment = env

                let stdoutPipe = Pipe()
                let stderrPipe = Pipe()
                proc.standardOutput = stdoutPipe
                proc.standardError = stderrPipe

                do {
                    try proc.run()
                    proc.waitUntilExit()

                    let outData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                    let errData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

                    let result = CLIResult(
                        success: proc.terminationStatus == 0,
                        stdout: String(data: outData, encoding: .utf8) ?? "",
                        stderr: String(data: errData, encoding: .utf8) ?? ""
                    )
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(returning: CLIResult(
                        success: false, stdout: "", stderr: error.localizedDescription))
                }
            }
        }
    }
}
