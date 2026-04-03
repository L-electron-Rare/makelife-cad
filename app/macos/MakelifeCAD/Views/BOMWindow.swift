import SwiftUI
import UniformTypeIdentifiers

// MARK: - BOM Entry

struct BOMEntry: Identifiable {
    let id = UUID()
    let value: String
    let footprint: String
    let references: [String]
    let kind: ComponentKind

    var quantity: Int { references.count }
    var refString: String { references.sorted().joined(separator: ", ") }
    var footprintShort: String {
        // e.g. "Resistor_SMD:R_0402" → "R_0402"
        footprint.split(separator: ":").last.map(String.init) ?? footprint
    }
}

// MARK: - BOM computation

private func buildBOM(from components: [SchematicComponent]) -> [BOMEntry] {
    var groups: [String: (value: String, footprint: String, kind: ComponentKind, refs: [String])] = [:]
    for c in components {
        let key = "\(c.value)|\(c.footprint)"
        if var g = groups[key] {
            g.refs.append(c.reference)
            groups[key] = g
        } else {
            groups[key] = (c.value, c.footprint, c.kind, [c.reference])
        }
    }
    return groups.values
        .map { BOMEntry(value: $0.value, footprint: $0.footprint, references: $0.refs, kind: $0.kind) }
        .sorted {
            if $0.kind.rawValue != $1.kind.rawValue { return $0.kind.rawValue < $1.kind.rawValue }
            return $0.value < $1.value
        }
}

// MARK: - BOMView

struct BOMView: View {
    @EnvironmentObject var schBridge: KiCadBridge

    @State private var searchText = ""
    @State private var sortOrder = [KeyPathComparator(\BOMEntry.value)]
    @State private var selection: BOMEntry.ID?

    private var entries: [BOMEntry] {
        let all = buildBOM(from: schBridge.components)
        if searchText.isEmpty { return all }
        let q = searchText.lowercased()
        return all.filter {
            $0.value.lowercased().contains(q) ||
            $0.refString.lowercased().contains(q) ||
            $0.footprint.lowercased().contains(q)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            if schBridge.components.isEmpty {
                emptyState
            } else {
                table
            }
        }
        .frame(minWidth: 600, minHeight: 360)
        .navigationTitle("BOM — \(schBridge.components.count) components")
    }

    // MARK: Toolbar

    private var toolbar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search…", text: $searchText)
                .textFieldStyle(.plain)
                .frame(maxWidth: 220)
            Spacer()
            Text("\(entries.count) lines · \(entries.map(\.quantity).reduce(0, +)) parts")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Export CSV") { exportCSV() }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(entries.isEmpty)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
    }

    // MARK: Table

    private var table: some View {
        Table(entries, selection: $selection, sortOrder: $sortOrder) {
            TableColumn("Qty") { entry in
                Text("\(entry.quantity)")
                    .monospacedDigit()
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .width(40)

            TableColumn("References") { entry in
                Text(entry.refString)
                    .font(.system(.body, design: .monospaced))
                    .lineLimit(1)
            }
            .width(min: 100, ideal: 140)

            TableColumn("Value", value: \.value)
                .width(min: 80, ideal: 120)

            TableColumn("Footprint") { entry in
                Text(entry.footprintShort)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .width(min: 100, ideal: 160)

            TableColumn("Category") { entry in
                Text(entry.kind.rawValue)
                    .foregroundStyle(.secondary)
            }
            .width(90)
        }
    }

    // MARK: Empty state

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "tablecells")
                .font(.system(size: 44))
                .foregroundStyle(.tertiary)
            Text("No schematic loaded")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("Open a .kicad_sch file or a KiCad project (⇧⌘O)")
                .font(.callout)
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: CSV Export

    private func exportCSV() {
        let header = "Qty,References,Value,Footprint,Category"
        let rows = entries.map { e in
            "\(e.quantity),\"\(e.refString)\",\"\(e.value)\",\"\(e.footprint)\",\(e.kind.rawValue)"
        }
        let csv = ([header] + rows).joined(separator: "\n")

        let panel = NSSavePanel()
        panel.title = "Export BOM"
        panel.allowedContentTypes = [UTType.commaSeparatedText]
        panel.nameFieldStringValue = "bom.csv"
        if panel.runModal() == .OK, let url = panel.url {
            try? csv.write(to: url, atomically: true, encoding: .utf8)
        }
    }
}
