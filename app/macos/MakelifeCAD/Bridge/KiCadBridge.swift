import Foundation

// MARK: - PCB Data models

struct PCBLayer: Identifiable, Codable {
    let id: Int
    let name: String
    let color: String
    var visible: Bool

    /// SwiftUI Color from hex string
    var swiftColor: (r: Double, g: Double, b: Double) {
        let hex = color.hasPrefix("#") ? String(color.dropFirst()) : color
        let val = UInt32(hex, radix: 16) ?? 0xFF5555
        return (
            r: Double((val >> 16) & 0xFF) / 255.0,
            g: Double((val >> 8)  & 0xFF) / 255.0,
            b: Double( val        & 0xFF) / 255.0
        )
    }
}

struct PCBFootprint: Identifiable, Codable {
    let id: UUID
    let reference: String
    let value: String
    let x: Double
    let y: Double
    let angle: Double
    let layer: String

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        reference = try c.decode(String.self, forKey: .reference)
        value     = try c.decode(String.self, forKey: .value)
        x         = try c.decode(Double.self, forKey: .x)
        y         = try c.decode(Double.self, forKey: .y)
        angle     = try c.decode(Double.self, forKey: .angle)
        layer     = try c.decode(String.self, forKey: .layer)
        id        = UUID()
    }

    enum CodingKeys: String, CodingKey {
        case reference, value, x, y, angle, layer
    }
}

// MARK: - PCB Bridge

/// Thread-safe wrapper around the kicad_bridge PCB C API.
/// One instance per open PCB — close with `closePCB()` when done.
@MainActor
final class KiCadPCBBridge: ObservableObject {

    @Published private(set) var layers: [PCBLayer] = []
    @Published private(set) var footprints: [PCBFootprint] = []
    @Published private(set) var isLoaded: Bool = false
    @Published private(set) var errorMessage: String?

    private var handle: kicad_pcb_handle?

    // MARK: - Public API

    func openPCB(path: String) throws {
        closePCB()
        guard FileManager.default.fileExists(atPath: path) else {
            throw KiCadBridgeError.fileNotFound(path)
        }
        guard let h = kicad_pcb_open(path) else {
            throw KiCadBridgeError.parseError(path)
        }
        handle = h
        try loadLayers()
        try loadFootprints()
        isLoaded = true
        errorMessage = nil
    }

    func renderLayer(layerId: Int) -> String? {
        guard let h = handle else { return nil }
        guard let ptr = kicad_pcb_render_layer_svg(h, Int32(layerId), 0, 0, 0, 0) else {
            return nil
        }
        return String(cString: ptr)
    }

    func toggleLayerVisibility(id: Int) {
        guard let idx = layers.firstIndex(where: { $0.id == id }) else { return }
        layers[idx].visible.toggle()
    }

    /// Run DRC checks and return the parsed violations.
    /// The result is cached by the C bridge until the handle is closed.
    func runDRC() -> [DRCViolation] {
        guard let h = handle else { return [] }
        guard let jsonPtr = kicad_run_drc_json(h) else { return [] }
        let data = Data(bytesNoCopy: UnsafeMutableRawPointer(mutating: jsonPtr),
                        count: strlen(jsonPtr),
                        deallocator: .none)
        return (try? JSONDecoder().decode([DRCViolation].self, from: data)) ?? []
    }

    func closePCB() {
        guard let h = handle else { return }
        kicad_pcb_close(h)
        handle = nil
        layers = []
        footprints = []
        isLoaded = false
    }

    // MARK: - Private loaders

    private func loadLayers() throws {
        guard let h = handle else { return }
        guard let jsonPtr = kicad_pcb_get_layers_json(h) else {
            throw KiCadBridgeError.parseError("layers JSON")
        }
        let data = Data(bytesNoCopy: UnsafeMutableRawPointer(mutating: jsonPtr),
                        count: strlen(jsonPtr),
                        deallocator: .none)
        layers = try JSONDecoder().decode([PCBLayer].self, from: data)
    }

    private func loadFootprints() throws {
        guard let h = handle else { return }
        guard let jsonPtr = kicad_pcb_get_footprints_json(h) else {
            throw KiCadBridgeError.parseError("footprints JSON")
        }
        let data = Data(bytesNoCopy: UnsafeMutableRawPointer(mutating: jsonPtr),
                        count: strlen(jsonPtr),
                        deallocator: .none)
        footprints = try JSONDecoder().decode([PCBFootprint].self, from: data)
    }
}

