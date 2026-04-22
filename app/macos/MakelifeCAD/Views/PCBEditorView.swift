// makelife-cad/app/macos/MakelifeCAD/Views/PCBEditorView.swift
import SwiftUI

// MARK: - Tool selection

enum PCBTool: String, CaseIterable, Identifiable {
    case select    = "arrow.up.left"
    case track     = "line.diagonal"
    case via       = "circle"
    case footprint = "square.on.square"
    case zone      = "square.dashed"

    var id: String { rawValue }
    var label: String {
        switch self {
        case .select:    return "Select"
        case .track:     return "Track"
        case .via:       return "Via"
        case .footprint: return "Footprint"
        case .zone:      return "Zone"
        }
    }
}

// MARK: - Canvas item (render-side model)

struct PCBCanvasItem: Identifiable {
    let id: Int32         // = item_id from C bridge
    var type: Int         // PCB_ITEM_* constants mirrored
    var x, y: Double
    var x2, y2: Double
    var width: Double
    var layer: String
    var libID: String
    var selected: Bool
}

// MARK: - Edit operation log (for undo/redo)

enum PCBEditOp {
    case add(PCBCanvasItem)
    case delete(PCBCanvasItem)
    case move(itemID: Int32, dx: Double, dy: Double)
}

// MARK: - Editor ViewModel

@MainActor
final class PCBEditorViewModel: ObservableObject {
    var bridge: KiCadPCBBridge

    @Published var items: [PCBCanvasItem] = []
    @Published var selectedItemID: Int32? = nil
    @Published var activeTool: PCBTool = .select
    @Published var activeLayer: String = "F.Cu"
    @Published var trackWidth: Double = 0.25     // mm
    @Published var viaSize: Double   = 0.8       // mm
    @Published var viaDrill: Double  = 0.4       // mm
    @Published var activeNetID: Int32 = 0
    @Published var gridSize: Double  = 1.0       // mm
    @Published var showRatsnest: Bool = true
    @Published private(set) var canUndo: Bool = false
    @Published private(set) var canRedo: Bool = false

    // Track drawing state (nil when not drawing)
    var trackStart: CGPoint? = nil
    var zonePoints: [CGPoint] = []

    // Pixels per mm (canvas scale)
    var scale: Double = 4.0

    // Operation log for undo/redo
    private var undoStack: [PCBEditOp] = []
    private var redoStack: [PCBEditOp] = []

    init(bridge: KiCadPCBBridge) {
        self.bridge = bridge
    }

    private func pushUndo(_ op: PCBEditOp) {
        undoStack.append(op)
        redoStack.removeAll()
        syncUndoRedo()
    }

    private func syncUndoRedo() {
        canUndo = !undoStack.isEmpty
        canRedo = !redoStack.isEmpty
    }

    // MARK: Grid snap

    func snap(_ value: Double) -> Double {
        (value / gridSize).rounded() * gridSize
    }

    func snapPoint(_ p: CGPoint) -> CGPoint {
        CGPoint(x: snap(p.x / scale), y: snap(p.y / scale))
    }

    // MARK: Mutations → bridge + local model sync

    func addTrack(from start: CGPoint, to end: CGPoint) {
        let s = snapPoint(start)
        let e = snapPoint(end)
        let id = bridge.addTrack(x1: s.x, y1: s.y,
                                  x2: e.x, y2: e.y,
                                  width: trackWidth,
                                  layer: activeLayer,
                                  netID: activeNetID)
        if id > 0 {
            let item = PCBCanvasItem(
                id: id, type: 2,
                x: s.x, y: s.y, x2: e.x, y2: e.y,
                width: trackWidth, layer: activeLayer, libID: "", selected: false)
            items.append(item)
            pushUndo(.add(item))
        }
    }

    func addVia(at point: CGPoint) {
        let p = snapPoint(point)
        let id = bridge.addVia(x: p.x, y: p.y,
                                size: viaSize, drill: viaDrill,
                                netID: activeNetID)
        if id > 0 {
            let item = PCBCanvasItem(
                id: id, type: 3,
                x: p.x, y: p.y, x2: p.x, y2: p.y,
                width: viaSize, layer: activeLayer, libID: "", selected: false)
            items.append(item)
            pushUndo(.add(item))
        }
    }

    func addFootprint(libID: String, at point: CGPoint) {
        let p = snapPoint(point)
        let id = bridge.addFootprint(libID: libID, x: p.x, y: p.y,
                                      layer: activeLayer)
        if id > 0 {
            let item = PCBCanvasItem(
                id: id, type: 1,
                x: p.x, y: p.y, x2: p.x, y2: p.y,
                width: 1.0, layer: activeLayer, libID: libID, selected: false)
            items.append(item)
            pushUndo(.add(item))
        }
    }

