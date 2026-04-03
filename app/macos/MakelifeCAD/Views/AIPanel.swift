import SwiftUI

// MARK: - AI Sidebar (combines both providers)

struct AISidebarView: View {
    @ObservedObject var aiVM: AppleIntelligenceViewModel
    @ObservedObject var fineFabVM: FineFabViewModel
    @Binding var provider: AIProvider

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            providerPicker
            Divider()
            modeList
            Spacer(minLength: 0)
        }
        .frame(minWidth: 220, idealWidth: 260, maxWidth: 320)
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "sparkles")
                .foregroundStyle(Color.accentColor)
            Text("AI Assistant")
                .font(.headline)
            Spacer()
            if provider == .gateway {
                gatewayURLButton
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
    }

    @State private var showURLPopover = false

    private var gatewayURLButton: some View {
        Button {
            showURLPopover = true
        } label: {
            HStack(spacing: 4) {
                Circle()
                    .fill(fineFabVM.isConnected ? Color.green : Color.red)
                    .frame(width: 7, height: 7)
                Image(systemName: "gear")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
        .help("Configure gateway URL")
        .popover(isPresented: $showURLPopover, arrowEdge: .bottom) {
            GatewayURLPopover(baseURL: $fineFabVM.baseURL) {
                Task { await fineFabVM.checkStatus() }
            }
        }
    }

    // MARK: Provider picker

    private var providerPicker: some View {
        Picker("", selection: $provider) {
            ForEach(AIProvider.allCases) { p in
                Text(p.rawValue).tag(p)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }

    // MARK: Mode list

    @ViewBuilder
    private var modeList: some View {
        switch provider {
        case .onDevice:
            ForEach(AIMode.allCases) { mode in
                modeRow(
                    label: mode.rawValue,
                    icon: mode.systemImage,
                    selected: aiVM.mode == mode
                ) { aiVM.mode = mode }
                Divider()
            }
        case .gateway:
            ForEach(FineFabMode.allCases) { mode in
                modeRow(
                    label: mode.rawValue,
                    icon: mode.systemImage,
                    selected: fineFabVM.mode == mode
                ) {
                    fineFabVM.mode = mode
                    if mode == .status { Task { await fineFabVM.checkStatus() } }
                }
                Divider()
            }
        }
    }

    private func modeRow(
        label: String,
        icon: String,
        selected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .frame(width: 20)
                    .foregroundStyle(selected ? Color.accentColor : .secondary)
                Text(label)
                    .font(.callout)
                    .foregroundStyle(selected ? .primary : .secondary)
                Spacer()
                if selected {
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(selected ? Color.accentColor.opacity(0.08) : .clear)
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
    }
}

// MARK: - AI Detail (combines both providers)

struct AIDetailView: View {
    @ObservedObject var aiVM: AppleIntelligenceViewModel
    @ObservedObject var fineFabVM: FineFabViewModel
    let provider: AIProvider

    var body: some View {
        switch provider {
        case .onDevice:
            onDeviceDetail
        case .gateway:
            gatewayDetail
        }
    }

    // MARK: On-device detail

    private var onDeviceDetail: some View {
        VStack(spacing: 0) {
            onDeviceResponseArea
            Divider()
            onDeviceInputBar
        }
    }

    @ViewBuilder
    private var onDeviceResponseArea: some View {
        switch aiVM.state {
        case .idle:
            aiPlaceholder
        case .thinking:
            loadingView(label: "Thinking…")
        case .streaming:
            responseText(aiVM.responseText.isEmpty ? "…" : aiVM.responseText)
        case .done:
            responseText(aiVM.responseText)
        case .unavailable(let reason):
            unavailableView(reason: reason)
        case .error(let msg):
            errorView(msg: msg) { aiVM.reset() }
        }
    }

    private var aiPlaceholder: some View {
        placeholder(
            icon: "sparkles",
            title: "Apple Intelligence",
            subtitle: aiVM.mode.placeholder
        )
    }

    private var onDeviceInputBar: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField(aiVM.mode.placeholder, text: $aiVM.prompt, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...5)
                .padding(8)
                .background(Color(.textBackgroundColor).opacity(0.5))
                .cornerRadius(8)
                .onSubmit { sendAI() }

            onDeviceActionButton

            if case .done = aiVM.state {
                clearButton { aiVM.reset() }
            }
        }
        .padding(12)
        .background(.ultraThinMaterial)
    }

    @ViewBuilder
    private var onDeviceActionButton: some View {
        switch aiVM.state {
        case .thinking, .streaming:
            stopButton { aiVM.cancel() }
        default:
            sendButton(
                enabled: !aiVM.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                action: sendAI
            )
        }
    }

    private func sendAI() {
        guard !aiVM.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        aiVM.submit()
    }

    // MARK: Gateway detail

    private var gatewayDetail: some View {
        VStack(spacing: 0) {
            gatewayResponseArea
            if fineFabVM.mode != .status {
                Divider()
                gatewayInputBar
            }
        }
    }

    @ViewBuilder
    private var gatewayResponseArea: some View {
        switch fineFabVM.state {
        case .idle:
            gatewayPlaceholder
        case .loading:
            loadingView(label: gatewayLoadingLabel)
        case .done:
            responseText(fineFabVM.responseText)
        case .error(let msg):
            errorView(msg: msg) { fineFabVM.reset() }
        }
    }

    private var gatewayLoadingLabel: String {
        switch fineFabVM.mode {
        case .status:  return "Checking gateway…"
        case .suggest: return "Querying mascarade-kicad…"
        case .review:  return "Reviewing with mascarade-kicad…"
        }
    }

    private var gatewayPlaceholder: some View {
        let showFileHint = fineFabVM.mode == .review && fineFabVM.schematicURL == nil
        return placeholder(
            icon: "bolt.circle",
            title: "Factory 4 Life AI",
            subtitle: showFileHint
                ? "Open a KiCad project (⇧⌘O) to enable file-based review"
                : fineFabVM.mode.placeholder
        )
    }

    private var gatewayInputBar: some View {
        HStack(alignment: .bottom, spacing: 8) {
            // Review: show loaded file or text input
            if fineFabVM.mode == .review, let url = fineFabVM.schematicURL {
                HStack(spacing: 6) {
                    Image(systemName: "doc.richtext")
                        .foregroundStyle(Color.accentColor)
                    Text(url.lastPathComponent)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer()
                }
                .padding(8)
                .background(Color(.textBackgroundColor).opacity(0.5))
                .cornerRadius(8)
            } else {
                TextField(fineFabVM.mode.placeholder, text: $fineFabVM.prompt, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...4)
                    .padding(8)
                    .background(Color(.textBackgroundColor).opacity(0.5))
                    .cornerRadius(8)
            }

            gatewayActionButton

            if case .done = fineFabVM.state {
                clearButton { fineFabVM.reset() }
            }
        }
        .padding(12)
        .background(.ultraThinMaterial)
    }

    @ViewBuilder
    private var gatewayActionButton: some View {
        if case .loading = fineFabVM.state {
            ProgressView().scaleEffect(0.8)
        } else {
            let canSend = fineFabVM.mode == .review && fineFabVM.schematicURL != nil
                || !fineFabVM.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            sendButton(enabled: canSend) { fineFabVM.submit() }
        }
    }

    // MARK: Reusable sub-views

    private func placeholder(icon: String, title: String, subtitle: String) -> some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: icon)
                .font(.system(size: 44))
                .foregroundStyle(.tertiary)
            VStack(spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func loadingView(label: String) -> some View {
        VStack(spacing: 12) {
            Spacer()
            ProgressView().scaleEffect(1.2)
            Text(label)
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func responseText(_ text: String) -> some View {
        ScrollView {
            Text(text)
                .textSelection(.enabled)
                .font(.body)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func unavailableView(reason: String) -> some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "brain")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text("Unavailable")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text(reason)
                .font(.callout)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorView(msg: String, onClear: @escaping () -> Void) -> some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 44))
                .foregroundStyle(.orange)
            Text("Error")
                .font(.headline)
            Text(msg)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button("Clear", action: onClear).buttonStyle(.bordered)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func stopButton(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "stop.circle.fill")
                .font(.title2)
                .foregroundStyle(.red)
        }
        .buttonStyle(.plain)
        .help("Stop")
    }

    private func sendButton(enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "arrow.up.circle.fill")
                .font(.title2)
                .foregroundStyle(enabled ? Color.accentColor : Color.secondary)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .help("Send")
    }

    private func clearButton(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "trash").foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .help("Clear response")
    }
}

// MARK: - Gateway URL popover

private struct GatewayURLPopover: View {
    @Binding var baseURL: String
    let onConfirm: () -> Void

    @State private var editURL: String = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Gateway URL")
                .font(.headline)
            TextField("http://localhost:8001", text: $editURL)
                .textFieldStyle(.roundedBorder)
                .frame(width: 240)
            HStack {
                Button("Cancel") { dismiss() }
                    .buttonStyle(.bordered)
                Button("Apply") {
                    baseURL = editURL
                    onConfirm()
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(16)
        .onAppear { editURL = baseURL }
    }
}