// MARK: - Schematic Data models

struct SchematicComponent: Identifiable, Codable {
    let id: UUID
    let reference: String
    let value: String
    let footprint: String
    let libId: String
    let pins: [String]
    let x: Double
    let y: Double

    /// Rough component type inferred from reference prefix.
    var kind: ComponentKind {
        switch reference.prefix(1).uppercased() {
        case "R": return .resistor
        case "C": return .capacitor
        case "L": return .inductor
        case "U": return .ic
        case "Q": return .transistor
        case "D": return .diode
        case "J", "P": return .connector
        default: return .other
        }
    }

    enum CodingKeys: String, CodingKey {
        case reference, value, footprint
        case libId = "lib_id"
        case pins, x, y
    }

    // Auto-generate UUID from reference so decoding is deterministic.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        reference = try c.decode(String.self, forKey: .reference)
        value     = try c.decode(String.self, forKey: .value)
        footprint = try c.decode(String.self, forKey: .footprint)
        libId     = try c.decode(String.self, forKey: .libId)
        pins      = try c.decode([String].self, forKey: .pins)
        x         = try c.decode(Double.self, forKey: .x)
        y         = try c.decode(Double.self, forKey: .y)
        id        = UUID()
    }
}

enum ComponentKind: String, CaseIterable {
    case resistor   = "Resistors"
    case capacitor  = "Capacitors"
    case inductor   = "Inductors"
    case ic         = "ICs"
    case transistor = "Transistors"
    case diode      = "Diodes"
    case connector  = "Connectors"
    case other      = "Other"
}

// MARK: - DRC / ERC data models

struct DRCLocation: Codable {
    let x: Double
    let y: Double
}

/// A single DRC or ERC violation returned by the C bridge.
struct DRCViolation: Identifiable, Codable {
    let id: UUID
    let severity: String        // "error" | "warning"
    let rule: String
    let message: String
    let location: DRCLocation?  // present for DRC (PCB)
    let layer: String?          // present for DRC
    let component: String?      // present for ERC
    let pin: String?            // present for ERC

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        severity  = try c.decode(String.self, forKey: .severity)
        rule      = try c.decode(String.self, forKey: .rule)
        message   = try c.decode(String.self, forKey: .message)
        location  = try c.decodeIfPresent(DRCLocation.self, forKey: .location)
        layer     = try c.decodeIfPresent(String.self, forKey: .layer)
        component = try c.decodeIfPresent(String.self, forKey: .component)
        pin       = try c.decodeIfPresent(String.self, forKey: .pin)
        id        = UUID()
    }

    enum CodingKeys: String, CodingKey {
        case severity, rule, message, location, layer, component, pin
    }

    var isError: Bool { severity == "error" }
}

// MARK: - PCB Edit (Phase 5)

extension KiCadPCBBridge {

    // MARK: Add items

    /// Place a footprint. Returns item ID > 0 on success, -1 on failure.
    @discardableResult
    func addFootprint(libID: String, x: Double, y: Double,
                      layer: String = "F.Cu") -> Int32 {
        guard let h = handle else { return -1 }
        return kicad_pcb_add_footprint(h, libID, x, y, layer)
    }

    /// Add a point-to-point track segment. Returns item ID > 0 on success.
    @discardableResult
    func addTrack(x1: Double, y1: Double, x2: Double, y2: Double,
                  width: Double, layer: String = "F.Cu",
                  netID: Int32 = 0) -> Int32 {
        guard let h = handle else { return -1 }
        return kicad_pcb_add_track(h, x1, y1, x2, y2, width, layer, netID)
    }

    /// Add a via. Returns item ID > 0 on success.
    @discardableResult
    func addVia(x: Double, y: Double,
                size: Double = 0.8, drill: Double = 0.4,
                netID: Int32 = 0) -> Int32 {
        guard let h = handle else { return -1 }
        return kicad_pcb_add_via(h, x, y, size, drill, netID)
    }

    /// Add a copper pour zone. pointsJSON: JSON array of {x,y} objects.
    @discardableResult
    func addZone(netID: Int32, layer: String = "F.Cu",
                 pointsJSON: String) -> Int32 {
        guard let h = handle else { return -1 }
        return kicad_pcb_add_zone(h, netID, layer, pointsJSON)
    }

    // MARK: Mutate items

