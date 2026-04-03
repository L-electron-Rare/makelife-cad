import SwiftUI
import SceneKit
import AppKit

// MARK: - PCB3DView (SwiftUI wrapper)

/// 3D PCB viewer powered by SceneKit.
/// Receives a PCB3DScene from the bridge and renders it as a SceneKit scene.
struct PCB3DView: View {
    @ObservedObject var bridge: KiCadPCBBridge

    @State private var scene:             PCB3DScene?
    @State private var layers:            [Layer3D]      = []
    @State private var selectedComponent: Component3D?   = nil
    @State private var errorMessage:      String?        = nil
    @State private var scnScene:          SCNScene?      = nil
    @State private var isTransparent:     Bool           = false

    var body: some View {
        ZStack {
            Color(red: 0.08, green: 0.08, blue: 0.12)
                .ignoresSafeArea()

            if let scnScene {
                HStack(spacing: 0) {
                    // 3D viewport
                    PCBSceneKitView(
                        scene:             scnScene,
                        selectedComponent: selectedComponent
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    Divider()

                    // Right sidebar — layer toggles + component info
                    LayerStack3DPanel(
                        layers:            $layers,
                        selectedComponent: $selectedComponent,
                        isTransparent:     $isTransparent,
                        onLayerToggle:     { rebuildScene() }
                    )
                    .frame(width: 220)
                }
            } else if let errorMessage {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundStyle(.orange)
                    Text(errorMessage)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding()
            } else if bridge.isLoaded {
                ProgressView("Building 3D scene\u{2026}")
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "view.3d")
                        .font(.system(size: 48))
                        .foregroundStyle(.tertiary)
                    Text("Open a .kicad_pcb file to view in 3D")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .onChange(of: bridge.isLoaded) { _, loaded in
            if loaded { buildScene() } else { clearScene() }
        }
        .onAppear {
            if bridge.isLoaded { buildScene() }
        }
    }

    // MARK: - Scene lifecycle

    private func buildScene() {
        do {
            let s = try bridge.export3D()
            scene  = s
            layers = s.layers
            rebuildScene()
        } catch {
            errorMessage = "3D export failed: \(error.localizedDescription)"
        }
    }

    private func rebuildScene() {
        guard let s = scene else { return }
        let visibleLayerIds = Set(layers.filter(\.visible).map(\.id))
        scnScene = PCBSceneBuilder.build(
            scene:         s,
            visibleLayers: visibleLayerIds,
            isTransparent: isTransparent,
            selectedRef:   selectedComponent?.reference
        )
    }

    private func clearScene() {
        scene             = nil
        layers            = []
        scnScene          = nil
        errorMessage      = nil
        selectedComponent = nil
    }
}

// MARK: - PCBSceneKitView (NSViewRepresentable)

private struct PCBSceneKitView: NSViewRepresentable {
    let scene:             SCNScene
    let selectedComponent: Component3D?

    func makeNSView(context: Context) -> SCNView {
        let v = SCNView()
        v.scene                     = scene
        v.allowsCameraControl       = true   // orbit, zoom, pan via mouse drag + scroll
        v.autoenablesDefaultLighting = true
        v.backgroundColor           = NSColor(red: 0.08, green: 0.08, blue: 0.12, alpha: 1)
        v.antialiasingMode          = .multisampling4X
        return v
    }

    func updateNSView(_ nsView: SCNView, context: Context) {
        nsView.scene = scene
        if let ref = selectedComponent?.reference {
            highlightNode(named: ref, in: nsView)
        } else {
            clearHighlights(in: nsView)
        }
    }

    private func highlightNode(named ref: String, in view: SCNView) {
        view.scene?.rootNode.enumerateChildNodes { node, _ in
            if node.name == ref {
                node.geometry?.firstMaterial?.emission.contents = NSColor.yellow.withAlphaComponent(0.4)
            } else {
                node.geometry?.firstMaterial?.emission.contents = NSColor.black
            }
        }
    }

    private func clearHighlights(in view: SCNView) {
        view.scene?.rootNode.enumerateChildNodes { node, _ in
            node.geometry?.firstMaterial?.emission.contents = NSColor.black
        }
    }
}

// MARK: - PCBSceneBuilder

/// Pure factory — builds an SCNScene from a PCB3DScene.
/// No SwiftUI state. Can be called off-main for large boards if needed.
enum PCBSceneBuilder {

    static func build(
        scene:         PCB3DScene,
        visibleLayers: Set<Int>,
        isTransparent: Bool,
        selectedRef:   String?
    ) -> SCNScene {
        let root  = SCNScene()
        let board = scene.board

        // -- Board substrate (green PCB) --
        addBoard(to: root.rootNode, board: board, isTransparent: isTransparent)

        // -- Copper / silkscreen layers --
        for layer in scene.layers where visibleLayers.contains(layer.id) {
            addLayerPlane(to: root.rootNode, layer: layer, board: board, isTransparent: isTransparent)
        }

        // -- Components --
        for comp in scene.components {
            addComponent(to: root.rootNode, comp: comp, selectedRef: selectedRef, isTransparent: isTransparent)
        }

        // -- Camera --
        let cameraNode = SCNNode()
        cameraNode.camera = SCNCamera()
        let diag = max(board.widthMM, board.heightMM)
        cameraNode.position = SCNVector3(
            Float(board.widthMM  / 2),
            Float(diag * 0.7),
            Float(board.heightMM / 2 + diag * 0.8)
        )
        cameraNode.look(at: SCNVector3(
            Float(board.widthMM  / 2),
            0,
            Float(board.heightMM / 2)
        ))
        root.rootNode.addChildNode(cameraNode)

        // -- Lights --
        let ambient = SCNNode()
        ambient.light       = SCNLight()
        ambient.light!.type = .ambient
        ambient.light!.color = NSColor(white: 0.5, alpha: 1)
        root.rootNode.addChildNode(ambient)

        let omni = SCNNode()
        omni.light       = SCNLight()
        omni.light!.type = .omni
        omni.light!.color = NSColor(white: 0.8, alpha: 1)
        omni.position = SCNVector3(
            Float(board.widthMM),
            Float(diag * 1.2),
            Float(board.heightMM)
        )
        root.rootNode.addChildNode(omni)

        return root
    }

    // MARK: - Board substrate

    private static func addBoard(to parent: SCNNode, board: Board3D, isTransparent: Bool) {
        let box = SCNBox(
            width:         CGFloat(board.widthMM),
            height:        CGFloat(board.thicknessMM),
            length:        CGFloat(board.heightMM),
            chamferRadius: 0.2
        )
        let mat = SCNMaterial()
        mat.diffuse.contents = NSColor(red: 0.05, green: 0.40, blue: 0.05,
                                       alpha: isTransparent ? 0.4 : 1.0)
        mat.isDoubleSided    = false
        box.materials        = [mat]

        let node      = SCNNode(geometry: box)
        node.name     = "__board__"
        node.position = SCNVector3(
            Float(board.widthMM  / 2),
            Float(-board.thicknessMM / 2),
            Float(board.heightMM / 2)
        )
        parent.addChildNode(node)
    }

    // MARK: - Layer planes

    private static func addLayerPlane(
        to parent: SCNNode,
        layer: Layer3D,
        board: Board3D,
        isTransparent: Bool
    ) {
        let plane = SCNPlane(
            width:  CGFloat(board.widthMM),
            height: CGFloat(board.heightMM)
        )
        let mat = SCNMaterial()
        let (r, g, b) = hexToRGB(layer.color)
        mat.diffuse.contents = NSColor(
            red:   r, green: g, blue: b,
            alpha: isTransparent ? 0.3 : 0.7
        )
        mat.isDoubleSided = true
        plane.materials   = [mat]

        let node = SCNNode(geometry: plane)
        node.name = "__layer_\(layer.id)__"
        // SCNPlane is in XY — rotate 90° around X to lie in XZ (horizontal)
        node.eulerAngles = SCNVector3(-Float.pi / 2, 0, 0)
        node.position    = SCNVector3(
            Float(board.widthMM  / 2),
            Float(layer.zMM),
            Float(board.heightMM / 2)
        )
        parent.addChildNode(node)
    }

    // MARK: - Component boxes

    private static func addComponent(
        to parent: SCNNode,
        comp: Component3D,
        selectedRef: String?,
        isTransparent: Bool
    ) {
        let box = SCNBox(
            width:         CGFloat(comp.bboxW),
            height:        CGFloat(comp.heightMM),
            length:        CGFloat(comp.bboxH),
            chamferRadius: comp.type == .ic ? 0.1 : 0.05
        )
        let mat = SCNMaterial()
        mat.diffuse.contents = componentColor(for: comp.type, isBack: comp.isBack,
                                              alpha: isTransparent ? 0.6 : 1.0)
        if selectedRef == comp.reference {
            mat.emission.contents = NSColor.yellow.withAlphaComponent(0.4)
        }
        mat.isDoubleSided = false
        box.materials = [mat]

        let baseZ: Double = comp.isBack ? -comp.heightMM / 2 : (1.6 + comp.heightMM / 2)

        let node      = SCNNode(geometry: box)
        node.name     = comp.reference
        node.position = SCNVector3(
            Float(comp.xMM),
            Float(baseZ),
            Float(comp.yMM)
        )
        // Apply rotation around Y axis (KiCad angle is in degrees, CCW)
        node.eulerAngles = SCNVector3(0, Float(comp.angleDeg * Double.pi / 180.0), 0)

        // Label on top face for ICs and connectors
        if comp.type == .ic || comp.type == .connector {
            addLabel(ref: comp.reference, to: node, comp: comp)
        }

        parent.addChildNode(node)
    }

    private static func addLabel(ref: String, to node: SCNNode, comp: Component3D) {
        let text       = SCNText(string: ref, extrusionDepth: 0.05)
        text.font      = NSFont.monospacedSystemFont(
            ofSize: CGFloat(min(comp.bboxW, comp.bboxH) * 0.35),
            weight: .medium
        )
        text.flatness  = 0.1
        let labelMat   = SCNMaterial()
        labelMat.diffuse.contents = NSColor.white
        text.materials = [labelMat]

        let labelNode = SCNNode(geometry: text)
        let (minVec, maxVec) = node.boundingBox
        let w = maxVec.x - minVec.x
        labelNode.position = SCNVector3(-w * 0.4, Float(comp.heightMM / 2 + 0.01), 0)
        labelNode.scale    = SCNVector3(0.5, 0.5, 0.5)
        node.addChildNode(labelNode)
    }

    // MARK: - Color helpers

    private static func componentColor(for type: ComponentType3D, isBack: Bool, alpha: Double) -> NSColor {
        switch type {
        case .ic:
            return NSColor(red: 0.15, green: 0.15, blue: 0.20, alpha: alpha)
        case .passive:
            return isBack
                ? NSColor(red: 0.55, green: 0.35, blue: 0.10, alpha: alpha)
                : NSColor(red: 0.75, green: 0.60, blue: 0.20, alpha: alpha)
        case .connector:
            return NSColor(red: 0.10, green: 0.35, blue: 0.10, alpha: alpha)
        case .other:
            return NSColor(red: 0.40, green: 0.40, blue: 0.45, alpha: alpha)
        }
    }

    private static func hexToRGB(_ hex: String) -> (CGFloat, CGFloat, CGFloat) {
        let h = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        let v = UInt32(h, radix: 16) ?? 0x888888
        return (
            CGFloat((v >> 16) & 0xFF) / 255.0,
            CGFloat((v >>  8) & 0xFF) / 255.0,
            CGFloat( v        & 0xFF) / 255.0
        )
    }
}
