import AppKit
import Foundation

enum FreeCADExportFormat: String, CaseIterable, Identifiable {
    case step
    case stl

    var id: String { rawValue }

    var label: String { rawValue.uppercased() }
}

enum FreeCADExecutionMode: String, Equatable {
    case local
    case gateway
    case unavailable
}

struct FreeCADRuntimeStatus: Decodable, Equatable {
    let status: String
    let installed: Bool
    let version: String?
    let compatible: Bool
    let path: String?
    let source: String
    let preferredExportMode: String

    enum CodingKeys: String, CodingKey {
        case status, installed, version, compatible, path, source
        case preferredExportMode = "preferred_export_mode"
    }

    var isExpectedVersion: Bool { version == FreeCADRuntimeResolver.targetVersion }
    var warningText: String? {
        guard installed else { return "FreeCAD 1.1.0 is not installed locally." }
        guard compatible else {
            return "FreeCAD \(version ?? "unknown") is incompatible. Expected 1.1.x."
        }
        guard !isExpectedVersion, let version else { return nil }
        return "FreeCAD \(version) is supported, but 1.1.0 is the target runtime for YiACAD."
    }

    static let unavailable = FreeCADRuntimeStatus(
        status: "unavailable",
        installed: false,
        version: nil,
        compatible: false,
        path: nil,
        source: "unavailable",
        preferredExportMode: "unavailable"
    )
}

struct FreeCADExportJob: Identifiable, Equatable {
    enum State: String, Equatable {
        case running
        case succeeded
        case failed
    }

    let id = UUID()
    let document: FreeCADDocumentRef
    let format: FreeCADExportFormat
    let mode: FreeCADExecutionMode
    var state: State
    var outputPath: String?
    var versionUsed: String?
    var source: String?
    var stdout: String?
    var stderr: String?
    var errorMessage: String?
    let startedAt: Date
    var finishedAt: Date?
}

enum FreeCADRuntimeResolver {
    static let targetVersion = "1.1.0"
    static let supportedPrefix = "1.1."
    static let appBundleCandidates = [
        "/Applications/FreeCAD.app/Contents/MacOS/FreeCADCmd",
        "/Applications/FreeCAD 1.1.app/Contents/MacOS/FreeCADCmd"
    ]

    static func parseVersion(from raw: String) -> String? {
        guard let match = raw.range(of: #"\d+\.\d+\.\d+"#, options: .regularExpression) else {
            return nil
        }
        return String(raw[match])
    }

    static func isCompatible(version: String?) -> Bool {
        guard let version else { return false }
        return version.hasPrefix(supportedPrefix)
    }

    static func isLocalGateway(_ baseURL: String) -> Bool {
        guard let url = URL(string: baseURL),
              let host = url.host?.lowercased() else {
            return false
        }
        return host == "localhost" || host == "127.0.0.1" || host == "::1"
    }
}

enum FreeCADExportPlanner {
    static func shouldProbeGateway(
        projectAvailable: Bool,
        gatewayBaseURL: String,
        force: Bool = false
    ) -> Bool {
        guard FreeCADRuntimeResolver.isLocalGateway(gatewayBaseURL) else { return false }
        return force || projectAvailable
    }

    static func chooseMode(
        localStatus: FreeCADRuntimeStatus,
        gatewayBaseURL: String,
        gatewayStatus: FreeCADRuntimeStatus?
    ) -> FreeCADExecutionMode {
        guard localStatus.compatible else { return .unavailable }
        if FreeCADRuntimeResolver.isLocalGateway(gatewayBaseURL),
           gatewayStatus?.compatible == true {
            return .gateway
        }
        return .local
    }
}

private struct FreeCADCommandResult {
    let exitCode: Int32
    let stdout: String
    let stderr: String
}