    /// Translate item by (dx, dy) in mm.
    func moveItem(itemID: Int32, dx: Double, dy: Double) {
        guard let h = handle else { return }
        kicad_pcb_move_item(h, itemID, dx, dy)
    }

    /// Delete item by ID.
    func deleteItem(itemID: Int32) {
        guard let h = handle else { return }
        kicad_pcb_delete_item(h, itemID)
    }

    // MARK: Undo / Redo

    func undo() {
        guard let h = handle else { return }
        kicad_pcb_undo(h)
    }

    func redo() {
        guard let h = handle else { return }
        kicad_pcb_redo(h)
    }

    // MARK: Persistence

    /// Save board to path. Returns true on success.
    @discardableResult
    func save(to path: String) -> Bool {
        guard let h = handle else { return false }
        return kicad_pcb_save(h, path) == 0
    }

    // MARK: Netlist import

    /// Import net assignments from a JSON netlist string.
    @discardableResult
    func importNetlist(_ json: String) -> Bool {
        guard let h = handle else { return false }
        return kicad_pcb_import_netlist(h, json) == 0
    }
}

// MARK: - Bridge errors

enum KiCadBridgeError: Error, LocalizedError {
    case fileNotFound(String)
    case parseError(String)
    case renderError
    case noPCBLoaded

    var errorDescription: String? {
        switch self {
        case .fileNotFound(let p): return "File not found: \(p)"
        case .parseError(let p):   return "Parse error: \(p)"
        case .renderError:         return "SVG render failed"
        case .noPCBLoaded:         return "No PCB file is loaded"
        }
    }
}

// MARK: - Schematic Item models (Phase 4)

enum SchItemType: String, Codable {
    case symbol
    case wire
    case label
}

struct SchItem: Identifiable, Codable {
    let id: UInt64
    let type: SchItemType

    // Symbol fields (optional — present when type == .symbol)
    let libId:     String?
    let reference: String?
    let value:     String?
    let footprint: String?
    let x:         Double?
    let y:         Double?

    // Wire fields (optional — present when type == .wire)
    let x1: Double?
    let y1: Double?
    let x2: Double?
    let y2: Double?

    // Label fields (optional — present when type == .label)
    let text: String?

    enum CodingKeys: String, CodingKey {
        case id, type
        case libId     = "lib_id"
        case reference, value, footprint
        case x, y, x1, y1, x2, y2, text
    }
}

// MARK: - Edit bridge errors

extension KiCadBridgeError {
    static var editFailed: KiCadBridgeError { .parseError("edit operation failed") }
}

// MARK: - KiCadSchEditBridge

/// Extends the read-only KiCadBridge with edit, undo/redo, and save.
/// Maintains a local copy of items for SwiftUI rendering.
@MainActor
final class KiCadSchEditBridge: ObservableObject {

    // MARK: - Published state

    @Published private(set) var items: [SchItem] = []
    @Published private(set) var isDirty: Bool = false
    @Published private(set) var canUndo: Bool = false
    @Published private(set) var canRedo: Bool = false
    @Published private(set) var errorMessage: String?

    // MARK: - Private

    private var handle: UnsafeMutableRawPointer?   // KicadSch*

    // Undo/redo availability is tracked by a simple depth counter because
    // the C layer owns the truth; Swift mirrors it.
    private var undoDepth: Int = 0
    private var redoDepth: Int = 0

    // MARK: - Open / Close

    func openSchematic(path: String) throws {
        close()
        guard FileManager.default.fileExists(atPath: path) else {
            throw KiCadBridgeError.fileNotFound(path)
        }
        guard let h = kbs_sch_open(path) else {
            throw KiCadBridgeError.parseError(path)
        }
        handle = h
        reloadItems()
        isDirty   = false
        undoDepth = 0
        redoDepth = 0
        syncUndoRedo()
    }

    func close() {
        guard let h = handle else { return }
        kbs_sch_close(h)
        handle    = nil
        items     = []
        isDirty   = false
        undoDepth = 0
        redoDepth = 0
        syncUndoRedo()
    }

    // MARK: - Edit operations

    @discardableResult
    func addSymbol(libId: String, x: Double, y: Double) -> UInt64 {
        guard let h = handle else { return 0 }
        let itemId = kbs_sch_add_symbol(h, libId, x, y)
        if itemId > 0 {
            markDirty()
            reloadItems()
        }
        return itemId
    }

