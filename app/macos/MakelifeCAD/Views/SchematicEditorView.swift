import SwiftUI
import AppKit

// MARK: - Edit tool

enum SchTool: String, CaseIterable {
    case select = "Select"
    case wire   = "Wire"
    case symbol = "Symbol"
    case label  = "Label"

    var systemImage: String {
        switch self {
        case .select: return "cursorarrow"
        case .wire:   return "line.diagonal"
        case .symbol: return "cpu"
        case .label:  return "tag"
        }
    }
}

// MARK: - Canvas transform state

private struct CanvasTransform {
    var scale:   CGFloat = 1.0
    var offsetX: CGFloat = 0.0
    var offsetY: CGFloat = 0.0

    /// Convert screen point to schematic mils
    func toSchematic(_ p: CGPoint) -> CGPoint {
        CGPoint(
            x: (p.x - offsetX) / scale,
            y: (p.y - offsetY) / scale
        )
    }

    /// Convert schematic mils to screen point
    func toScreen(_ p: CGPoint) -> CGPoint {
        CGPoint(
            x: p.x * scale + offsetX,
            y: p.y * scale + offsetY
        )
    }
}

// MARK: - SchematicEditorView

struct SchematicEditorView: View {

    @ObservedObject var bridge: KiCadSchEditBridge

    // Active tool
    @State private var activeTool: SchTool = .select

    // Selection
    @State private var selectedItemId: UInt64? = nil

    // Canvas pan/zoom
    @State private var transform   = CanvasTransform()
    @State private var dragStart   = CGPoint.zero
    @State private var dragOffset  = CGPoint.zero
    @State private var isDragging  = false

    // Wire drawing state
    @State private var wireStart: CGPoint? = nil

    // Symbol to place (set by SymbolPalette)
    @State private var pendingSymbolLibId: String? = nil

    // Label input sheet
    @State private var showLabelSheet: Bool = false
    @State private var labelInputText: String = ""
    @State private var labelPlacementPoint: CGPoint = .zero

    // Palette + inspector
    @State private var showPalette:   Bool = true
    @State private var showInspector: Bool = true

    // Grid size in mils
    private let gridMils: CGFloat = 50.0

    var body: some View {
        HSplitView {
            // Left panel: symbol palette
            if showPalette {
                SymbolPalette(
                    onSelect: { libId in
                        pendingSymbolLibId = libId
                        activeTool = .symbol
                    }
                )
                .frame(minWidth: 180, idealWidth: 220, maxWidth: 260)
            }

            // Center: canvas + toolbar
            VStack(spacing: 0) {
                toolBar
                Divider()
                canvasView
            }

            // Right panel: property inspector
            if showInspector, let selId = selectedItemId,
               let item = bridge.items.first(where: { $0.id == selId }) {
                PropertyEditor(
                    item: item,
                    onApply: { key, value in
                        bridge.setProperty(id: selId, key: key, value: value)
                    }
                )
                .frame(minWidth: 200, idealWidth: 240, maxWidth: 280)
            }
        }
        .background(Color(red: 0.118, green: 0.118, blue: 0.180))
        .toolbar {
            ToolbarItemGroup(placement: .automatic) {
                Button {
                    showPalette.toggle()
                } label: {
                    Image(systemName: "sidebar.left")
                }
                .help("Toggle symbol palette")

                Button {
                    showInspector.toggle()
                } label: {
                    Image(systemName: "sidebar.right")
                }
                .help("Toggle property inspector")
            }
        }
        .onDeleteCommand {
            if let id = selectedItemId {
                bridge.deleteItem(id: id)
                selectedItemId = nil
            }
        }
        .sheet(isPresented: $showLabelSheet) {
            labelInputSheet
        }
    }

    // MARK: - Label input sheet

