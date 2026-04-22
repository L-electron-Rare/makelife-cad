import Foundation
import FoundationModels

// MARK: - @Generable structured types (macOS 26+)

@available(macOS 26.0, *)
@Generable(description: "A suggested electronic component for a circuit")
struct ComponentSuggestion {
    @Guide(description: "Reference designator like R1, C1, U1")
    var reference: String

    @Guide(description: "Component value like 10kΩ, 100nF, LM1117-3.3")
    var value: String

    @Guide(description: "KiCad footprint like Resistor_SMD:R_0603_1608Metric")
    var footprint: String

    @Guide(description: "Brief explanation why this component is needed")
    var reason: String
}

@available(macOS 26.0, *)
@Generable(description: "A list of suggested components for a circuit requirement")
struct ComponentSuggestionList {
    @Guide(description: "One-line summary of the circuit requirement")
    var summary: String

    var suggestions: [ComponentSuggestion]
}

@available(macOS 26.0, *)
@Generable(description: "A single design issue found in a schematic review")
struct SchematicIssue {
    @Guide(description: "Severity: critical, warning, or info")
    var severity: String

    @Guide(description: "Component reference or area where the issue is")
    var location: String

    @Guide(description: "Description of the issue")
    var issue: String

    @Guide(description: "Recommended fix for the issue")
    var fix: String
}

@available(macOS 26.0, *)
@Generable(description: "A schematic design review with issues found")
struct SchematicReviewResult {
    @Guide(description: "One-line overall assessment of the schematic quality")
    var summary: String

    var issues: [SchematicIssue]
}

// MARK: - Mode

enum AIMode: String, CaseIterable, Identifiable {
    case ask     = "Ask"
    case suggest = "Suggest Components"
    case review  = "Review Schematic"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .ask:     return "bubble.left.and.text.bubble.right"
        case .suggest: return "sparkles"
        case .review:  return "checkmark.seal"
        }
    }

    var placeholder: String {
        switch self {
        case .ask:
            return "Ask anything about EDA or KiCad…"
        case .suggest:
            return "Describe your circuit (e.g. 3.3 V LDO for ESP32 @ 500 mA)…"
        case .review:
            return "Describe your schematic components and connections for a review…"
        }
    }
}

// MARK: - ViewModel

@MainActor
final class AppleIntelligenceViewModel: ObservableObject {

    enum State {
        case idle
        case thinking
        case streaming
        case done
        case unavailable(String)
        case error(String)
    }

    @Published var prompt: String = ""
    @Published var mode: AIMode = .ask
    @Published private(set) var state: State = .idle
    @Published private(set) var responseText: String = ""

    /// Structured suggestions from the last Suggest run (macOS 26+).
    /// UI can use these to offer "Add to schematic" actions.
    @Published private(set) var lastSuggestionRefs: [(reference: String, value: String, footprint: String)] = []

    /// Set by ContentView when a schematic is loaded — automatically prepended to prompts.
    var schematicSummary: String? = nil

    private var activeTask: Task<Void, Never>?

    /// Injects schematic context into a user prompt when a schematic is loaded.
    private func withContext(_ prompt: String) -> String {
        guard let summary = schematicSummary, !summary.isEmpty else { return prompt }
        return "\(summary)\n\n---\n\(prompt)"
    }

    // MARK: - Public

    func submit() {
        let text = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        activeTask?.cancel()
        activeTask = Task { await run(userPrompt: text) }
    }

    func cancel() {
        activeTask?.cancel()
        activeTask = nil
        switch state {
        case .thinking, .streaming: state = .idle
        default: break
        }
    }

    func reset() {
        cancel()
        state = .idle
        responseText = ""
        prompt = ""
    }

    // MARK: - Private

