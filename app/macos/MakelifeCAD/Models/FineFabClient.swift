import Foundation

// MARK: - Gateway health

struct GatewayHealth: Decodable {
    let status: String
    let service: String
    let tools: Int
    let yiacadStatus: String

    enum CodingKeys: String, CodingKey {
        case status, service, tools
        case yiacadStatus = "yiacad_status"
    }
}

// MARK: - Tools

struct GatewayTool: Decodable, Identifiable {
    var id: String { name }
    let name: String
    let description: String
    let version: String
    let capabilities: [String]
    let status: String
}

private struct GatewayToolsResponse: Decodable {
    let tools: [GatewayTool]
}

// MARK: - FreeCAD

struct GatewayFreeCADStatusResponse: Decodable, Equatable {
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
}

struct GatewayFreeCADExportResponse: Decodable, Equatable {
    let status: String
    let outputPath: String?
    let returncode: Int?
    let stdout: String?
    let stderr: String?
    let versionUsed: String?
    let source: String?

    enum CodingKeys: String, CodingKey {
        case status, stdout, stderr, source, returncode
        case outputPath = "output_path"
        case versionUsed = "version_used"
    }
}

// MARK: - Component suggest

struct FF_ComponentSuggestion: Decodable, Identifiable {
    var id: String { name + package }
    let name: String
    let manufacturer: String
    let package: String
    let keySpecs: [String: String]
    let reason: String

    enum CodingKeys: String, CodingKey {
        case name, manufacturer, package, reason
        case keySpecs = "key_specs"
    }
}

struct FF_ComponentSuggestResponse: Decodable {
    let suggestions: [FF_ComponentSuggestion]
    let modelUsed: String
    let contextUsed: Bool

    enum CodingKeys: String, CodingKey {
        case suggestions
        case modelUsed = "model_used"
        case contextUsed = "context_used"
    }
}

// MARK: - Schematic review

struct FF_ReviewIssue: Decodable, Identifiable {
    // Stable ID derived from content to avoid SwiftUI instability
    var id: String { "\(severity)-\(category)-\(message.prefix(20))" }
    let severity: String
    let category: String
    let component: String
    let message: String
    let suggestion: String
}

struct FF_SchematicReviewResponse: Decodable {
    let issues: [FF_ReviewIssue]
    let summary: String
    let modelUsed: String
    let componentsAnalyzed: Int
    let netsAnalyzed: Int

    enum CodingKeys: String, CodingKey {
        case issues, summary
        case modelUsed = "model_used"
        case componentsAnalyzed = "components_analyzed"
        case netsAnalyzed = "nets_analyzed"
    }
}

// MARK: - Error

struct GatewayError: LocalizedError {
    let code: Int
    let body: String

    var errorDescription: String? {
        "Gateway error \(code): \(body)"
    }
}

// MARK: - Client

struct FineFabClient {
    let baseURL: String

    private var rootURL: URL {
        let s = baseURL.hasSuffix("/") ? String(baseURL.dropLast()) : baseURL
        return URL(string: s) ?? URL(string: "http://localhost:8001")!
    }

    private func endpoint(_ path: String) -> URL {
        rootURL.appendingPathComponent(path)
    }

    // MARK: Health

    func health() async throws -> GatewayHealth {
        let (data, _) = try await URLSession.shared.data(from: endpoint("health"))
        return try JSONDecoder().decode(GatewayHealth.self, from: data)
    }

    // MARK: Tools

    func tools() async throws -> [GatewayTool] {
        let (data, _) = try await URLSession.shared.data(from: endpoint("tools"))
        return try JSONDecoder().decode(GatewayToolsResponse.self, from: data).tools
    }

    // MARK: FreeCAD

    func freecadStatus() async throws -> GatewayFreeCADStatusResponse {
        let (data, response) = try await URLSession.shared.data(from: endpoint("freecad/status"))
        try checkHTTP(data: data, response: response)
        return try JSONDecoder().decode(GatewayFreeCADStatusResponse.self, from: data)
    }

    func freecadExport(
        inputPath: String,
        format: String,
        outputDir: String? = nil
    ) async throws -> GatewayFreeCADExportResponse {
        var request = URLRequest(url: endpoint("freecad/export"), timeoutInterval: 120)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var body: [String: Any] = [
            "input_path": inputPath,
            "format": format
        ]
        if let outputDir, !outputDir.isEmpty {
            body["output_dir"] = outputDir
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        try checkHTTP(data: data, response: response)
        return try JSONDecoder().decode(GatewayFreeCADExportResponse.self, from: data)
    }

    // MARK: AI — Component suggest

    func suggestComponents(
        description: String,
        constraints: [String: String] = [:]
    ) async throws -> FF_ComponentSuggestResponse {
        var request = URLRequest(url: endpoint("ai/component-suggest"), timeoutInterval: 30)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = ["description": description, "constraints": constraints]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        try checkHTTP(data: data, response: response)
        return try JSONDecoder().decode(FF_ComponentSuggestResponse.self, from: data)
    }

    // MARK: AI — Schematic review (multipart)

    func reviewSchematic(fileContent: String) async throws -> FF_SchematicReviewResponse {
        var request = URLRequest(url: endpoint("ai/schematic-review"), timeoutInterval: 60)
        request.httpMethod = "POST"

        let boundary = "FineFabBoundary-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        let crlf = "\r\n"
        body += "--\(boundary)\(crlf)".utf8data
        body += "Content-Disposition: form-data; name=\"file\"; filename=\"schematic.kicad_sch\"\(crlf)".utf8data
        body += "Content-Type: text/plain\(crlf)\(crlf)".utf8data
        body += fileContent.data(using: .utf8) ?? Data()
        body += "\(crlf)--\(boundary)--\(crlf)".utf8data
        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)
        try checkHTTP(data: data, response: response)
        return try JSONDecoder().decode(FF_SchematicReviewResponse.self, from: data)
    }

    // MARK: Private

    private func checkHTTP(data: Data, response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { return }
        if http.statusCode >= 400 {
            let body = String(data: data, encoding: .utf8) ?? "unknown error"
            throw GatewayError(code: http.statusCode, body: String(body.prefix(300)))
        }
    }
}

// MARK: - Helpers

private extension String {
    var utf8data: Data { data(using: .utf8) ?? Data() }
}

private func += (lhs: inout Data, rhs: Data) { lhs.append(rhs) }