    private var labelInputSheet: some View {
        VStack(spacing: 16) {
            Text("Net Label")
                .font(.headline)
            TextField("Label text", text: $labelInputText)
                .textFieldStyle(.roundedBorder)
                .frame(width: 240)
            HStack {
                Button("Cancel") {
                    showLabelSheet = false
                    labelInputText = ""
                    wireStart = nil
                }
                Button("Place") {
                    let schPt = transform.toSchematic(labelPlacementPoint)
                    let snapped = snapToGrid(schPt)
                    bridge.addLabel(text: labelInputText,
                                    x: Double(snapped.x),
                                    y: Double(snapped.y))
                    labelInputText = ""
                    showLabelSheet = false
                    wireStart = nil
                }
                .buttonStyle(.borderedProminent)
                .disabled(labelInputText.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 300)
    }

    // MARK: - Toolbar

    private var toolBar: some View {
        HStack(spacing: 4) {
            ForEach(SchTool.allCases, id: \.self) { tool in
                Button {
                    activeTool = tool
                    if tool != .symbol { pendingSymbolLibId = nil }
                } label: {
                    Label(tool.rawValue, systemImage: tool.systemImage)
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.bordered)
                .background(activeTool == tool
                    ? Color.accentColor.opacity(0.25)
                    : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .help(tool.rawValue)
            }

            Divider().frame(height: 20)

            Button {
                bridge.undo()
            } label: {
                Image(systemName: "arrow.uturn.backward")
            }
            .disabled(!bridge.canUndo)
            .help("Undo (Cmd+Z)")

            Button {
                bridge.redo()
            } label: {
                Image(systemName: "arrow.uturn.forward")
            }
            .disabled(!bridge.canRedo)
            .help("Redo (Cmd+Shift+Z)")

            Spacer()

            if bridge.isDirty {
                Text("Unsaved changes")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.ultraThinMaterial)
    }

    // MARK: - Canvas

    private var canvasView: some View {
        Canvas { ctx, size in
            drawGrid(ctx: ctx, size: size)
            drawItems(ctx: ctx)
            drawWirePreview(ctx: ctx)
        }
        .background(Color(red: 0.118, green: 0.118, blue: 0.180))
        .contentShape(Rectangle())
        .gesture(panGesture)
        .gesture(
            MagnificationGesture()
                .onChanged { value in
                    let newScale = transform.scale * value
                    transform.scale = min(20, max(0.05, newScale))
                }
        )
        .onTapGesture(count: 2) { location in
            handleDoubleClick(at: location)
        }
        .onTapGesture(count: 1) { location in
            handleClick(at: location)
        }
    }

    // MARK: - Draw helpers

    private func drawGrid(ctx: GraphicsContext, size: CGSize) {
        let spacing = gridMils * transform.scale
        guard spacing > 4 else { return }

        var path = Path()
        let startX = transform.offsetX.truncatingRemainder(dividingBy: spacing)
        var x = startX
        while x <= size.width {
            path.move(to: CGPoint(x: x, y: 0))
            path.addLine(to: CGPoint(x: x, y: size.height))
            x += spacing
        }
        let startY = transform.offsetY.truncatingRemainder(dividingBy: spacing)
        var y = startY
        while y <= size.height {
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: size.width, y: y))
            y += spacing
        }
        ctx.stroke(path, with: .color(.white.opacity(0.06)), lineWidth: 0.5)
    }

    private func drawItems(ctx: GraphicsContext) {
        for item in bridge.items {
            let isSelected = item.id == selectedItemId
            switch item.type {
            case .symbol:
                drawSymbol(ctx: ctx, item: item, selected: isSelected)
            case .wire:
                drawWire(ctx: ctx, item: item, selected: isSelected)
            case .label:
                drawLabel(ctx: ctx, item: item, selected: isSelected)
            }
        }
    }

    private func drawSymbol(ctx: GraphicsContext, item: SchItem,
                            selected: Bool) {
        guard let sx = item.x, let sy = item.y else { return }
        let screen = transform.toScreen(CGPoint(x: sx, y: sy))
        let r: CGFloat = 14 * min(transform.scale, 2)

        let rect = CGRect(x: screen.x - r, y: screen.y - r,
                          width: r * 2, height: r * 2)
        ctx.fill(Path(rect), with: .color(.blue.opacity(0.25)))
        ctx.stroke(Path(rect), with: .color(selected ? .yellow : .blue),
                   lineWidth: selected ? 2 : 1)

        let labelText = item.reference ?? item.libId ?? "?"
        ctx.draw(
            Text(labelText).font(.system(size: 10 * min(transform.scale, 1.5),
                                         design: .monospaced))
                           .foregroundStyle(.white),
            at: CGPoint(x: screen.x, y: screen.y - r - 8)
        )
        if let val = item.value, !val.isEmpty {
            ctx.draw(
                Text(val).font(.system(size: 9 * min(transform.scale, 1.5),
                                       design: .monospaced))
                         .foregroundStyle(.secondary),
                at: CGPoint(x: screen.x, y: screen.y + r + 8)
            )
        }
    }

    private func drawWire(ctx: GraphicsContext, item: SchItem,
                          selected: Bool) {
        guard let x1 = item.x1, let y1 = item.y1,
              let x2 = item.x2, let y2 = item.y2 else { return }
        let p1 = transform.toScreen(CGPoint(x: x1, y: y1))
        let p2 = transform.toScreen(CGPoint(x: x2, y: y2))
        var path = Path()
        path.move(to: p1)
        path.addLine(to: p2)
        ctx.stroke(path,
                   with: .color(selected ? .yellow : .green),
                   lineWidth: selected ? 2.5 : 1.5)
    }

    private func drawLabel(ctx: GraphicsContext, item: SchItem,
                           selected: Bool) {
        guard let sx = item.x, let sy = item.y, let text = item.text else { return }
        let screen = transform.toScreen(CGPoint(x: sx, y: sy))
        let flagW: CGFloat = CGFloat(text.count) * 7 * min(transform.scale, 1.5) + 6
        let flagH: CGFloat = 14
        var path = Path()
        path.move(to: CGPoint(x: screen.x, y: screen.y))
        path.addLine(to: CGPoint(x: screen.x + flagW, y: screen.y - flagH / 2))
        path.addLine(to: CGPoint(x: screen.x + flagW, y: screen.y + flagH / 2))
        path.closeSubpath()
        ctx.fill(path, with: .color((selected ? Color.yellow : Color.orange).opacity(0.3)))
        ctx.stroke(path, with: .color(selected ? .yellow : .orange), lineWidth: 1)
        ctx.draw(
            Text(text).font(.system(size: 10 * min(transform.scale, 1.5),
                                    design: .monospaced))
                      .foregroundStyle(.white),
            at: CGPoint(x: screen.x + flagW / 2 + 3, y: screen.y)
        )
    }

    private func drawWirePreview(ctx: GraphicsContext) {
        guard activeTool == .wire, let start = wireStart else { return }
        var path = Path()
        path.move(to: start)
        path.addLine(to: dragOffset)
        ctx.stroke(path, with: .color(.green.opacity(0.6)),
                   style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
    }

    // MARK: - Interaction

    private func handleClick(at location: CGPoint) {
        let schPt = transform.toSchematic(location)
        let snapped = snapToGrid(schPt)

        switch activeTool {
        case .select:
            selectedItemId = hitTest(screenPoint: location)

        case .wire:
            if let start = wireStart {
                let startSchPt = transform.toSchematic(start)
                let snappedStart = snapToGrid(startSchPt)
                bridge.addWire(
                    x1: Double(snappedStart.x), y1: Double(snappedStart.y),
                    x2: Double(snapped.x),      y2: Double(snapped.y)
                )
                wireStart = nil
            } else {
                wireStart = location
            }

        case .symbol:
            let libId = pendingSymbolLibId ?? "Device:R"
            bridge.addSymbol(libId: libId,
                             x: Double(snapped.x),
                             y: Double(snapped.y))

        case .label:
            labelPlacementPoint = location
            labelInputText = ""
            showLabelSheet = true
        }
    }

    private func handleDoubleClick(at location: CGPoint) {
        guard activeTool == .select else { return }
        if let id = hitTest(screenPoint: location) {
            selectedItemId = id
            showInspector = true
        }
    }

    /// Simple AABB hit test — returns the topmost item id under screenPoint.
    private func hitTest(screenPoint: CGPoint) -> UInt64? {
        let hitRadius: CGFloat = 16
        for item in bridge.items.reversed() {
            switch item.type {
            case .symbol:
                guard let sx = item.x, let sy = item.y else { continue }
                let s = transform.toScreen(CGPoint(x: sx, y: sy))
                let r: CGFloat = 14 * min(transform.scale, 2)
                if abs(screenPoint.x - s.x) <= r && abs(screenPoint.y - s.y) <= r {
                    return item.id
                }

            case .wire:
                guard let x1 = item.x1, let y1 = item.y1,
                      let x2 = item.x2, let y2 = item.y2 else { continue }
                let p1 = transform.toScreen(CGPoint(x: x1, y: y1))
                let p2 = transform.toScreen(CGPoint(x: x2, y: y2))
                if distanceFromPoint(screenPoint, toSegment: p1, p2) < hitRadius {
                    return item.id
                }

            case .label:
                guard let sx = item.x, let sy = item.y else { continue }
                let s = transform.toScreen(CGPoint(x: sx, y: sy))
                if abs(screenPoint.x - s.x) <= hitRadius
                    && abs(screenPoint.y - s.y) <= hitRadius {
                    return item.id
                }
            }
        }
        return nil
    }

    /// Snap a schematic point to the nearest grid intersection.
    private func snapToGrid(_ pt: CGPoint) -> CGPoint {
        CGPoint(
            x: (pt.x / gridMils).rounded() * gridMils,
            y: (pt.y / gridMils).rounded() * gridMils
        )
    }

    /// Point-to-segment distance for wire hit testing.
    private func distanceFromPoint(_ p: CGPoint,
                                   toSegment a: CGPoint,
                                   _ b: CGPoint) -> CGFloat {
        let dx = b.x - a.x
        let dy = b.y - a.y
        let lenSq = dx * dx + dy * dy
        guard lenSq > 0 else {
            return hypot(p.x - a.x, p.y - a.y)
        }
        let t = max(0, min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / lenSq))
        let projX = a.x + t * dx
        let projY = a.y + t * dy
        return hypot(p.x - projX, p.y - projY)
    }

    // MARK: - Pan gesture

    private var panGesture: some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                if !isDragging {
                    dragStart  = CGPoint(x: transform.offsetX,
                                        y: transform.offsetY)
                    isDragging = true
                }
                if activeTool == .select && selectedItemId == nil {
                    transform.offsetX = dragStart.x + value.translation.width
                    transform.offsetY = dragStart.y + value.translation.height
                }
                dragOffset = value.location
            }
            .onEnded { _ in isDragging = false }
    }
}

// MARK: - Keyboard shortcuts

extension SchematicEditorView {
    /// Call this from the window scene's `.commands {}` block.
    static func commands(bridge: KiCadSchEditBridge,
                         filePath: String?) -> some Commands {
        CommandGroup(replacing: .undoRedo) {
            Button("Undo") { bridge.undo() }
                .keyboardShortcut("z", modifiers: .command)
                .disabled(!bridge.canUndo)

            Button("Redo") { bridge.redo() }
                .keyboardShortcut("z", modifiers: [.command, .shift])
                .disabled(!bridge.canRedo)
        }
    }
}