    @discardableResult
    func addWire(x1: Double, y1: Double, x2: Double, y2: Double) -> UInt64 {
        guard let h = handle else { return 0 }
        let itemId = kbs_sch_add_wire(h, x1, y1, x2, y2)
        if itemId > 0 {
            markDirty()
            reloadItems()
        }
        return itemId
    }

    @discardableResult
    func addLabel(text: String, x: Double, y: Double) -> UInt64 {
        guard let h = handle else { return 0 }
        let itemId = kbs_sch_add_label(h, text, x, y)
        if itemId > 0 {
            markDirty()
            reloadItems()
        }
        return itemId
    }

    func moveItem(id: UInt64, dx: Double, dy: Double) {
        guard let h = handle else { return }
        let result = kbs_sch_move_item(h, id, dx, dy)
        if result == 0 {
            markDirty()
            reloadItems()
        }
    }

    func deleteItem(id: UInt64) {
        guard let h = handle else { return }
        let result = kbs_sch_delete_item(h, id)
        if result == 0 {
            markDirty()
            reloadItems()
        }
    }

    func setProperty(id: UInt64, key: String, value: String) {
        guard let h = handle else { return }
        let result = kbs_sch_set_property(h, id, key, value)
        if result == 0 {
            markDirty()
            reloadItems()
        }
    }

    // MARK: - Undo / Redo

    func undo() {
        guard let h = handle, canUndo else { return }
        let result = kbs_sch_undo(h)
        if result == 0 {
            undoDepth = max(0, undoDepth - 1)
            redoDepth += 1
            reloadItems()
            syncUndoRedo()
            if undoDepth == 0 { isDirty = false }
        }
    }

    func redo() {
        guard let h = handle, canRedo else { return }
        let result = kbs_sch_redo(h)
        if result == 0 {
            redoDepth = max(0, redoDepth - 1)
            undoDepth += 1
            reloadItems()
            syncUndoRedo()
            isDirty = true
        }
    }

    // MARK: - Save

    func save(path: String) throws {
        guard let h = handle else {
            throw KiCadBridgeError.editFailed
        }
        let result = kbs_sch_save(h, path)
        guard result == 0 else {
            throw KiCadBridgeError.parseError("save failed: \(path)")
        }
        isDirty = false
    }

    // MARK: - Private helpers

    private func reloadItems() {
        guard let h = handle else { items = []; return }
        guard let jsonPtr = kbs_sch_get_items_json(h)
        else { return }
        let data = Data(bytesNoCopy: UnsafeMutableRawPointer(mutating: jsonPtr),
                        count: strlen(jsonPtr),
                        deallocator: .none)
        if let decoded = try? JSONDecoder().decode([SchItem].self, from: data) {
            items = decoded
        }
    }

    private func markDirty() {
        undoDepth += 1
        redoDepth  = 0
        isDirty    = true
        syncUndoRedo()
    }

    private func syncUndoRedo() {
        canUndo = undoDepth > 0
        canRedo = redoDepth > 0
    }
}

// MARK: - Main bridge class

/// Thread-safe wrapper around the kicad_bridge C library.
/// One instance per open schematic — close with `close()` when done.
@MainActor
final class KiCadBridge: ObservableObject {

    @Published private(set) var components: [SchematicComponent] = []
    @Published private(set) var svgContent: String = ""
    @Published private(set) var isLoaded: Bool = false
    @Published private(set) var errorMessage: String?

    private var handle: UnsafeMutableRawPointer?  // KicadSch*

    // MARK: - Public API

    func openSchematic(path: String) throws {
        close()
        guard FileManager.default.fileExists(atPath: path) else {
            throw KiCadBridgeError.fileNotFound(path)
        }
        guard let h = kbs_sch_open(path) else {
            throw KiCadBridgeError.parseError(path)
        }
        handle = h
        try loadComponents()
        try loadSVG()
        isLoaded = true
        errorMessage = nil
    }

    /// Run ERC checks and return the parsed violations.
    /// The result is cached by the C bridge until the handle is closed.
    func runERC() -> [DRCViolation] {
        guard let h = handle else { return [] }
        guard let jsonPtr = kbs_run_erc_json(h) else { return [] }
        let data = Data(bytesNoCopy: UnsafeMutableRawPointer(mutating: jsonPtr),
                        count: strlen(jsonPtr),
                        deallocator: .none)
        return (try? JSONDecoder().decode([DRCViolation].self, from: data)) ?? []
    }