@MainActor
final class FreeCADViewModel: ObservableObject {
    @Published private(set) var localStatus: FreeCADRuntimeStatus = .unavailable
    @Published private(set) var gatewayStatus: FreeCADRuntimeStatus?
    @Published private(set) var documents: [FreeCADDocumentRef] = []
    @Published var selectedDocument: FreeCADDocumentRef?
    @Published private(set) var lastExportJob: FreeCADExportJob?
    @Published private(set) var logs: [String] = []
    @Published private(set) var isRefreshing = false
    @Published private(set) var isExporting = false

    // gatewayBaseURL is kept in sync by App.swift via .onChange(of: fineFabVM.baseURL).
    // FineFabViewModel is the single owner of the "finefab.gateway.url" UserDefaults key.
    @Published var gatewayBaseURL: String {
        didSet { client = FineFabClient(baseURL: gatewayBaseURL) }
    }

    private var client: FineFabClient
    private var currentProject: YiacadProject?

    init() {
        let savedURL = UserDefaults.standard.string(forKey: "finefab.gateway.url")
            ?? "http://localhost:8001"
        self.gatewayBaseURL = savedURL
        self.client = FineFabClient(baseURL: savedURL)
    }

    func attach(project: YiacadProject?) {
        currentProject = project
        documents = project?.freecadDocuments ?? []
        // Clear stale results on every project change, not only when closing.
        gatewayStatus = nil
        lastExportJob = nil
        if let selectedDocument, documents.contains(selectedDocument) {
            self.selectedDocument = selectedDocument
        } else {
            self.selectedDocument = documents.first
        }
    }

    func refreshAll(forceGatewayProbe: Bool = false) async {
        isRefreshing = true
        defer { isRefreshing = false }

        refreshDocuments()
        localStatus = await detectLocalRuntimeStatus()
        if FreeCADExportPlanner.shouldProbeGateway(
            projectAvailable: currentProject != nil,
            gatewayBaseURL: gatewayBaseURL,
            force: forceGatewayProbe
        ) {
            gatewayStatus = await detectGatewayRuntimeStatus()
        } else {
            gatewayStatus = nil
        }
    }

    func refreshDocuments() {
        guard let projectURL = currentProject?.url,
              let refreshedProject = YiacadProject(url: projectURL) else {
            documents = []
            selectedDocument = nil
            return
        }

        currentProject = refreshedProject
        documents = refreshedProject.freecadDocuments
        if let selectedDocument, documents.contains(selectedDocument) {
            self.selectedDocument = selectedDocument
        } else {
            self.selectedDocument = documents.first
        }
    }

    func openSelectedInFreeCAD() {
        guard let selectedDocument else { return }
        appendLog("Opening \(selectedDocument.relativePath) in FreeCAD.")
        do {
            try runDetachedOpen(arguments: ["-a", "FreeCAD", selectedDocument.url.path])
        } catch {
            appendLog("Open failed: \(error.localizedDescription)")
        }
    }

    func revealSelectedInFinder() {
        guard let selectedDocument else { return }
        NSWorkspace.shared.activateFileViewerSelecting([selectedDocument.url])
    }