    private func run(userPrompt: String) async {
        guard !Task.isCancelled else { return }
        if #available(macOS 26.0, *) {
            await runWithFoundationModels(userPrompt: userPrompt)
        } else {
            state = .unavailable("Apple Intelligence requires macOS 26 (Tahoe) or later.")
        }
    }

    @available(macOS 26.0, *)
    private func runWithFoundationModels(userPrompt: String) async {
        let model = SystemLanguageModel.default
        switch model.availability {
        case .available:
            break
        case .unavailable(.deviceNotEligible):
            state = .unavailable("This device does not support Apple Intelligence.")
            return
        case .unavailable(.appleIntelligenceNotEnabled):
            state = .unavailable("Enable Apple Intelligence in System Settings › Apple Intelligence & Siri.")
            return
        case .unavailable(.modelNotReady):
            state = .unavailable("Apple Intelligence model is downloading. Try again in a moment.")
            return
        case .unavailable(let other):
            state = .unavailable("Apple Intelligence unavailable (\(other)).")
            return
        }

        responseText = ""

        let contextualPrompt = withContext(userPrompt)
        switch mode {
        case .ask:     await streamAsk(contextualPrompt)
        case .suggest: await structuredSuggest(contextualPrompt)
        case .review:  await structuredReview(contextualPrompt)
        }
    }

    @available(macOS 26.0, *)
    private func streamAsk(_ userPrompt: String) async {
        state = .streaming
        do {
            let session = LanguageModelSession(
                instructions: "You are a KiCad EDA and electronics engineering expert. Give concise, practical answers."
            )
            let stream = session.streamResponse(to: userPrompt)
            for try await partial in stream {
                guard !Task.isCancelled else { return }
                responseText = partial.content
            }
            state = .done
        } catch is CancellationError {
            state = .idle
        } catch {
            state = .error(error.localizedDescription)
        }
    }

    @available(macOS 26.0, *)
    private func structuredSuggest(_ userPrompt: String) async {
        state = .thinking
        lastSuggestionRefs = []
        do {
            let session = LanguageModelSession(
                instructions: """
                    You are a KiCad EDA expert. Suggest electronic components for the given \
                    circuit requirement. Use standard reference designators, realistic values, \
                    and common KiCad footprints.
                    """
            )
            state = .streaming
            let response = try await session.respond(
                to: "Suggest 5 components for: \(userPrompt)",
                generating: ComponentSuggestionList.self
            )
            guard !Task.isCancelled else { return }
            let result = response.content

            // Format structured result as readable text
            var text = "Component Suggestions\n"
            text += "────────────────────────────────\n"
            text += result.summary + "\n\n"
            for (i, s) in result.suggestions.enumerated() {
                text += "\(i + 1). \(s.reference)  \(s.value)\n"
                text += "   Footprint: \(s.footprint)\n"
                text += "   \(s.reason)\n\n"
            }
            responseText = text

            // Store structured data for "Add to schematic" actions
            lastSuggestionRefs = result.suggestions.map {
                (reference: $0.reference, value: $0.value, footprint: $0.footprint)
            }
            state = .done
        } catch is CancellationError {
            state = .idle
        } catch {
            state = .error(error.localizedDescription)
        }
    }

    @available(macOS 26.0, *)
    private func structuredReview(_ userPrompt: String) async {
        state = .thinking
        do {
            let session = LanguageModelSession(
                instructions: """
                    You are a KiCad EDA design reviewer. Find design issues: missing decoupling \
                    capacitors, wrong voltage levels, missing pull-up/pull-down resistors, \
                    power pin errors, ERC violations.
                    """
            )
            state = .streaming
            let response = try await session.respond(
                to: "Review this schematic: \(userPrompt)",
                generating: SchematicReviewResult.self
            )
            guard !Task.isCancelled else { return }
            let result = response.content

            // Format structured result as readable text
            var text = "Schematic Review\n"
            text += "────────────────────────────────\n"
            text += result.summary + "\n\n"
            text += "Issues (\(result.issues.count)):\n"
            for issue in result.issues {
                let icon: String
                switch issue.severity.lowercased() {
                case "critical": icon = "🔴"
                case "warning":  icon = "🟡"
                default:         icon = "🔵"
                }
                text += "\(icon) [\(issue.severity)] \(issue.location): \(issue.issue)\n"
                text += "   Fix: \(issue.fix)\n\n"
            }
            responseText = text
            state = .done
        } catch is CancellationError {
            state = .idle
        } catch {
            state = .error(error.localizedDescription)
        }
    }
}
