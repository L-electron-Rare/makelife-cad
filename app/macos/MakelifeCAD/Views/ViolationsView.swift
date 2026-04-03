import SwiftUI

// MARK: - ViolationsView

/// Issues navigator panel — lists DRC/ERC violations grouped by severity.
/// Mirrors Xcode's issue navigator pattern.
struct ViolationsView: View {

    enum CheckKind {
        case drc(KiCadPCBBridge)
        case erc(KiCadBridge)
    }

    let kind: CheckKind

    @State private var violations: [DRCViolation] = []
    @State private var isRunning: Bool = false
    @State private var hasRun: Bool = false

    // MARK: - Derived

    private var errors: [DRCViolation]   { violations.filter { $0.isError } }
    private var warnings: [DRCViolation] { violations.filter { !$0.isError } }

    private var buttonLabel: String {
        switch kind {
        case .drc: return "Run DRC"
        case .erc: return "Run ERC"
        }
    }

    private var isLoaded: Bool {
        switch kind {
        case .drc(let b): return b.isLoaded
        case .erc(let b): return b.isLoaded
        }
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if hasRun {
                violationsList
            } else {
                emptyState
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            if hasRun {
                summaryBadge(count: errors.count, color: .red, label: "error")
                summaryBadge(count: warnings.count, color: .yellow, label: "warning")
            } else {
                Text(buttonLabel)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                runCheck()
            } label: {
                Label(buttonLabel, systemImage: "play.fill")
                    .font(.caption)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(!isLoaded || isRunning)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.bar)
    }

    private func summaryBadge(count: Int, color: Color, label: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: count > 0
                  ? (label == "error" ? "xmark.circle.fill" : "exclamationmark.triangle.fill")
                  : "checkmark.circle.fill")
                .foregroundStyle(count > 0 ? color : .green)
                .font(.caption)
            Text("\(count) \(label)\(count == 1 ? "" : "s")")
                .font(.caption)
                .foregroundStyle(count > 0 ? .primary : .secondary)
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.seal")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("Press \"\(buttonLabel)\" to check the design")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    // MARK: - Violations list

    private var violationsList: some View {
        Group {
            if violations.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.largeTitle)
                        .foregroundStyle(.green)
                    Text("No violations found")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    if !errors.isEmpty {
                        Section("Errors (\(errors.count))") {
                            ForEach(errors) { v in
                                ViolationRow(violation: v)
                            }
                        }
                    }
                    if !warnings.isEmpty {
                        Section("Warnings (\(warnings.count))") {
                            ForEach(warnings) { v in
                                ViolationRow(violation: v)
                            }
                        }
                    }
                }
                .listStyle(.sidebar)
            }
        }
    }

    // MARK: - Action

    private func runCheck() {
        isRunning = true
        // Run synchronously on main thread — C bridge is fast for typical boards
        switch kind {
        case .drc(let b): violations = b.runDRC()
        case .erc(let b): violations = b.runERC()
        }
        hasRun = true
        isRunning = false
    }
}

// MARK: - ViolationRow

private struct ViolationRow: View {
    let violation: DRCViolation

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            severityIcon
            VStack(alignment: .leading, spacing: 2) {
                Text(violation.message)
                    .font(.caption)
                    .lineLimit(3)
                HStack(spacing: 6) {
                    Text(violation.rule)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 3))
                    if let layer = violation.layer, !layer.isEmpty {
                        Text(layer)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    if let comp = violation.component, !comp.isEmpty {
                        Text(comp)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    if let pin = violation.pin, !pin.isEmpty {
                        Text("pin \(pin)")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    if let loc = violation.location {
                        Text(String(format: "(%.2f, %.2f)", loc.x, loc.y))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
        .padding(.vertical, 2)
    }

    private var severityIcon: some View {
        Group {
            if violation.isError {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.red)
            } else {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.yellow)
            }
        }
        .font(.caption)
        .frame(width: 14)
    }
}