    func commitZone() {
        guard zonePoints.count >= 3 else { zonePoints = []; return }
        let pts = zonePoints.map { p -> String in
            let sp = snapPoint(p)
            return "{\"x\":\(sp.x),\"y\":\(sp.y)}"
        }.joined(separator: ",")
        let json = "[\(pts)]"
        let id = bridge.addZone(netID: activeNetID,
                                 layer: activeLayer,
                                 pointsJSON: json)
        if id > 0 {
            let first = zonePoints.first.map { snapPoint($0) } ?? .zero
            let item = PCBCanvasItem(
                id: id, type: 4,
                x: first.x, y: first.y, x2: first.x, y2: first.y,
                width: 0, layer: activeLayer, libID: "", selected: false)
            items.append(item)
            pushUndo(.add(item))
        }
        zonePoints = []
    }

    func moveSelected(by delta: CGSize) {
        guard let selID = selectedItemID,
              let idx = items.firstIndex(where: { $0.id == selID }) else { return }
        let dx = delta.width  / scale
        let dy = delta.height / scale
        bridge.moveItem(itemID: selID, dx: dx, dy: dy)
        items[idx].x  += dx; items[idx].y  += dy
        items[idx].x2 += dx; items[idx].y2 += dy
        pushUndo(.move(itemID: selID, dx: dx, dy: dy))
    }

    func deleteSelected() {
        guard let selID = selectedItemID,
              let item = items.first(where: { $0.id == selID }) else { return }
        bridge.deleteItem(itemID: selID)
        items.removeAll { $0.id == selID }
        selectedItemID = nil
        pushUndo(.delete(item))
    }

    func undo() {
        guard let op = undoStack.popLast() else { return }
        bridge.undo()
        switch op {
        case .add(let item):
            items.removeAll { $0.id == item.id }
        case .delete(let item):
            items.append(item)
        case .move(let itemID, let dx, let dy):
            if let idx = items.firstIndex(where: { $0.id == itemID }) {
                items[idx].x  -= dx; items[idx].y  -= dy
                items[idx].x2 -= dx; items[idx].y2 -= dy
            }
        }
        redoStack.append(op)
        selectedItemID = nil
        syncUndoRedo()
    }

    func redo() {
        guard let op = redoStack.popLast() else { return }
        bridge.redo()
        switch op {
        case .add(let item):
            items.append(item)
        case .delete(let item):
            items.removeAll { $0.id == item.id }
        case .move(let itemID, let dx, let dy):
            if let idx = items.firstIndex(where: { $0.id == itemID }) {
                items[idx].x  += dx; items[idx].y  += dy
                items[idx].x2 += dx; items[idx].y2 += dy
            }
        }
        undoStack.append(op)
        syncUndoRedo()
    }

    func save(to path: String) {
        _ = bridge.save(to: path)
    }
}

// MARK: - Canvas renderer

struct PCBCanvasRenderer: View {
    @ObservedObject var vm: PCBEditorViewModel
    var trackPreviewEnd: CGPoint?

