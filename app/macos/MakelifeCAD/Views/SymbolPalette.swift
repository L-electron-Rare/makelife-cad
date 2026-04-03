import SwiftUI

// MARK: - Symbol catalog entry

struct SymbolEntry: Identifiable {
    let id = UUID()
    let libId:       String   // e.g. "Device:R"
    let displayName: String   // e.g. "Resistor"
    let systemImage: String
    let category:    String
}

// MARK: - SymbolPalette

struct SymbolPalette: View {

    var onSelect: (String) -> Void

    @State private var searchText: String = ""
    @State private var expandedCategories: Set<String> = ["Passives", "Semiconductors"]

    // Built-in catalog — common components for quick placement.
    // Phase 6+: query the KiCad library index via C bridge.
    private let catalog: [SymbolEntry] = [
        // Passives
        SymbolEntry(libId: "Device:R",        displayName: "Resistor",        systemImage: "minus",                             category: "Passives"),
        SymbolEntry(libId: "Device:C",        displayName: "Capacitor",       systemImage: "equal",                             category: "Passives"),
        SymbolEntry(libId: "Device:L",        displayName: "Inductor",        systemImage: "waveform",                          category: "Passives"),
        SymbolEntry(libId: "Device:R_Pack04", displayName: "Resistor Pack 4", systemImage: "rectangle.grid.2x2",                category: "Passives"),
        // Semiconductors
        SymbolEntry(libId: "Device:LED",          displayName: "LED",         systemImage: "lightbulb",    category: "Semiconductors"),
        SymbolEntry(libId: "Device:D",            displayName: "Diode",       systemImage: "chevron.right", category: "Semiconductors"),
        SymbolEntry(libId: "Device:Q_NPN_BCE",    displayName: "NPN BJT",     systemImage: "arrow.right",  category: "Semiconductors"),
        SymbolEntry(libId: "Device:Q_PMOS_GDS",   displayName: "PMOS FET",    systemImage: "arrow.left",   category: "Semiconductors"),
        // ICs
        SymbolEntry(libId: "Device:IC",  displayName: "Generic IC",     systemImage: "cpu",        category: "ICs"),
        SymbolEntry(libId: "Device:MCU", displayName: "Generic MCU",    systemImage: "memorychip", category: "ICs"),
        SymbolEntry(libId: "4xxx:4011",  displayName: "4011 NAND Gate", systemImage: "circuitry",  category: "ICs"),
        // Connectors
        SymbolEntry(libId: "Connector_Generic:Conn_01x02", displayName: "2-pin Header", systemImage: "rectangle.connected.to.line.below", category: "Connectors"),
        SymbolEntry(libId: "Connector_Generic:Conn_01x04", displayName: "4-pin Header", systemImage: "rectangle.connected.to.line.below", category: "Connectors"),
        SymbolEntry(libId: "Connector:USB_C_Receptacle",   displayName: "USB-C",        systemImage: "cable.connector",                   category: "Connectors"),
        // Power
        SymbolEntry(libId: "power:VCC",  displayName: "VCC",   systemImage: "arrow.up",   category: "Power"),
        SymbolEntry(libId: "power:GND",  displayName: "GND",   systemImage: "arrow.down", category: "Power"),
        SymbolEntry(libId: "power:+3V3", displayName: "+3.3V", systemImage: "plus",       category: "Power"),
        SymbolEntry(libId: "power:+5V",  displayName: "+5V",   systemImage: "plus",       category: "Power"),
    ]

    private var filtered: [SymbolEntry] {
        guard !searchText.isEmpty else { return catalog }
        return catalog.filter {
            $0.displayName.localizedCaseInsensitiveContains(searchText) ||
            $0.libId.localizedCaseInsensitiveContains(searchText)
        }
    }

    private var groupedFiltered: [(key: String, entries: [SymbolEntry])] {
        let grouped = Dictionary(grouping: filtered, by: \.category)
        return grouped.sorted { $0.key < $1.key }
                      .map { (key: $0.key, entries: $0.value) }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Search bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .font(.caption)
                TextField("Search symbols\u{2026}", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.callout)
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            // Symbol list grouped by category
            List {
                ForEach(groupedFiltered, id: \.key) { group in
                    Section {
                        ForEach(group.entries) { entry in
                            SymbolRow(entry: entry)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    onSelect(entry.libId)
                                }
                                .draggable(entry.libId)
                        }
                    } header: {
                        Text(group.key)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .listStyle(.sidebar)
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }
}

// MARK: - SymbolRow

private struct SymbolRow: View {
    let entry: SymbolEntry

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: entry.systemImage)
                .frame(width: 16)
                .foregroundStyle(.blue)
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.displayName)
                    .font(.callout)
                Text(entry.libId)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
    }
}
