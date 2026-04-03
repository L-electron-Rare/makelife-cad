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

// MARK: - Bridge errors

enum KiCadBridgeError: Error, LocalizedError {
    case fileNotFound(String)
    case parseError(String)
    case renderError

    var errorDescription: String? {
        switch self {
        case .fileNotFound(let p): return "File not found: \(p)"
        case .parseError(let p):   return "Parse error: \(p)"
        case .renderError:         return "SVG render failed"
        }
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

    private var handle: OpaquePointer?  // KicadSch*

    // MARK: - Public API

    func openSchematic(path: String) throws {
        close()
        guard FileManager.default.fileExists(atPath: path) else {
            throw KiCadBridgeError.fileNotFound(path)
        }
        guard let h = kicad_sch_open(path) else {
            throw KiCadBridgeError.parseError(path)
        }
        handle = OpaquePointer(h)
        try loadComponents()
        try loadSVG()
        isLoaded = true
        errorMessage = nil
    }

    /// Run ERC checks and return the parsed violations.
    /// The result is cached by the C bridge until the handle is closed.
    func runERC() -> [DRCViolation] {
        guard let h = handle else { return [] }
        guard let jsonPtr = kicad_run_erc_json(UnsafeMutablePointer(h)) else { return [] }
        let data = Data(bytesNoCopy: UnsafeMutableRawPointer(mutating: jsonPtr),
                        count: strlen(jsonPtr),
                        deallocator: .none)
        return (try? JSONDecoder().decode([DRCViolation].self, from: data)) ?? []
    }

    func close() {
        guard let h = handle else { return }
        kicad_sch_close(UnsafeMutablePointer(h))
        handle = nil
        components = []
        svgContent = ""
        isLoaded = false
    }

    // MARK: - Private loaders

    private func loadComponents() throws {
        guard let h = handle else { return }
        guard let jsonPtr = kicad_sch_get_components_json(UnsafeMutablePointer(h)) else {
            throw KiCadBridgeError.parseError("components JSON")
        }
        let data = Data(bytesNoCopy: UnsafeMutableRawPointer(mutating: jsonPtr),
                        count: strlen(jsonPtr),
                        deallocator: .none)
        components = try JSONDecoder().decode([SchematicComponent].self, from: data)
    }

    private func loadSVG() throws {
        guard let h = handle else { return }
        guard let svgPtr = kicad_sch_render_svg(UnsafeMutablePointer(h)) else {
            throw KiCadBridgeError.renderError
        }
        svgContent = String(cString: svgPtr)
    }
}