    func exportSelected(format: FreeCADExportFormat) async {
        guard let selectedDocument else { return }

        let mode = FreeCADExportPlanner.chooseMode(
            localStatus: localStatus,
            gatewayBaseURL: gatewayBaseURL,
            gatewayStatus: gatewayStatus
        )
        guard mode != .unavailable else {
            appendLog("Export blocked: no compatible FreeCAD 1.1.x runtime.")
            lastExportJob = FreeCADExportJob(
                document: selectedDocument,
                format: format,
                mode: .unavailable,
                state: .failed,
                outputPath: nil,
                versionUsed: localStatus.version,
                source: localStatus.source,
                stdout: nil,
                stderr: nil,
                errorMessage: localStatus.warningText,
                startedAt: Date(),
                finishedAt: Date()
            )
            return
        }

        isExporting = true
        var job = FreeCADExportJob(
            document: selectedDocument,
            format: format,
            mode: mode,
            state: .running,
            outputPath: nil,
            versionUsed: nil,
            source: nil,
            stdout: nil,
            stderr: nil,
            errorMessage: nil,
            startedAt: Date(),
            finishedAt: nil
        )
        lastExportJob = job
        appendLog("Starting \(format.label) export for \(selectedDocument.relativePath) via \(mode.rawValue).")

        do {
            switch mode {
            case .gateway:
                let response = try await exportViaGateway(document: selectedDocument, format: format)
                job.state = response.status == "ok" ? .succeeded : .failed
                job.outputPath = response.outputPath
                job.versionUsed = response.versionUsed
                job.source = response.source
                job.stdout = response.stdout
                job.stderr = response.stderr
                job.errorMessage = response.status == "ok" ? nil : (response.stderr ?? "Gateway export failed")
            case .local:
                let result = try await exportLocally(document: selectedDocument, format: format)
                job.state = result.exitCode == 0 ? .succeeded : .failed
                job.outputPath = result.outputPath
                job.versionUsed = localStatus.version
                job.source = localStatus.source
                job.stdout = result.stdout
                job.stderr = result.stderr
                job.errorMessage = result.exitCode == 0 ? nil : result.stderr
            case .unavailable:
                break
            }
        } catch {
            job.state = .failed
            job.errorMessage = error.localizedDescription
            appendLog("Export failed: \(error.localizedDescription)")
        }

        job.finishedAt = Date()
        if let outputPath = job.outputPath {
            appendLog("Export finished: \(outputPath)")
        } else if let errorMessage = job.errorMessage {
            appendLog("Export error: \(errorMessage)")
        }

        lastExportJob = job
        isExporting = false
    }

    private func detectGatewayRuntimeStatus() async -> FreeCADRuntimeStatus? {
        guard FreeCADRuntimeResolver.isLocalGateway(gatewayBaseURL) else {
            return nil
        }

        do {
            let status = try await client.freecadStatus()
            return FreeCADRuntimeStatus(
                status: status.status,
                installed: status.installed,
                version: status.version,
                compatible: status.compatible,
                path: status.path,
                source: status.source,
                preferredExportMode: status.preferredExportMode
            )
        } catch {
            return FreeCADRuntimeStatus(
                status: "offline",
                installed: false,
                version: nil,
                compatible: false,
                path: nil,
                source: "gateway",
                preferredExportMode: "local"
            )
        }
    }

    private func detectLocalRuntimeStatus() async -> FreeCADRuntimeStatus {
        let environment = ProcessInfo.processInfo.environment
        let candidates = ([environment["FREECAD_CMD"]].compactMap { $0 } +
            FreeCADRuntimeResolver.appBundleCandidates +
            ["FreeCADCmd", "freecadcmd"])

        for candidate in candidates {
            guard let resolved = await resolveExecutable(candidate) else { continue }
            let source: String = environment["FREECAD_CMD"] == candidate
                ? "env"
                : (candidate.hasPrefix("/Applications/") ? "app_bundle" : "path")

            do {
                let result = try await runPythonScript(
                    executable: resolved,
                    script: """
                    import FreeCAD
                    version = FreeCAD.Version()
                    print(".".join(str(part) for part in version[:3]))
                    """,
                    arguments: []
                )
                let version = FreeCADRuntimeResolver.parseVersion(
                    from: "\(result.stdout)\n\(result.stderr)"
                )
                return FreeCADRuntimeStatus(
                    status: FreeCADRuntimeResolver.isCompatible(version: version) ? "available" : "incompatible",
                    installed: true,
                    version: version,
                    compatible: FreeCADRuntimeResolver.isCompatible(version: version),
                    path: resolved,
                    source: source,
                    preferredExportMode: "local"
                )
            } catch {
                return FreeCADRuntimeStatus(
                    status: "unavailable",
                    installed: true,
                    version: nil,
                    compatible: false,
                    path: resolved,
                    source: source,
                    preferredExportMode: "unavailable"
                )
            }
        }

        return .unavailable
    }

