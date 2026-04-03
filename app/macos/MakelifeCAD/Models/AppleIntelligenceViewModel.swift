import Foundation
import FoundationModels

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
        await streamGuidedResponse(
            instructions: """
                You are a KiCad EDA expert. Suggest five electronic components for the given \
                circuit requirement. Use standard reference designators and realistic values.
                """,
            prompt: """
                Suggest 5 components for: \(userPrompt)

                Return plain text in this format:
                Component Suggestions
                ----------------------------------------
                1. <reference>  <value>
                   <reason>
                """
        )
    }

    @available(macOS 26.0, *)
    private func structuredReview(_ userPrompt: String) async {
        await streamGuidedResponse(
            instructions: """
                You are a KiCad EDA design reviewer. Find design issues: missing decoupling \
                capacitors, wrong voltage levels, missing pull-up/pull-down resistors, \
                power pin errors, ERC violations.
                """,
            prompt: """
                Review this schematic: \(userPrompt)

                Return plain text in this format:
                Schematic Review
                ----------------------------------------
                <one-line summary>

                Issues (<count>):
                - [severity] [location] <issue>
                  Fix: <recommended fix>
                """
        )
    }

    @available(macOS 26.0, *)
    private func streamGuidedResponse(instructions: String, prompt: String) async {
        state = .thinking
        do {
            let session = LanguageModelSession(instructions: instructions)
            let stream = session.streamResponse(to: prompt)
            state = .streaming
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
}
