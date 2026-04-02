import SwiftUI
import WebKit

// MARK: - PCBView

/// Main PCB viewer — renders one or more layers as SVG via WKWebView.
struct PCBView: View {
    @ObservedObject var bridge: KiCadPCBBridge

    /// Which layer is currently rendered (nil = all visible layers composited)
    @Binding var activeLayerId: Int?

    var body: some View {
        ZStack {
            Color(red: 0.118, green: 0.118, blue: 0.180)
                .ignoresSafeArea()

            if bridge.isLoaded {
                PCBSVGWebView(bridge: bridge, activeLayerId: activeLayerId)
            } else if let err = bridge.errorMessage {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundStyle(.orange)
                    Text(err)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding()
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "cpu")
                        .font(.system(size: 48))
                        .foregroundStyle(.tertiary)
                    Text("Open a .kicad_pcb file to begin")
                        .foregroundStyle(.secondary)
                }
            }

            if !bridge.isLoaded {
                GridBackground()
            }
        }
    }
}

// MARK: - PCBSVGWebView

/// Renders PCB layers composited in a WKWebView with zoom/pan.
private struct PCBSVGWebView: NSViewRepresentable {
    @ObservedObject var bridge: KiCadPCBBridge
    let activeLayerId: Int?

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        guard bridge.isLoaded else { return }

        // Collect visible layers to render
        let visibleLayers: [PCBLayer]
        if let lid = activeLayerId {
            visibleLayers = bridge.layers.filter { $0.id == lid && $0.visible }
        } else {
            visibleLayers = bridge.layers.filter { $0.visible }
        }

        // Build composited SVG: one <g> per layer
        var compositedSVGs: [(color: String, svg: String)] = []
        for layer in visibleLayers {
            if let svg = bridge.renderLayer(layerId: layer.id) {
                compositedSVGs.append((color: layer.color, svg: svg))
            }
        }

        // Use the first SVG's viewBox for the container; overlay others
        let primarySVG = compositedSVGs.first?.svg ?? "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 150 100\"></svg>"

        let html = buildHTML(primarySVG: primarySVG,
                             layers: compositedSVGs)
        webView.loadHTMLString(html, baseURL: nil)
    }

    private func buildHTML(primarySVG: String,
                           layers: [(color: String, svg: String)]) -> String {
        // Each layer SVG is rendered as an <img> via data URI inside a composite view.
        // For simplicity and correctness, we render the last (topmost) layer's SVG directly
        // and overlay previous layers using CSS opacity.
        // Since each SVG has the same viewBox (same PCB coordinate space), they can stack.

        let svgDataURIs = layers.map { layer -> String in
            let encoded = layer.svg
                .data(using: .utf8)
                .map { $0.base64EncodedString() } ?? ""
            return "data:image/svg+xml;base64,\(encoded)"
        }

        let imgTags = svgDataURIs.map { uri in
            "<img src=\"\(uri)\" style=\"position:absolute;top:0;left:0;width:100%;height:100%;object-fit:contain;\">"
        }.joined(separator: "\n")

        return """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <style>
          * { margin: 0; padding: 0; box-sizing: border-box; }
          body { background: #1e1e2e; overflow: hidden; width: 100vw; height: 100vh; }
          .stage {
            width: 100%; height: 100%;
            display: flex; align-items: center; justify-content: center;
            cursor: grab;
            position: relative;
          }
          .stage:active { cursor: grabbing; }
          .layer-stack {
            position: relative;
            width: 90vw; height: 90vh;
          }
          .layer-stack img { pointer-events: none; }
        </style>
        </head>
        <body>
        <div class="stage" id="stage">
          <div class="layer-stack" id="stack">
            \(imgTags)
          </div>
        </div>
        <script>
        let scale = 1, tx = 0, ty = 0;
        let dragging = false, lastX = 0, lastY = 0;
        const stage = document.getElementById('stage');
        const stack = document.getElementById('stack');

        function applyTransform() {
          stack.style.transform = `translate(${tx}px, ${ty}px) scale(${scale})`;
          stack.style.transformOrigin = '50% 50%';
        }

        stage.addEventListener('wheel', e => {
          e.preventDefault();
          const delta = e.deltaY > 0 ? 0.9 : 1.1;
          scale = Math.min(50, Math.max(0.05, scale * delta));
          applyTransform();
        }, { passive: false });

        stage.addEventListener('mousedown', e => {
          dragging = true; lastX = e.clientX; lastY = e.clientY;
        });
        window.addEventListener('mousemove', e => {
          if (!dragging) return;
          tx += e.clientX - lastX; ty += e.clientY - lastY;
          lastX = e.clientX; lastY = e.clientY;
          applyTransform();
        });
        window.addEventListener('mouseup', () => { dragging = false; });
        // Double-click to reset
        stage.addEventListener('dblclick', () => {
          scale = 1; tx = 0; ty = 0; applyTransform();
        });
        </script>
        </body>
        </html>
        """
    }
}

// MARK: - Grid background (reused from SchematicView pattern)

private struct GridBackground: View {
    var body: some View {
        Canvas { ctx, size in
            let spacing: CGFloat = 24
            var path = Path()
            var x: CGFloat = 0
            while x <= size.width {
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
                x += spacing
            }
            var y: CGFloat = 0
            while y <= size.height {
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
                y += spacing
            }
            ctx.stroke(path, with: .color(.white.opacity(0.05)), lineWidth: 0.5)
        }
    }
}
