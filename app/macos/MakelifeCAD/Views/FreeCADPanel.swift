import SwiftUI

struct FreeCADSidebarView: View {
    @ObservedObject var viewModel: FreeCADViewModel

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            runtimeSummary
            Divider()
            documentList
            Divider()
            actionBar
        }
        .frame(minWidth: 240, idealWidth: 280, maxWidth: 360)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "cube.transparent")
                .foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 2) {
                Text("FreeCAD")
                    .font(.headline)
                Text("YiACAD mechanical workspace")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if viewModel.isRefreshing {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }

    private var runtimeSummary: some View {
        VStack(alignment: .leading, spacing: 10) {
            statusRow(
                title: "Local runtime",
                status: viewModel.localStatus.status,
                detail: viewModel.localStatus.version ?? "missing"
            )
            statusRow(
                title: "Gateway export",
                status: viewModel.gatewayStatus?.status ?? "disabled",
                detail: viewModel.gatewayStatus?.version ?? "remote/off"
            )
            if let mode = selectedModeLabel {
                Label("Exports via \(mode)", systemImage: mode == "gateway" ? "network" : "desktopcomputer")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
    }

    private var documentList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                if viewModel.documents.isEmpty {
                    Text("No `.FCStd` files found in `mechanical/`.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    ForEach(viewModel.documents) { document in
                        Button {
                            viewModel.selectedDocument = document
                        } label: {
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: "cube")
                                    .foregroundStyle(viewModel.selectedDocument == document ? Color.accentColor : Color.secondary)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(document.name)
                                        .font(.callout.weight(.medium))
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)
                                    Text(document.relativePath)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                                Spacer()
                            }
                            .padding(10)
                            .background(viewModel.selectedDocument == document ? Color.accentColor.opacity(0.08) : .clear)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(8)
        }
    }

    private var actionBar: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Button("Open") {
                    viewModel.openSelectedInFreeCAD()
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.selectedDocument == nil)

                Button("Reveal") {
                    viewModel.revealSelectedInFinder()
                }
                .buttonStyle(.bordered)
                .disabled(viewModel.selectedDocument == nil)
            }

            HStack(spacing: 8) {
                Button("STEP") {
                    Task { await viewModel.exportSelected(format: .step) }
                }
                .buttonStyle(.bordered)
                .disabled(viewModel.selectedDocument == nil || viewModel.isExporting)

                Button("STL") {
                    Task { await viewModel.exportSelected(format: .stl) }
                }
                .buttonStyle(.bordered)
                .disabled(viewModel.selectedDocument == nil || viewModel.isExporting)
            }
        }
        .padding(12)
        .background(.ultraThinMaterial)
    }

    private func statusRow(title: String, status: String, detail: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(detail)
                    .font(.caption.monospaced())
                    .foregroundStyle(.primary)
            }
            Spacer()
            Text(status.uppercased())
                .font(.caption2.weight(.bold))
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(statusColor(status).opacity(0.12))
                .foregroundStyle(statusColor(status))
                .clipShape(Capsule())
        }
    }

    private func statusColor(_ status: String) -> Color {
        switch status {
        case "available": return .green
        case "incompatible": return .orange
        case "offline": return .secondary
        case "disabled": return .secondary
        default: return .red
        }
    }

    private var selectedModeLabel: String? {
        let mode = FreeCADExportPlanner.chooseMode(
            localStatus: viewModel.localStatus,
            gatewayBaseURL: viewModel.gatewayBaseURL,
            gatewayStatus: viewModel.gatewayStatus
        )
        return mode == .unavailable ? nil : mode.rawValue
    }
}

struct FreeCADDetailView: View {
    @ObservedObject var viewModel: FreeCADViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                documentHeader
                if let warning = viewModel.localStatus.warningText {
                    warningBanner(warning)
                }
                exportCard
                logCard
            }
            .padding(20)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var documentHeader: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                if let document = viewModel.selectedDocument {
                    Text(document.name)
                        .font(.title2.weight(.semibold))
                    Text(document.relativePath)
                        .font(.callout.monospaced())
                        .foregroundStyle(.secondary)
                    if let modified = document.lastModified {
                        Text("Modified \(modified.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("Select a FreeCAD document")
                        .font(.title3.weight(.semibold))
                    Text("YiACAD scans `mechanical/` recursively and lists all `.FCStd` files here.")
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Label("Mechanical document", systemImage: "cube")
        }
    }

    private var exportCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                if let job = viewModel.lastExportJob {
                    LabeledContent("Format", value: job.format.label)
                    LabeledContent("Mode", value: job.mode.rawValue)
                    LabeledContent("Status", value: job.state.rawValue)
                    LabeledContent("Version", value: job.versionUsed ?? "unknown")
                    LabeledContent("Source", value: job.source ?? "unknown")
                    if let outputPath = job.outputPath {
                        Text(outputPath)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                    }
                    if let errorMessage = job.errorMessage, !errorMessage.isEmpty {
                        Text(errorMessage)
                            .font(.callout)
                            .foregroundStyle(.red)
                    }
                } else {
                    Text("No export has run yet.")
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Label("Last export", systemImage: "shippingbox")
        }
    }

    private var logCard: some View {
        GroupBox {
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    if viewModel.logs.isEmpty {
                        Text("Logs will appear here when the runtime is validated or an export runs.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(Array(viewModel.logs.enumerated()), id: \.offset) { _, line in
                            Text(line)
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }
            .frame(minHeight: 220)
        } label: {
            Label("Runtime log", systemImage: "terminal")
        }
    }

    private func warningBanner(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(text)
                .font(.callout)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