    var body: some View {
        Canvas { ctx, size in
            // Background
            ctx.fill(Path(CGRect(origin: .zero, size: size)),
                     with: .color(Color(red: 0.08, green: 0.10, blue: 0.12)))

            // Grid dots
            drawGrid(ctx: ctx, size: size)

            // Items
            for item in vm.items {
                drawItem(ctx: ctx, item: item)
            }

            // Track preview while drawing
            if vm.activeTool == .track,
               let start = vm.trackStart,
               let end = trackPreviewEnd {
                var p = Path()
                p.move(to: canvasPoint(x: start.x, y: start.y))
                p.addLine(to: end)
                ctx.stroke(p, with: .color(.orange.opacity(0.8)),
                           style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
            }

            // Zone preview
            if vm.activeTool == .zone && vm.zonePoints.count >= 2 {
                var p = Path()
                p.move(to: vm.zonePoints[0])
                for pt in vm.zonePoints.dropFirst() { p.addLine(to: pt) }
                ctx.stroke(p, with: .color(.yellow.opacity(0.6)),
                           style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
            }
        }
    }

    private func canvasPoint(x: Double, y: Double) -> CGPoint {
        CGPoint(x: x * vm.scale, y: y * vm.scale)
    }

    private func drawGrid(ctx: GraphicsContext, size: CGSize) {
        let step = vm.gridSize * vm.scale
        guard step >= 4 else { return }
        var x = 0.0
        while x < size.width {
            var y = 0.0
            while y < size.height {
                ctx.fill(Path(ellipseIn: CGRect(x: x - 0.5, y: y - 0.5,
                                                width: 1, height: 1)),
                         with: .color(.white.opacity(0.15)))
                y += step
            }
            x += step
        }
    }

    private func layerColor(_ layer: String) -> Color {
        switch layer {
        case "F.Cu":    return Color(red: 0.8, green: 0.2, blue: 0.2)
        case "B.Cu":    return Color(red: 0.2, green: 0.5, blue: 0.9)
        case "F.SilkS": return Color(red: 0.9, green: 0.9, blue: 0.9)
        default:        return .green
        }
    }

    private func drawItem(ctx: GraphicsContext, item: PCBCanvasItem) {
        let color = item.selected
            ? Color.yellow
            : layerColor(item.layer)
        let lw   = max(1.0, item.width * vm.scale)

        switch item.type {
        case 1: // footprint
            let rect = CGRect(
                x: item.x * vm.scale - lw / 2,
                y: item.y * vm.scale - lw / 2,
                width: lw, height: lw)
            ctx.stroke(Path(rect), with: .color(color),
                       style: StrokeStyle(lineWidth: 1.5))
            ctx.draw(
                Text(item.libID.components(separatedBy: ":").last ?? "")
                    .font(.system(size: 8)).foregroundColor(color),
                at: CGPoint(x: item.x * vm.scale + lw / 2 + 2,
                            y: item.y * vm.scale))

        case 2: // track
            var p = Path()
            p.move(to: CGPoint(x: item.x * vm.scale, y: item.y * vm.scale))
            p.addLine(to: CGPoint(x: item.x2 * vm.scale, y: item.y2 * vm.scale))
            ctx.stroke(p, with: .color(color),
                       style: StrokeStyle(lineWidth: lw, lineCap: .round))

        case 3: // via
            let r = lw / 2
            let ellipse = CGRect(
                x: item.x * vm.scale - r,
                y: item.y * vm.scale - r,
                width: lw, height: lw)
            ctx.fill(Path(ellipseIn: ellipse), with: .color(color))
            let drillR = item.width * 0.25 * vm.scale
            let hole = CGRect(
                x: item.x * vm.scale - drillR,
                y: item.y * vm.scale - drillR,
                width: drillR * 2, height: drillR * 2)
            ctx.fill(Path(ellipseIn: hole),
                     with: .color(Color(red: 0.08, green: 0.10, blue: 0.12)))

        case 4: // zone placeholder
            let zoneRect = CGRect(
                x: item.x * vm.scale - 5, y: item.y * vm.scale - 5,
                width: 10, height: 10)
            ctx.fill(Path(zoneRect), with: .color(color.opacity(0.3)))

        default: break
        }
    }
}

// MARK: - Main PCBEditorView

struct PCBEditorView: View {
    @StateObject var vm: PCBEditorViewModel
    @State private var trackPreviewEnd: CGPoint? = nil
    @State private var dragOffset: CGSize = .zero
    @State private var footprintToPlace: String? = nil

    var body: some View {
        HStack(spacing: 0) {
            // Toolbar (left)
            PCBToolbar(vm: vm)
                .frame(width: 44)
                .background(Color(nsColor: .windowBackgroundColor))

            // Canvas
            ZStack {
                PCBCanvasRenderer(vm: vm, trackPreviewEnd: trackPreviewEnd)
                    .gesture(canvasGesture)
                    .onHover { hovering in
                        if !hovering { trackPreviewEnd = nil }
                    }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Inspector (right)
            PCBInspectorPanel(vm: vm)
                .frame(width: 220)
                .background(Color(nsColor: .windowBackgroundColor))
        }
        .onReceive(NotificationCenter.default.publisher(
            for: .footprintDropped)) { notif in
            footprintToPlace = notif.object as? String
        }
    }

    // MARK: Gesture routing

    private var canvasGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                switch vm.activeTool {
                case .select:
                    if vm.selectedItemID != nil {
                        dragOffset = value.translation
                    } else {
                        trackPreviewEnd = value.location
                    }
                case .track:
                    if vm.trackStart == nil {
                        vm.trackStart = value.startLocation
                    }
                    trackPreviewEnd = value.location
                case .zone:
                    break // zone uses tap
                default:
                    break
                }
            }
            .onEnded { value in
                switch vm.activeTool {
                case .select:
                    if vm.selectedItemID != nil && dragOffset != .zero {
                        vm.moveSelected(by: dragOffset)
                    } else {
                        selectItem(at: value.location)
                    }
                    dragOffset = .zero

                case .track:
                    if let start = vm.trackStart {
                        vm.addTrack(from: start, to: value.location)
                        vm.trackStart = value.location // chain tracks
                        trackPreviewEnd = nil
                    }

                case .via:
                    vm.addVia(at: value.location)

                case .footprint:
                    if let libID = footprintToPlace {
                        vm.addFootprint(libID: libID, at: value.location)
                    }

                case .zone:
                    vm.zonePoints.append(value.location)
                }
            }
    }

    private func selectItem(at point: CGPoint) {
        let threshold = 8.0 // pixels
        for item in vm.items {
            let cx = item.x * vm.scale
            let cy = item.y * vm.scale
            let dist = sqrt(pow(point.x - cx, 2) + pow(point.y - cy, 2))
            if dist < threshold {
                vm.selectedItemID = item.id
                return
            }
        }
        vm.selectedItemID = nil
    }
}

// MARK: - Notification

extension Notification.Name {
    static let footprintDropped = Notification.Name("footprintDropped")
}
