import Foundation

// MARK: - Provider

enum AIProvider: String, CaseIterable, Identifiable {
    case onDevice = "On-device"
    case gateway  = "Factory AI"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .onDevice: return "sparkles"
        case .gateway:  return "bolt.fill"
        }
    }

    var subtitle: String {
        switch self {
        case .onDevice: return "Apple Intelligence · Private"
        case .gateway:  return "mascarade-kicad · GPU"
        }
    }
}

// MARK: - FineFab modes

enum FineFabMode: String, CaseIterable, Identifiable {
    case status  = "Gateway Status"
    case suggest = "Component Suggest"
    case review  = "Schematic Review"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .status:  return "network"
        case .suggest: return "sparkles"
        case .review:  return "checkmark.seal"
        }
    }

    var placeholder: String {
        switch self {
        case .status:  return ""
        case .suggest: return "Describe the component you need (e.g. 3.3 V LDO 500 mA SOT-23)…"
        case .review:  return "Paste schematic context or open a project for file upload…"
        }
    }
}

// MARK: - ViewModel

@MainActor
final class FineFabViewModel: ObservableObject {

    enum State {
        case idle
        case loading
        case done
        case error(String)
    }

    // Gateway URL — persisted in UserDefaults
    @Published var baseURL: String {
        didSet {
            UserDefaults.standard.set(baseURL, forKey: "finefab.gateway.url")
            client = FineFabClient(baseURL: baseURL)
        }
    }

    @Published var mode: FineFabMode = .status
    @Published var prompt: String = ""

    @Published private(set) var state: State = .idle
    @Published private(set) var health: GatewayHealth?
    @Published private(set) var tools: [GatewayTool] = []
    @Published private(set) var responseText: String = ""
    @Published private(set) var isConnected: Bool = false

    /// Set by App.swift when a project is loaded — used for schematic review
    var schematicURL: URL?

    /// Set by ContentView when a schematic is loaded — injected as context in suggest requests
    var schematicContext: String? = nil

    private var client: FineFabClient
    private var activeTask: Task<Void, Never>?

    init() {
        let saved = UserDefaults.standard.string(forKey: "finefab.gateway.url")
            ?? "http://localhost:8001"
        self.baseURL = saved
        self.client = FineFabClient(baseURL: saved)
    }

    // MARK: - Public

    func submit() {
        activeTask?.cancel()
        activeTask = Task { await run() }
    }

    func reset() {
        activeTask?.cancel()
        activeTask = nil
        state = .idle
        responseText = ""
        prompt = ""
    }

    func checkStatus() async {
        state = .loading
        do {
            async let h = client.health()
            async let t = client.tools()
            health = try await h
            tools = (try? await t) ?? []
            isConnected = health?.status == "ok"
            responseText = format(health: health!, tools: tools)
            state = .done
        } catch {
            isConnected = false
            health = nil
            state = .error(
                "Gateway unreachable at \(baseURL)\n\n" +
                "Start the gateway:\n" +
                "uvicorn gateway.app:app --reload --port 8001\n\n" +
                "Error: \(error.localizedDescription)"
            )
        }
    }

    // MARK: - Private

    private func run() async {
        switch mode {
        case .status:  await checkStatus()
        case .suggest: await runSuggest()
        case .review:  await runReview()
        }
    }

    private func runSuggest() async {
        let text = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        state = .loading
        do {
            // Augment description with schematic context when available
            let description = schematicContext.map { "\($0)\n\n---\nRequest: \(text)" } ?? text
            let result = try await client.suggestComponents(description: description)
            responseText = format(suggestions: result)
            state = .done
        } catch {
            state = .error(error.localizedDescription)
        }
    }

    private func runReview() async {
        state = .loading
        do {
            let content: String
            if let url = schematicURL,
               let fileContent = try? String(contentsOf: url, encoding: .utf8) {
                content = fileContent
            } else {
                let text = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else {
                    state = .error(
                        "No schematic loaded.\n\n" +
                        "Open a KiCad project (⇧⌘O) or paste schematic content in the text field."
                    )
                    return
                }
                content = text
            }
            let result = try await client.reviewSchematic(fileContent: content)
            responseText = format(review: result)
            state = .done
        } catch {
            state = .error(error.localizedDescription)
        }
    }

    // MARK: - Formatters

    private func format(health h: GatewayHealth, tools ts: [GatewayTool]) -> String {
        var lines = [
            "Gateway Status",
            String(repeating: "─", count: 40),
            "",
            "Status:   \(h.status.uppercased())",
            "Service:  \(h.service)",
            "Tools:    \(h.tools) registered",
            "YiACAD:   \(h.yiacadStatus)",
            ""
        ]
        if !ts.isEmpty {
            lines.append("Registered tools:")
            for t in ts {
                lines.append("  • \(t.name) v\(t.version) — \(t.status)")
                lines.append("    \(t.capabilities.joined(separator: ", "))")
            }
        }
        return lines.joined(separator: "\n")
    }

    private func format(suggestions r: FF_ComponentSuggestResponse) -> String {
        var lines = [
            "Component Suggestions",
            "Model: \(r.modelUsed)",
            String(repeating: "─", count: 40),
            ""
        ]
        for (i, s) in r.suggestions.enumerated() {
            lines.append("\(i + 1). \(s.name) [\(s.package)]")
            if !s.manufacturer.isEmpty { lines.append("   \(s.manufacturer)") }
            if !s.keySpecs.isEmpty {
                let specs = s.keySpecs.map { "\($0.key): \($0.value)" }.joined(separator: ", ")
                lines.append("   \(specs)")
            }
            if !s.reason.isEmpty { lines.append("   → \(s.reason)") }
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    private func format(review r: FF_SchematicReviewResponse) -> String {
        var lines = [
            "Schematic Review",
            "Model: \(r.modelUsed)",
            String(repeating: "─", count: 40),
            "",
            r.summary,
            "Analyzed: \(r.componentsAnalyzed) components, \(r.netsAnalyzed) nets",
            ""
        ]
        if r.issues.isEmpty {
            lines.append("✓ No issues found.")
        } else {
            lines.append("Issues (\(r.issues.count)):\n")
            for issue in r.issues {
                let icon: String
                switch issue.severity {
                case "high":   icon = "✗"
                case "medium": icon = "⚠"
                default:       icon = "ℹ"
                }
                lines.append("\(icon) [\(issue.category)] \(issue.message)")
                if !issue.component.isEmpty { lines.append("  @ \(issue.component)") }
                if !issue.suggestion.isEmpty { lines.append("  Fix: \(issue.suggestion)") }
                lines.append("")
            }
        }
        return lines.joined(separator: "\n")
    }
}