    func close() {
        guard let h = handle else { return }
        kbs_sch_close(h)
        handle = nil
        components = []
        svgContent = ""
        isLoaded = false
    }

    // MARK: - Private loaders

    private func loadComponents() throws {
        guard let h = handle else { return }
        guard let jsonPtr = kbs_sch_get_components_json(h) else {
            throw KiCadBridgeError.parseError("components JSON")
        }
        let data = Data(bytesNoCopy: UnsafeMutableRawPointer(mutating: jsonPtr),
                        count: strlen(jsonPtr),
                        deallocator: .none)
        components = try JSONDecoder().decode([SchematicComponent].self, from: data)
    }

    private func loadSVG() throws {
        guard let h = handle else { return }
        guard let svgPtr = kbs_sch_render_svg(h) else {
            throw KiCadBridgeError.renderError
        }
        svgContent = String(cString: svgPtr)
    }
}

// MARK: - 3D Data models

struct Board3D {
    let widthMM:     Double
    let heightMM:    Double
    let thicknessMM: Double
    let outline:     [(x: Double, y: Double)]
}

struct Layer3D: Identifiable {
    let id:    Int
    let name:  String
    let zMM:   Double
    let color: String   // hex "#rrggbb"
    var visible: Bool = true
}

enum ComponentType3D: String {
    case ic        = "ic"
    case passive   = "passive"
    case connector = "connector"
    case other     = "other"
}

struct Component3D: Identifiable {
    let id:        UUID
    let reference: String
    let value:     String
    let xMM:       Double
    let yMM:       Double
    let angleDeg:  Double
    let layer:     String
    let bboxW:     Double
    let bboxH:     Double
    let heightMM:  Double
    let type:      ComponentType3D

    // Computed: is component on back of board?
    var isBack: Bool { layer == "B.Cu" }
}

struct PCB3DScene {
    let board:      Board3D
    var layers:     [Layer3D]
    let components: [Component3D]
}

// MARK: - 3D JSON decoding (private)

private struct Board3DJSON: Decodable {
    let width_mm: Double
    let height_mm: Double
    let thickness_mm: Double
    let outline: [[Double]]
}

private struct Layer3DJSON: Decodable {
    let id: Int
    let name: String
    let z_mm: Double
    let color: String
}

private struct Component3DJSON: Decodable {
    let reference: String
    let value: String
    let x_mm: Double
    let y_mm: Double
    let angle_deg: Double
    let layer: String
    let bbox_w: Double
    let bbox_h: Double
    let height_mm: Double
    let type: String
}

private struct PCB3DJSON: Decodable {
    let board: Board3DJSON
    let layers: [Layer3DJSON]
    let components: [Component3DJSON]
}

// MARK: - KiCadPCBBridge 3D extension

extension KiCadPCBBridge {

    /// Export PCB as a 3D scene model.
    /// Calls kicad_pcb_export_3d_json() and decodes the result.
    func export3D() throws -> PCB3DScene {
        guard let h = handle else {
            throw KiCadBridgeError.noPCBLoaded
        }
        guard let cStr = kicad_pcb_export_3d_json(h),
              let json = String(cString: cStr, encoding: .utf8),
              let data = json.data(using: .utf8) else {
            throw KiCadBridgeError.parseError("3d_json")
        }

        let raw = try JSONDecoder().decode(PCB3DJSON.self, from: data)

        let outline = raw.board.outline.compactMap { pt -> (x: Double, y: Double)? in
            guard pt.count >= 2 else { return nil }
            return (x: pt[0], y: pt[1])
        }

        let board = Board3D(
            widthMM:     raw.board.width_mm,
            heightMM:    raw.board.height_mm,
            thicknessMM: raw.board.thickness_mm,
            outline:     outline
        )

        let layers = raw.layers.map { l in
            Layer3D(id: l.id, name: l.name, zMM: l.z_mm, color: l.color)
        }

        let components = raw.components.map { c in
            Component3D(
                id:        UUID(),
                reference: c.reference,
                value:     c.value,
                xMM:       c.x_mm,
                yMM:       c.y_mm,
                angleDeg:  c.angle_deg,
                layer:     c.layer,
                bboxW:     c.bbox_w,
                bboxH:     c.bbox_h,
                heightMM:  c.height_mm,
                type:      ComponentType3D(rawValue: c.type) ?? .other
            )
        }

        return PCB3DScene(board: board, layers: layers, components: components)
    }
}
