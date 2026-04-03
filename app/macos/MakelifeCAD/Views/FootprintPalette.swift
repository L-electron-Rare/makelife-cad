// makelife-cad/app/macos/MakelifeCAD/Views/FootprintPalette.swift
import SwiftUI

// MARK: - Data

struct FootprintEntry: Identifiable, Hashable {
    let id: String     // lib_id, e.g. "Resistor_SMD:R_0402"
    var library: String { id.components(separatedBy: ":").first ?? id }
    var name: String   { id.components(separatedBy: ":").last  ?? id }
}

// Built-in catalogue — Phase 5 uses a static list.
// Phase 7 will query the KiCad system library via bridge.
private let builtinFootprints: [FootprintEntry] = [
    FootprintEntry(id: "Resistor_SMD:R_0402"),
    FootprintEntry(id: "Resistor_SMD:R_0603"),
    FootprintEntry(id: "Resistor_SMD:R_0805"),
    FootprintEntry(id: "Capacitor_SMD:C_0402"),
    FootprintEntry(id: "Capacitor_SMD:C_0603"),
    FootprintEntry(id: "Capacitor_SMD:C_0805"),
    FootprintEntry(id: "Package_QFP:TQFP-32_7x7mm_P0.8mm"),
    FootprintEntry(id: "Package_QFP:LQFP-64_10x10mm_P0.5mm"),
    FootprintEntry(id: "Package_TO_SOT_SMD:SOT-23"),
    FootprintEntry(id: "Connector_PinHeader_2.54mm:PinHeader_1x02_P2.54mm_Vertical"),
    FootprintEntry(id: "Connector_PinHeader_2.54mm:PinHeader_1x04_P2.54mm_Vertical"),
    FootprintEntry(id: "LED_SMD:LED_0603_1608Metric"),
    FootprintEntry(id: "Crystal:Crystal_SMD_3225-4Pin_3.2x2.5mm"),
]

// MARK: - View

struct FootprintPalette: View {
    @State private var search: String = ""
    @ObservedObject var vm: PCBEditorViewModel

    var filtered: [FootprintEntry] {
        guard !search.isEmpty else { return builtinFootprints }
        return builtinFootprints.filter {
            $0.id.localizedCaseInsensitiveContains(search)
        }
    }

    var grouped: [(String, [FootprintEntry])] {
        let dict = Dictionary(grouping: filtered, by: \.library)
        return dict.sorted { $0.key < $1.key }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Search bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Search footprints\u{2026}", text: $search)
                    .textFieldStyle(.plain)
                if !search.isEmpty {
                    Button { search = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            // Grouped list
            List {
                ForEach(grouped, id: \.0) { lib, entries in
                    Section(lib) {
                        ForEach(entries) { entry in
                            FootprintRow(entry: entry)
                                .onTapGesture(count: 2) {
                                    // Double-tap: activate footprint tool + set pending lib_id
                                    vm.activeTool = .footprint
                                    NotificationCenter.default.post(
                                        name: .footprintDropped,
                                        object: entry.id)
                                }
                        }
                    }
                }
            }
            .listStyle(.sidebar)
        }
        .frame(minWidth: 200)
    }
}

// MARK: - Row

struct FootprintRow: View {
    let entry: FootprintEntry

    var body: some View {
        HStack {
            Image(systemName: "square.on.square")
                .foregroundColor(.secondary)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.name)
                    .font(.system(size: 12, weight: .medium))
                Text(entry.library)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        // Drag to canvas
        .draggable(entry.id)
    }
}
