import SwiftUI

struct ComponentList: View {
    @ObservedObject var bridge: KiCadBridge
    @Binding var selectedComponent: SchematicComponent?
    @State private var searchText: String = ""

    // Group components by kind, filtered by search
    private var grouped: [(key: ComponentKind, value: [SchematicComponent])] {
        let filtered: [SchematicComponent]
        if searchText.isEmpty {
            filtered = bridge.components
        } else {
            let q = searchText.lowercased()
            filtered = bridge.components.filter {
                $0.reference.lowercased().contains(q)
                    || $0.value.lowercased().contains(q)
                    || $0.libId.lowercased().contains(q)
            }
        }
        // Group by kind, sort groups by raw value, sort items by reference
        let dict = Dictionary(grouping: filtered, by: \.kind)
        return ComponentKind.allCases.compactMap { kind in
            guard let items = dict[kind], !items.isEmpty else { return nil }
            let sorted = items.sorted { $0.reference < $1.reference }
            return (key: kind, value: sorted)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Components")
                    .font(.headline)
                Spacer()
                Text("\(bridge.components.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .adaptiveSidebarBackground()

            Divider()

            if !bridge.isLoaded {
                Spacer()
                Text("No schematic loaded")
                    .foregroundStyle(.tertiary)
                    .font(.caption)
                Spacer()
            } else {
                // Search field
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.tertiary)
                    TextField("Search\u{2026}", text: $searchText)
                        .textFieldStyle(.plain)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color(.textBackgroundColor).opacity(0.3))
                .cornerRadius(6)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)

                // Grouped list
                List(selection: Binding(
                    get: { selectedComponent?.id },
                    set: { id in
                        selectedComponent = bridge.components.first { $0.id == id }
                    }
                )) {
                    ForEach(grouped, id: \.key) { group in
                        Section(header: SectionHeader(kind: group.key, count: group.value.count)) {
                            ForEach(group.value) { component in
                                ComponentRow(component: component)
                                    .tag(component.id)
                            }
                        }
                    }
                }
                .listStyle(.sidebar)
            }
        }
        .frame(minWidth: 220, idealWidth: 260, maxWidth: 320)
    }
}

// MARK: - Section header

private struct SectionHeader: View {
    let kind: ComponentKind
    let count: Int

    var body: some View {
        HStack {
            Image(systemName: kindIcon(kind))
                .foregroundStyle(kindColor(kind))
                .font(.caption)
            Text(kind.rawValue)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text("\(count)")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .monospacedDigit()
        }
    }

    private func kindIcon(_ k: ComponentKind) -> String {
        switch k {
        case .resistor:   return "minus"
        case .capacitor:  return "rectangle"
        case .inductor:   return "wave.3.right"
        case .ic:         return "cpu"
        case .transistor: return "arrow.triangle.branch"
        case .diode:      return "arrow.right"
        case .connector:  return "point.3.filled.connected.trianglepath.dotted"
        case .other:      return "questionmark.circle"
        }
    }

    private func kindColor(_ k: ComponentKind) -> Color {
        switch k {
        case .resistor:   return Color(red: 0.98, green: 0.63, blue: 0.44) // peach
        case .capacitor:  return Color(red: 0.64, green: 0.89, blue: 0.63) // green
        case .inductor:   return Color(red: 0.53, green: 0.78, blue: 0.98) // blue
        case .ic:         return Color(red: 0.79, green: 0.65, blue: 0.97) // mauve
        case .transistor: return Color(red: 0.95, green: 0.55, blue: 0.66) // red
        case .diode:      return Color(red: 0.95, green: 0.83, blue: 0.53) // yellow
        case .connector:  return Color(red: 0.44, green: 0.85, blue: 0.76) // teal
        case .other:      return .secondary
        }
    }
}

// MARK: - Component row

private struct ComponentRow: View {
    let component: SchematicComponent

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(component.reference)
                    .font(.system(.body, design: .monospaced))
                    .bold()
                Spacer()
                Button {
                    NotificationCenter.default.post(
                        name: .makelifeHighlightInPCB,
                        object: component.reference
                    )
                } label: {
                    Image(systemName: "cpu")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .help("Locate in PCB")
                Text(component.value)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            if !component.footprint.isEmpty {
                Text(component.footprint.components(separatedBy: ":").last ?? component.footprint)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
    }
}
