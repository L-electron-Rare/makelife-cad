import SwiftUI

// MARK: - LayerStack3DPanel

/// Sidebar for the 3D viewer: layer stack cross-section, visibility toggles,
/// transparent mode toggle, selected component info panel.
struct LayerStack3DPanel: View {
    @Binding var layers:            [Layer3D]
    @Binding var selectedComponent: Component3D?
    @Binding var isTransparent:     Bool
    let onLayerToggle:              () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // -- Header --
            HStack {
                Text("3D Layers")
                    .font(.headline)
                Spacer()
                Toggle("Transparent", isOn: $isTransparent)
                    .toggleStyle(.button)
                    .font(.caption)
                    .onChange(of: isTransparent) { _, _ in onLayerToggle() }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {

                    // ---- Cross-section diagram ----
                    Text("STACK")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 12)
                        .padding(.top, 10)

                    LayerStackDiagram(layers: layers)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)

                    Divider().padding(.vertical, 4)

                    // ---- Layer toggles ----
                    ForEach(layers.indices, id: \.self) { idx in
                        LayerToggleRow(
                            layer: layers[idx],
                            onToggle: {
                                layers[idx].visible.toggle()
                                onLayerToggle()
                            }
                        )
                    }

                    Divider().padding(.vertical, 4)

                    // ---- Selected component info ----
                    if let comp = selectedComponent {
                        ComponentInfoPanel(comp: comp, onDeselect: { selectedComponent = nil })
                    } else {
                        Text("Click a component in the 3D view\nto select it")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                    }
                }
            }
        }
    }
}

// MARK: - LayerStackDiagram

/// Visual cross-section of the layer stack — colored bars stacked vertically.
private struct LayerStackDiagram: View {
    let layers: [Layer3D]

    var body: some View {
        VStack(spacing: 1) {
            // PCB substrate
            RoundedRectangle(cornerRadius: 2)
                .fill(Color(red: 0.05, green: 0.40, blue: 0.05))
                .frame(height: 14)
                .overlay(
                    Text("FR4 1.6mm")
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundStyle(.white)
                )

            ForEach(layers.sorted(by: { $0.zMM > $1.zMM })) { layer in
                layerBar(layer)
            }
        }
    }

    @ViewBuilder
    private func layerBar(_ layer: Layer3D) -> some View {
        let (r, g, b) = hexToRGB(layer.color)
        RoundedRectangle(cornerRadius: 1)
            .fill(Color(red: r, green: g, blue: b).opacity(layer.visible ? 0.85 : 0.25))
            .frame(height: 8)
            .overlay(
                Text(layer.name)
                    .font(.system(size: 7, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.9))
            )
    }

    private func hexToRGB(_ hex: String) -> (Double, Double, Double) {
        let h = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        let v = UInt32(h, radix: 16) ?? 0x888888
        return (
            Double((v >> 16) & 0xFF) / 255.0,
            Double((v >>  8) & 0xFF) / 255.0,
            Double( v        & 0xFF) / 255.0
        )
    }
}

// MARK: - LayerToggleRow

private struct LayerToggleRow: View {
    let layer:    Layer3D
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 8) {
                let (r, g, b) = hexToRGB(layer.color)
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color(red: r, green: g, blue: b))
                    .frame(width: 14, height: 14)
                    .opacity(layer.visible ? 1 : 0.3)

                Text(layer.name)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(layer.visible ? .primary : .tertiary)

                Spacer()

                Image(systemName: layer.visible ? "eye" : "eye.slash")
                    .font(.caption)
                    .foregroundStyle(layer.visible ? .primary : .tertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func hexToRGB(_ hex: String) -> (Double, Double, Double) {
        let h = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        let v = UInt32(h, radix: 16) ?? 0x888888
        return (
            Double((v >> 16) & 0xFF) / 255.0,
            Double((v >>  8) & 0xFF) / 255.0,
            Double( v        & 0xFF) / 255.0
        )
    }
}

// MARK: - ComponentInfoPanel

private struct ComponentInfoPanel: View {
    let comp:       Component3D
    let onDeselect: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(comp.reference)
                    .font(.headline)
                Spacer()
                Button(action: onDeselect) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)

            Grid(alignment: .leading, verticalSpacing: 3) {
                infoRow("Value",  comp.value)
                infoRow("Layer",  comp.layer)
                infoRow("Type",   comp.type.rawValue)
                infoRow("X",      String(format: "%.2f mm", comp.xMM))
                infoRow("Y",      String(format: "%.2f mm", comp.yMM))
                infoRow("Angle",  String(format: "%.1f\u{00B0}", comp.angleDeg))
                infoRow("Height", String(format: "%.2f mm", comp.heightMM))
                infoRow("BBox",   String(format: "%.2f \u{00D7} %.2f mm", comp.bboxW, comp.bboxH))
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 10)
        }
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .padding(8)
    }

    @ViewBuilder
    private func infoRow(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .gridColumnAlignment(.trailing)
            Text(value)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.primary)
                .gridColumnAlignment(.leading)
        }
    }
}
