import SwiftUI
import WebKit

// MARK: - Fab layer color mapping

private struct FabLayer {
    let pcbLayer: PCBLayer
    let fabColor: String    // CSS hex
    let blendMode: String   // CSS mix-blend-mode
    let opacity: Double
}

/// Map KiCad layer names to standard PCB fab visualization colors.
private func fabColor(for layer: PCBLayer) -> (color: String, blend: String, opacity: Double) {
    let name = layer.name
    if name.contains("Cu")     { return ("#ff8800", "screen",   0.90) }
    if name.contains("SilkS")  { return ("#ffffff", "screen",   0.85) }
    if name.contains("Mask")   { return ("#22aa44", "multiply", 0.55) }
    if name.contains("Paste")  { return ("#cccccc", "screen",   0.40) }
    if name.contains("Edge")   { return ("#ffff00", "screen",   1.00) }
    if name.contains("Fab")    { return ("#8888ff", "screen",   0.50) }
    if name.contains("Courtyard") { return ("#ff44ff", "screen", 0.40) }
    // fallback: use the layer's own color
    let c = layer.swiftColor
    let hex = String(format: "#%02x%02x%02x",
                     Int(c.r * 255), Int(c.g * 255), Int(c.b * 255))
    return (hex, "screen", 0.70)
}

// MARK: - FabPreviewView

struct FabPreviewView: View {
    @EnvironmentObject var pcbBridge: KiCadPCBBridge

    @State private var showLegend = true
    @State private var boardStyle: BoardStyle = .classicGreen

    enum BoardStyle: String, CaseIterable {
        case classicGreen = "Classic (Green)"
        case darkMatte    = "Dark Matte"
        case white        = "White PCB"

        var bgColor: String {
            switch self {
            case .classicGreen: return "#1a4d1a"
            case .darkMatte:    return "#0d0d0d"
            case .white:        return "#e8e8e0"
            }
        }
    }

    var body: some View {
        if !pcbBridge.isLoaded {
            emptyState
        } else {
            HSplitView {
                FabWebView(bridge: pcbBridge, bgColor: boardStyle.bgColor)
                if showLegend {
                    legendPanel
                        .frame(minWidth: 160, idealWidth: 180, maxWidth: 200)
                }
            }
            .frame(minWidth: 600, minHeight: 400)
            .toolbar { toolbarItems }
            .navigationTitle("Fab Preview")
        }
    }

    // MARK: Empty state

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "cpu")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)
            Text("No PCB loaded")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("Open a .kicad_pcb file first")
                .font(.callout)
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Legend panel

    private var legendPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Layers")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .padding(.bottom, 6)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(pcbBridge.layers.filter(\.visible)) { layer in
                        let fab = fabColor(for: layer)
                        HStack(spacing: 8) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color(hex: fab.color) ?? .gray)
                                .frame(width: 14, height: 14)
                            Text(layer.name)
                                .font(.caption)
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 2)
                    }
                }
                .padding(.vertical, 8)
            }
            Divider()
            Picker("Style", selection: $boardStyle) {
                ForEach(BoardStyle.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.menu)
            .padding(10)
        }
        .background(.ultraThinMaterial)
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        ToolbarItem {
            Button { showLegend.toggle() } label: {
                Label("Legend", systemImage: showLegend ? "sidebar.right" : "sidebar.right")
            }
            .help("Toggle layer legend")
        }
    }
}

// MARK: - FabWebView

private struct FabWebView: NSViewRepresentable {
    @ObservedObject var bridge: KiCadPCBBridge
    let bgColor: String

    func makeNSView(context: Context) -> WKWebView {
        let wv = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        wv.setValue(false, forKey: "drawsBackground")
        return wv
    }

    func updateNSView(_ wv: WKWebView, context: Context) {
        guard bridge.isLoaded else { return }
        let layers = bridge.layers.filter(\.visible)
        var layerData: [(color: String, blend: String, opacity: Double, svg: String)] = []
        for layer in layers {
            if let svg = bridge.renderLayer(layerId: layer.id) {
                let fab = fabColor(for: layer)
                layerData.append((fab.color, fab.blend, fab.opacity, svg))
            }
        }
        wv.loadHTMLString(buildFabHTML(layers: layerData, bg: bgColor), baseURL: nil)
    }

    private func buildFabHTML(
        layers: [(color: String, blend: String, opacity: Double, svg: String)],
        bg: String
    ) -> String {
        let imgs = layers.map { l -> String in
            let encoded = (l.svg.data(using: .utf8)?.base64EncodedString()) ?? ""
            let uri = "data:image/svg+xml;base64,\(encoded)"
            return """
            <img src="\(uri)"
                 style="position:absolute;top:0;left:0;width:100%;height:100%;
                        object-fit:contain;
                        mix-blend-mode:\(l.blend);
                        opacity:\(l.opacity);
                        filter:drop-shadow(0 0 2px \(l.color));">
            """
        }.joined(separator: "\n")

        return """
        <!DOCTYPE html>
        <html>
        <head><meta charset="utf-8">
        <style>
          * { margin:0; padding:0; box-sizing:border-box; }
          body { background:\(bg); overflow:hidden; width:100vw; height:100vh; }
          .stage {
            width:100%; height:100%;
            display:flex; align-items:center; justify-content:center;
            cursor:grab; position:relative;
          }
          .stage:active { cursor:grabbing; }
          .stack { position:relative; width:88vw; height:88vh; }
          .stack img { pointer-events:none; }
        </style>
        </head>
        <body>
        <div class="stage" id="s"><div class="stack" id="k">\(imgs)</div></div>
        <script>
        let sc=1,tx=0,ty=0,drag=false,lx=0,ly=0;
        const s=document.getElementById('s'),k=document.getElementById('k');
        function apply(){ k.style.transform=`translate(${tx}px,${ty}px) scale(${sc})`; k.style.transformOrigin='50% 50%'; }
        s.addEventListener('wheel',e=>{ e.preventDefault(); sc=Math.min(50,Math.max(0.05,sc*(e.deltaY>0?0.88:1.14))); apply(); },{passive:false});
        s.addEventListener('mousedown',e=>{ drag=true; lx=e.clientX; ly=e.clientY; });
        window.addEventListener('mousemove',e=>{ if(!drag)return; tx+=e.clientX-lx; ty+=e.clientY-ly; lx=e.clientX; ly=e.clientY; apply(); });
        window.addEventListener('mouseup',()=>{ drag=false; });
        s.addEventListener('dblclick',()=>{ sc=1;tx=0;ty=0;apply(); });
        </script>
        </body></html>
        """
    }
}

// MARK: - Color+hex helper

private extension Color {
    init?(hex: String) {
        let h = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard h.count == 6, let val = UInt64(h, radix: 16) else { return nil }
        self.init(
            red:   Double((val >> 16) & 0xFF) / 255,
            green: Double((val >> 8)  & 0xFF) / 255,
            blue:  Double( val        & 0xFF) / 255
        )
    }
}
