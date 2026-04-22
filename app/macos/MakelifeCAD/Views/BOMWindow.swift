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

    /// Build a search query from value + footprint short name
    var searchQuery: String {
        "\(value) \(footprintShort)".trimmingCharacters(in: .whitespaces)
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

    // Supplier search state
    @State private var supplierResults: [UUID: [SupplierResult]] = [:]
    @State private var searchingEntries: Set<UUID> = []
    @State private var searchErrors: [UUID: String] = [:]
    @State private var selectedSupplierDetail: BOMEntry?

    private let searchClient = ComponentSearchClient()

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
        .frame(minWidth: 800, minHeight: 400)
        .navigationTitle("BOM — \(schBridge.components.count) components")
        .sheet(item: $selectedSupplierDetail) { _ in
            supplierDetailSheet
        }
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
            Button {
                searchAllSuppliers()
            } label: {
                Label("Search All Suppliers", systemImage: "cart")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(entries.isEmpty || !searchingEntries.isEmpty)
            Button("Export CSV") { exportCSV() }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(entries.isEmpty)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .adaptiveSidebarBackground()
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
            .width(70)

            TableColumn("Price") { entry in
                supplierPriceCell(for: entry)
            }
            .width(min: 60, ideal: 80)

            TableColumn("Stock") { entry in
                supplierStockCell(for: entry)
            }
            .width(min: 50, ideal: 70)

            TableColumn("Supplier") { entry in
                supplierActionCell(for: entry)
            }
            .width(min: 80, ideal: 110)
        }
    }

    // MARK: Supplier cells

    @ViewBuilder
    private func supplierPriceCell(for entry: BOMEntry) -> some View {
        if let results = supplierResults[entry.id], let best = results.first {
            Text(best.priceString)
                .monospacedDigit()
                .foregroundStyle(best.unitPrice != nil ? .primary : .secondary)
        } else if searchingEntries.contains(entry.id) {
            ProgressView().controlSize(.small)
        } else {
            Text("—").foregroundStyle(.tertiary)
        }
    }

    @ViewBuilder
    private func supplierStockCell(for entry: BOMEntry) -> some View {
        if let results = supplierResults[entry.id], let best = results.first {
            Text(best.stockString)
                .monospacedDigit()
                .foregroundStyle(best.stock ?? 0 > 0 ? .green : .red)
        } else {
            Text("—").foregroundStyle(.tertiary)
        }
    }

    @ViewBuilder
    private func supplierActionCell(for entry: BOMEntry) -> some View {
        HStack(spacing: 4) {
            if searchingEntries.contains(entry.id) {
                ProgressView().controlSize(.mini)
            } else if let results = supplierResults[entry.id], !results.isEmpty {
                // Show source badge + detail button
                Text(results.first?.source ?? "")
                    .font(.caption2)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(.blue.opacity(0.15))
                    .cornerRadius(3)
                Button {
                    selectedSupplierDetail = entry
                } label: {
                    Image(systemName: "info.circle")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .help("View supplier details")
            } else if let error = searchErrors[entry.id] {
                Image(systemName: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .help(error)
                Button {
                    searchSupplier(for: entry)
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
            } else {
                Button("Search") {
                    searchSupplier(for: entry)
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
            }
        }
    }

    // MARK: Supplier search

    private func searchSupplier(for entry: BOMEntry) {
        searchingEntries.insert(entry.id)
        searchErrors.removeValue(forKey: entry.id)

        Task {
            do {
                let results = try await searchClient.searchLCSC(query: entry.searchQuery)
                supplierResults[entry.id] = results
                if results.isEmpty {
                    searchErrors[entry.id] = "No results found"
                }
            } catch {
                searchErrors[entry.id] = error.localizedDescription
            }
            searchingEntries.remove(entry.id)
        }
    }

    private func searchAllSuppliers() {
        for entry in entries where supplierResults[entry.id] == nil && !searchingEntries.contains(entry.id) {
            searchSupplier(for: entry)
        }
    }

    // MARK: Supplier detail sheet

    @ViewBuilder
    private var supplierDetailSheet: some View {
        if let entry = selectedSupplierDetail, let results = supplierResults[entry.id] {
            VStack(alignment: .leading, spacing: 0) {
                // Header
                HStack {
                    VStack(alignment: .leading) {
                        Text(entry.value).font(.headline)
                        Text(entry.footprintShort).font(.subheadline).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Done") { selectedSupplierDetail = nil }
                        .keyboardShortcut(.cancelAction)
                }
                .padding()

                Divider()

                // Results list
                List(results) { result in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(result.partNumber).font(.headline.monospaced())
                            Spacer()
                            Text(result.source)
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(.blue.opacity(0.15))
                                .cornerRadius(4)
                        }
                        Text(result.manufacturer).font(.subheadline).foregroundStyle(.secondary)
                        if !result.description.isEmpty {
                            Text(result.description).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                        }
                        HStack(spacing: 16) {
                            Label(result.priceString, systemImage: "dollarsign.circle")
                                .font(.body.monospacedDigit())
                            Label(result.stockString, systemImage: "shippingbox")
                                .font(.body.monospacedDigit())
                                .foregroundStyle(result.stock ?? 0 > 0 ? .green : .red)
                            Spacer()
                            if let url = result.datasheetURL {
                                Link("Datasheet", destination: url)
                                    .font(.caption)
                            }
                            if let url = result.productURL {
                                Link("Product Page", destination: url)
                                    .font(.caption)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .frame(minWidth: 500, minHeight: 300)
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
        let hasSupplier = !supplierResults.isEmpty
        var header = "Qty,References,Value,Footprint,Category"
        if hasSupplier { header += ",Part Number,Manufacturer,Unit Price,Stock,Source" }

        let rows = entries.map { e -> String in
            var row = "\(e.quantity),\"\(e.refString)\",\"\(e.value)\",\"\(e.footprint)\",\(e.kind.rawValue)"
            if hasSupplier, let best = supplierResults[e.id]?.first {
                row += ",\"\(best.partNumber)\",\"\(best.manufacturer)\",\(best.priceString),\(best.stockString),\(best.source)"
            } else if hasSupplier {
                row += ",,,,,"
            }
            return row
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
