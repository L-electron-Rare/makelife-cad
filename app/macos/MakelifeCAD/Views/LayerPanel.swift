import SwiftUI

// MARK: - LayerPanel

/// Sidebar panel showing layer toggles + footprint list for the PCB viewer.
struct LayerPanel: View {
    @ObservedObject var bridge: KiCadPCBBridge
    @Binding var activeLayerId: Int?
    @Binding var selectedFootprint: PCBFootprint?

    @State private var searchText: String = ""

    private var filteredFootprints: [PCBFootprint] {
        guard !searchText.isEmpty else { return bridge.footprints }
        let q = searchText.lowercased()
        return bridge.footprints.filter {
            $0.reference.lowercased().contains(q)
                || $0.value.lowercased().contains(q)
                || $0.layer.lowercased().contains(q)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // ---- Header ----
            HStack {
                Text("PCB Layers")
                    .font(.headline)
                Spacer()
                Text("\(bridge.layers.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial)

            Divider()

            if !bridge.isLoaded {
                Spacer()
                Text("No PCB loaded")
                    .foregroundStyle(.tertiary)
                    .font(.caption)
                Spacer()
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        // ---- Layer list ----
                        layerSection

                        Divider().padding(.vertical, 4)

                        // ---- Footprint list ----
                        footprintSection
                    }
                }
            }
        }
        .frame(minWidth: 220, idealWidth: 260, maxWidth: 320)
    }

    // MARK: - Layer section

    private var layerSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionTitle(label: "Layers", count: bridge.layers.count)

            // "All layers" row
            LayerRow(
                color: "#888888",
                name: "All layers",
                isActive: activeLayerId == nil,
                isVisible: true,
                onSelect: { activeLayerId = nil },
                onToggle: nil
            )

            ForEach(bridge.layers) { layer in
                LayerRow(
                    color: layer.color,
                    name: layer.name,
                    isActive: activeLayerId == layer.id,
                    isVisible: layer.visible,
                    onSelect: { activeLayerId = layer.id },
                    onToggle: {
                        bridge.toggleLayerVisibility(id: layer.id)
                    }
                )
            }
        }
    }

    // MARK: - Footprint section

    private var footprintSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionTitle(label: "Footprints", count: bridge.footprints.count)

            // Search
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
            .padding(.vertical, 4)

            ForEach(filteredFootprints) { fp in
                FootprintRow(footprint: fp,
                             isSelected: selectedFootprint?.id == fp.id)
                    .contentShape(Rectangle())
                    .onTapGesture { selectedFootprint = fp }
            }
        }
    }
}

// MARK: - LayerRow

private struct LayerRow: View {
    let color: String
    let name: String
    let isActive: Bool
    let isVisible: Bool
    let onSelect: () -> Void
    let onToggle: (() -> Void)?

    var body: some View {
        HStack(spacing: 8) {
            // Color swatch
            RoundedRectangle(cornerRadius: 3)
                .fill(colorFromHex(color))
                .frame(width: 14, height: 14)
                .overlay(
                    RoundedRectangle(cornerRadius: 3)
                        .strokeBorder(.white.opacity(0.15), lineWidth: 0.5)
                )

            // Layer name
            Text(name)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(isActive ? .primary : .secondary)
                .lineLimit(1)

            Spacer()

            // Visibility toggle
            if let toggle = onToggle {
                Button(action: toggle) {
                    Image(systemName: isVisible ? "eye" : "eye.slash")
                        .font(.caption2)
                        .foregroundStyle(isVisible ? .secondary : .tertiary)
                }
                .buttonStyle(.plain)
                .help(isVisible ? "Hide layer" : "Show layer")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(isActive
            ? Color.accentColor.opacity(0.15)
            : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture { onSelect() }
    }

    private func colorFromHex(_ hex: String) -> Color {
        let h = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        let val = UInt32(h, radix: 16) ?? 0x888888
        return Color(
            red:   Double((val >> 16) & 0xFF) / 255.0,
            green: Double((val >>  8) & 0xFF) / 255.0,
            blue:  Double( val        & 0xFF) / 255.0
        )
    }
}

// MARK: - FootprintRow

private struct FootprintRow: View {
    let footprint: PCBFootprint
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(footprint.reference)
                    .font(.system(.caption, design: .monospaced))
                    .bold()
                    .foregroundStyle(.primary)
                Spacer()
                Text(footprint.value)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            HStack {
                Text(footprint.layer)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Spacer()
                Text(String(format: "(%.1f, %.1f)", footprint.x, footprint.y))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(isSelected
            ? Color.accentColor.opacity(0.2)
            : Color.clear)
    }
}

// MARK: - SectionTitle

private struct SectionTitle: View {
    let label: String
    let count: Int

    var body: some View {
        HStack {
            Text(label.uppercased())
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .tracking(1)
            Spacer()
            Text("\(count)")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .monospacedDigit()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }
}
