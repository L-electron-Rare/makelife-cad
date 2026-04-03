import SwiftUI

// MARK: - GitDiffView

struct GitDiffView: View {
    @EnvironmentObject var schBridge: KiCadBridge
    @EnvironmentObject var projectManager: KiCadProjectManager

    @StateObject private var vm = GitDiffViewModel()
    @State private var filter: FilterMode = .all

    enum FilterMode: String, CaseIterable {
        case all      = "All"
        case added    = "Added"
        case removed  = "Removed"
        case modified = "Modified"
    }

    private var diffs: [ComponentDiff] {
        guard case .done(let d) = vm.state else { return [] }
        switch filter {
        case .all:      return d
        case .added:    return d.filter { if case .added    = $0.change { return true }; return false }
        case .removed:  return d.filter { if case .removed  = $0.change { return true }; return false }
        case .modified: return d.filter {
            if case .valueChanged    = $0.change { return true }
            if case .footprintChanged = $0.change { return true }
            return false
        }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        .frame(minWidth: 520, minHeight: 360)
        .navigationTitle("Schematic Diff")
        .onAppear { runDiff() }
        .onChange(of: schBridge.isLoaded) { _, _ in runDiff() }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.triangle.branch")
                .foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 1) {
                Text(vm.schematicPath.isEmpty ? "No file loaded" : vm.schematicPath)
                    .font(.callout.bold())
                if !vm.commitSHA.isEmpty {
                    Text("vs. HEAD (\(vm.commitSHA))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if case .loading = vm.state {
                ProgressView().scaleEffect(0.7)
            }
            Button {
                runDiff()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.plain)
            .help("Re-run diff")
            .disabled(schBridge.components.isEmpty)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        switch vm.state {
        case .idle:
            emptyState(icon: "arrow.triangle.branch", msg: "No diff yet", sub: "Open a schematic to compare against HEAD")
        case .loading:
            VStack(spacing: 10) {
                Spacer()
                ProgressView("Comparing with HEAD…")
                Spacer()
            }
            .frame(maxWidth: .infinity)
        case .noGit:
            emptyState(icon: "questionmark.folder", msg: "Not a git repository",
                       sub: "The project directory is not tracked by git")
        case .noHistory:
            emptyState(icon: "clock.badge.xmark", msg: "No git history",
                       sub: "\(vm.schematicPath) has not been committed yet")
        case .clean:
            emptyState(icon: "checkmark.circle", msg: "No changes",
                       sub: "The schematic matches HEAD (\(vm.commitSHA))")
        case .error(let msg):
            emptyState(icon: "exclamationmark.triangle", msg: "Error", sub: msg)
        case .done:
            diffList
        }
    }

    // MARK: Diff list

    private var diffList: some View {
        VStack(spacing: 0) {
            // Filter bar + summary
            HStack(spacing: 6) {
                Picker("Filter", selection: $filter) {
                    ForEach(FilterMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 300)
                Spacer()
                diffSummaryChips
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            if diffs.isEmpty {
                emptyState(icon: "line.3.horizontal.decrease.circle",
                           msg: "No \(filter.rawValue.lowercased()) components", sub: "")
            } else {
                List(diffs) { diff in
                    diffRow(diff)
                }
                .listStyle(.inset)
            }
        }
    }

    private var diffSummaryChips: some View {
        HStack(spacing: 6) {
            if case .done(let d) = vm.state {
                let added    = d.filter { if case .added    = $0.change { return true }; return false }.count
                let removed  = d.filter { if case .removed  = $0.change { return true }; return false }.count
                let modified = d.filter {
                    if case .valueChanged    = $0.change { return true }
                    if case .footprintChanged = $0.change { return true }
                    return false
                }.count
                if added    > 0 { chip("+\(added)",     .green)  }
                if removed  > 0 { chip("-\(removed)",   .red)    }
                if modified > 0 { chip("~\(modified)",  .orange) }
            }
        }
    }

    private func chip(_ label: String, _ color: Color) -> some View {
        Text(label)
            .font(.caption.bold())
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }

    private func diffRow(_ diff: ComponentDiff) -> some View {
        HStack(spacing: 12) {
            Image(systemName: diff.icon)
                .foregroundStyle(rowColor(diff))
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(diff.reference)
                        .font(.system(.body, design: .monospaced).bold())
                    Text(diff.value)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                if !diff.changeLabel.isEmpty {
                    Text(diff.changeLabel)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            Text(diff.footprint.split(separator: ":").last.map(String.init) ?? diff.footprint)
                .font(.caption)
                .foregroundStyle(.quaternary)
        }
        .padding(.vertical, 3)
    }

    private func rowColor(_ diff: ComponentDiff) -> Color {
        switch diff.change {
        case .added:             return .green
        case .removed:           return .red
        case .valueChanged:      return .orange
        case .footprintChanged:  return .yellow
        }
    }

    // MARK: Empty state

    private func emptyState(icon: String, msg: String, sub: String) -> some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: icon)
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)
            Text(msg).font(.headline).foregroundStyle(.secondary)
            if !sub.isEmpty {
                Text(sub).font(.callout).foregroundStyle(.tertiary).multilineTextAlignment(.center)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Trigger

    private func runDiff() {
        guard schBridge.isLoaded,
              let fileURL = projectManager.currentProject?.schematicURL else { return }
        Task { await vm.diff(currentComponents: schBridge.components, fileURL: fileURL) }
    }
}
