import SwiftUI

// MARK: - Sidebar

struct GitHubSidebarView: View {
    @ObservedObject var vm: GitHubLibraryViewModel

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        .frame(minWidth: 220, idealWidth: 260, maxWidth: 320)
        .task { await vm.load() }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "books.vertical.fill")
                .foregroundStyle(Color.accentColor)
            Text("makelife-hard")
                .font(.headline)
            Spacer()
            if vm.isLoading {
                ProgressView()
                    .scaleEffect(0.6)
            } else {
                Button {
                    Task { await vm.refresh() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Refresh library")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
    }

    @ViewBuilder
    private var content: some View {
        if let error = vm.error {
            errorView(error)
        } else if vm.categories.isEmpty && !vm.isLoading {
            emptyView
        } else {
            libraryList
        }
    }

    private func errorView(_ msg: String) -> some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: "wifi.slash")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("Could not load library")
                .font(.callout)
                .foregroundStyle(.secondary)
            Text(msg)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 12)
            Button("Retry") {
                Task { await vm.refresh() }
            }
            .buttonStyle(.bordered)
            Spacer()
        }
        .padding(12)
    }

    private var emptyView: some View {
        VStack {
            Spacer()
            Text("No KiCad blocks found")
                .font(.caption)
                .foregroundStyle(.tertiary)
            Spacer()
        }
    }

    private var libraryList: some View {
        List(selection: Binding(
            get: { vm.selectedEntry?.id },
            set: { id in
                vm.selectedEntry = vm.categories
                    .flatMap(\.entries)
                    .first { $0.id == id }
            }
        )) {
            ForEach(vm.categories) { category in
                Section(header: CategoryHeader(
                    name: category.name,
                    count: category.entries.count
                )) {
                    ForEach(category.entries) { entry in
                        EntryRow(entry: entry)
                            .tag(entry.id)
                    }
                }
            }
        }
        .listStyle(.sidebar)
    }
}

// MARK: - Detail

struct GitHubDetailView: View {
    let entry: GitHubEntry?

    var body: some View {
        if let entry = entry {
            entryDetail(entry)
        } else {
            placeholder
        }
    }

    private func entryDetail(_ entry: GitHubEntry) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header bar
            HStack(spacing: 10) {
                Image(systemName: entryIcon(entry))
                    .font(.title2)
                    .foregroundStyle(entryColor(entry))
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.name)
                        .font(.title3.bold())
                    Text(entry.path)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(20)
            .background(.ultraThinMaterial)

            Divider()

            // Info
            VStack(alignment: .leading, spacing: 16) {
                infoRow(label: "Repository", value: "L-electron-Rare/makelife-hard")
                infoRow(label: "Type", value: entryType(entry))
                infoRow(label: "Path", value: entry.path)

                if let html = entry.htmlUrl {
                    Divider()
                    Link(destination: URL(string: html)!) {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.up.right.square")
                            Text("Open on GitHub")
                        }
                        .font(.callout)
                    }
                }
            }
            .padding(20)

            Spacer()
        }
    }

    private var placeholder: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "books.vertical")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)
            Text("Select a design block")
                .foregroundStyle(.tertiary)
            Text("Browse L-electron-Rare/makelife-hard")
                .font(.caption)
                .foregroundStyle(.quaternary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func infoRow(label: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .trailing)
            Text(value)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
        }
    }

    private func entryIcon(_ entry: GitHubEntry) -> String {
        if entry.name.hasSuffix(".kicad_sch") { return "doc.richtext" }
        if entry.name.hasSuffix(".kicad_pcb") { return "cpu" }
        if entry.name.hasSuffix(".kicad_pro") { return "folder.fill" }
        return "doc"
    }

    private func entryColor(_ entry: GitHubEntry) -> Color {
        if entry.name.hasSuffix(".kicad_sch") { return .orange }
        if entry.name.hasSuffix(".kicad_pcb") { return .blue }
        return Color.accentColor
    }

    private func entryType(_ entry: GitHubEntry) -> String {
        if entry.name.hasSuffix(".kicad_sch") { return "KiCad Schematic" }
        if entry.name.hasSuffix(".kicad_pcb") { return "KiCad PCB Layout" }
        if entry.name.hasSuffix(".kicad_pro") { return "KiCad Project" }
        return "File"
    }
}

// MARK: - Sub-views

private struct CategoryHeader: View {
    let name: String
    let count: Int

    var body: some View {
        HStack {
            Text(name.capitalized)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
            Spacer()
            Text("\(count)")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.tertiary)
        }
    }
}

private struct EntryRow: View {
    let entry: GitHubEntry

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .frame(width: 16)
                .foregroundStyle(iconColor)
            Text(displayName)
                .font(.system(.caption, design: .monospaced))
                .lineLimit(1)
        }
        .padding(.vertical, 2)
    }

    private var displayName: String {
        entry.name
            .replacingOccurrences(of: ".kicad_sch", with: "")
            .replacingOccurrences(of: ".kicad_pcb", with: "")
            .replacingOccurrences(of: ".kicad_pro", with: "")
    }

    private var icon: String {
        if entry.name.hasSuffix(".kicad_sch") { return "doc.richtext" }
        if entry.name.hasSuffix(".kicad_pcb") { return "cpu" }
        return "folder"
    }

    private var iconColor: Color {
        if entry.name.hasSuffix(".kicad_sch") { return .orange }
        if entry.name.hasSuffix(".kicad_pcb") { return .blue }
        return .secondary
    }
}
