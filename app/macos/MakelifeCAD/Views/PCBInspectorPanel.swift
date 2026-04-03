// makelife-cad/app/macos/MakelifeCAD/Views/PCBInspectorPanel.swift
import SwiftUI

// MARK: - Toolbar (left strip)

struct PCBToolbar: View {
    @ObservedObject var vm: PCBEditorViewModel

    var body: some View {
        VStack(spacing: 4) {
            ForEach(PCBTool.allCases) { tool in
                Button {
                    vm.activeTool = tool
                    if tool == .track { vm.trackStart = nil }
                    if tool == .zone  { vm.zonePoints  = [] }
                } label: {
                    Image(systemName: tool.rawValue)
                        .frame(width: 28, height: 28)
                        .background(vm.activeTool == tool
                            ? Color.accentColor.opacity(0.2)
                            : Color.clear)
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)
                .help(tool.label)
            }
            Spacer()
        }
        .padding(.vertical, 8)
    }
}

// MARK: - Inspector

struct PCBInspectorPanel: View {
    @ObservedObject var vm: PCBEditorViewModel

    // Preset track widths in mm
    private let trackPresets = [0.1, 0.15, 0.2, 0.25, 0.5, 1.0]
    // Preset via sizes [outer, drill] in mm
    private let viaPresets: [(Double, Double)] = [
        (0.6, 0.3), (0.8, 0.4), (1.0, 0.5), (1.2, 0.6)
    ]
    // Available layers
    private let layers = ["F.Cu", "B.Cu", "In1.Cu", "In2.Cu"]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {

                // Active layer
                GroupBox("Active Layer") {
                    Picker("Layer", selection: $vm.activeLayer) {
                        ForEach(layers, id: \.self) { Text($0).tag($0) }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                }

                // Track width
                GroupBox("Track Width") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(String(format: "%.3g mm", vm.trackWidth))
                                .font(.system(size: 12, design: .monospaced))
                            Spacer()
                        }
                        Slider(value: $vm.trackWidth, in: 0.05...3.0, step: 0.05)
                        HStack(spacing: 4) {
                            ForEach(trackPresets, id: \.self) { w in
                                Button(String(format: "%.2g", w)) {
                                    vm.trackWidth = w
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.mini)
                                .tint(vm.trackWidth == w ? .accentColor : .secondary)
                            }
                        }
                    }
                }

                // Via settings
                GroupBox("Via Size") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(String(format: "\u{00D8}%.3g / drill %.3g mm",
                                        vm.viaSize, vm.viaDrill))
                                .font(.system(size: 12, design: .monospaced))
                            Spacer()
                        }
                        HStack(spacing: 4) {
                            ForEach(viaPresets, id: \.0) { size, drill in
                                Button(String(format: "%.1g", size)) {
                                    vm.viaSize  = size
                                    vm.viaDrill = drill
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.mini)
                                .tint(vm.viaSize == size ? .accentColor : .secondary)
                            }
                        }
                    }
                }

                // Net selection
                GroupBox("Net") {
                    HStack {
                        Text("Net ID")
                            .font(.caption)
                        Stepper(value: $vm.activeNetID, in: 0...999) {
                            Text("\(vm.activeNetID)")
                                .font(.system(size: 12, design: .monospaced))
                        }
                    }
                }

                // Grid
                GroupBox("Grid") {
                    HStack {
                        Text("Snap")
                            .font(.caption)
                        Picker("", selection: $vm.gridSize) {
                            Text("0.1 mm").tag(0.1)
                            Text("0.25 mm").tag(0.25)
                            Text("0.5 mm").tag(0.5)
                            Text("1.0 mm").tag(1.0)
                            Text("2.54 mm").tag(2.54)
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                    }
                }

                // Ratsnest toggle
                GroupBox("Display") {
                    Toggle("Ratsnest", isOn: $vm.showRatsnest)
                        .font(.caption)
                }

                // Selected item info
                if let selID = vm.selectedItemID {
                    GroupBox("Selection") {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Item #\(selID)")
                                .font(.system(size: 12, design: .monospaced))
                            if let item = vm.items.first(where: { $0.id == selID }) {
                                Text(String(format: "x: %.4g  y: %.4g", item.x, item.y))
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(.secondary)
                                Text("Layer: \(item.layer)")
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                            }
                            Button("Delete", role: .destructive) {
                                vm.deleteSelected()
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                }

                Spacer()
            }
            .padding(10)
        }
    }
}