    private func resolveExecutable(_ candidate: String) async -> String? {
        if candidate.contains("/") {
            return FileManager.default.isExecutableFile(atPath: candidate) ? candidate : nil
        }

        do {
            let result = try await runCommand(executable: "/usr/bin/which", arguments: [candidate])
            let resolved = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            return resolved.isEmpty ? nil : resolved
        } catch {
            return nil
        }
    }

    private func exportViaGateway(
        document: FreeCADDocumentRef,
        format: FreeCADExportFormat
    ) async throws -> GatewayFreeCADExportResponse {
        let outputDir = try exportDirectory()
        return try await client.freecadExport(
            inputPath: document.url.path,
            format: format.rawValue,
            outputDir: outputDir.path
        )
    }

    private func exportLocally(
        document: FreeCADDocumentRef,
        format: FreeCADExportFormat
    ) async throws -> (exitCode: Int32, outputPath: String?, stdout: String, stderr: String) {
        guard let executable = localStatus.path else {
            throw NSError(domain: "FreeCADViewModel", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "FreeCAD command path is unavailable."
            ])
        }

        let outputDir = try exportDirectory()
        let outputPath = outputDir.appendingPathComponent("\(document.name).\(format.rawValue)")
        let result = try await runPythonScript(
            executable: executable,
            script: """
            import FreeCAD, Part, Mesh, sys
            input_path, output_path, fmt = sys.argv[1], sys.argv[2], sys.argv[3]
            doc = FreeCAD.openDocument(input_path)
            objs = [obj for obj in doc.Objects if hasattr(obj, 'Shape') or hasattr(obj, 'Mesh')]
            if not objs:
                raise RuntimeError("No exportable objects found in document")
            if fmt.lower() == "stl":
                Mesh.export(objs, output_path)
            else:
                Part.export(objs, output_path)
            doc.close()
            print(output_path)
            """,
            arguments: [document.url.path, outputPath.path, format.rawValue]
        )
        return (result.exitCode, result.exitCode == 0 ? outputPath.path : nil, result.stdout, result.stderr)
    }

    private func exportDirectory() throws -> URL {
        guard let project = currentProject else {
            throw NSError(domain: "FreeCADViewModel", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "Open a YiACAD project before exporting."
            ])
        }

        let outputDir = project.mechanicalRootURL.appendingPathComponent("exports", isDirectory: true)
        try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
        return outputDir
    }

    private func runPythonScript(
        executable: String,
        script: String,
        arguments: [String]
    ) async throws -> FreeCADCommandResult {
        let scriptURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("makelife-freecad-\(UUID().uuidString).py")
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: scriptURL) }

        return try await runCommand(executable: executable, arguments: ["-c", scriptURL.path] + arguments)
    }

    private func runCommand(
        executable: String,
        arguments: [String]
    ) async throws -> FreeCADCommandResult {
        // Use a DispatchQueue + continuation instead of Task.detached so that
        // process.waitUntilExit() blocks a GCD thread, not the Swift cooperative pool.
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let process = Process()
                    process.executableURL = URL(fileURLWithPath: executable)
                    process.arguments = arguments

                    let stdoutPipe = Pipe()
                    let stderrPipe = Pipe()
                    process.standardOutput = stdoutPipe
                    process.standardError = stderrPipe

                    try process.run()
                    process.waitUntilExit()

                    let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                    let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                    continuation.resume(returning: FreeCADCommandResult(
                        exitCode: process.terminationStatus,
                        stdout: String(data: stdoutData, encoding: .utf8) ?? "",
                        stderr: String(data: stderrData, encoding: .utf8) ?? ""
                    ))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func runDetachedOpen(arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = arguments
        try process.run()
    }

    private func appendLog(_ line: String) {
        logs.append("[\(timestamp())] \(line)")
    }

    private func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: Date())
    }
}
