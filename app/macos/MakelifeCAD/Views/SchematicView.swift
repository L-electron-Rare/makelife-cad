import SwiftUI
import WebKit

// MARK: - WKWebView wrapper

/// NSViewRepresentable wrapping WKWebView for SVG display.
struct SVGWebView: NSViewRepresentable {
    let svgContent: String

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        guard !svgContent.isEmpty else { return }
        // Wrap SVG in minimal HTML with dark background + zoom/pan via JavaScript
        let html = """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <style>
          * { margin: 0; padding: 0; box-sizing: border-box; }
          body { background: #1e1e2e; overflow: hidden; width: 100vw; height: 100vh; }
          .container {
            width: 100%; height: 100%;
            display: flex; align-items: center; justify-content: center;
            cursor: grab;
          }
          .container:active { cursor: grabbing; }
          svg { max-width: 100%; max-height: 100%; }
          .component { cursor: pointer; }
          .component:hover circle { fill: #fab387; }
          .component:hover text { fill: #ffffff; }
        </style>
        </head>
        <body>
        <div class="container" id="container">
        \(svgContent)
        </div>
        <script>
        // Pan + zoom via mouse wheel and drag
        let scale = 1, tx = 0, ty = 0;
        let dragging = false, lastX = 0, lastY = 0;
        const container = document.getElementById('container');
        const svg = container.querySelector('svg');

        function applyTransform() {
          svg.style.transform = `translate(${tx}px, ${ty}px) scale(${scale})`;
          svg.style.transformOrigin = '50% 50%';
        }

        container.addEventListener('wheel', e => {
          e.preventDefault();
          const delta = e.deltaY > 0 ? 0.9 : 1.1;
          scale = Math.min(20, Math.max(0.1, scale * delta));
          applyTransform();
        }, { passive: false });

        container.addEventListener('mousedown', e => {
          dragging = true; lastX = e.clientX; lastY = e.clientY;
        });
        window.addEventListener('mousemove', e => {
          if (!dragging) return;
          tx += e.clientX - lastX; ty += e.clientY - lastY;
          lastX = e.clientX; lastY = e.clientY;
          applyTransform();
        });
        window.addEventListener('mouseup', () => { dragging = false; });
        </script>
        </body>
        </html>
        """
        webView.loadHTMLString(html, baseURL: nil)
    }
}

// MARK: - SchematicView

struct SchematicView: View {
    @ObservedObject var bridge: KiCadBridge
    @Binding var selectedComponent: SchematicComponent?

    var body: some View {
        ZStack {
            Color(red: 0.118, green: 0.118, blue: 0.180)  // Catppuccin Mocha base
                .ignoresSafeArea()

            if bridge.isLoaded && !bridge.svgContent.isEmpty {
                SVGWebView(svgContent: bridge.svgContent)
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
                    Image(systemName: "doc.badge.plus")
                        .font(.system(size: 48))
                        .foregroundStyle(.tertiary)
                    Text("Open a .kicad_sch file to begin")
                        .foregroundStyle(.secondary)
                }
            }

            // Grid overlay (only when empty)
            if !bridge.isLoaded {
                GridBackground()
            }

            // Rendering engine indicator (bottom-right)
            if bridge.isLoaded {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        renderingBadge
                    }
                }
                .padding(8)
            }
        }
    }

    @ViewBuilder
    private var renderingBadge: some View {
        let isNative = bridge.isNativeRendering
        HStack(spacing: 4) {
            Image(systemName: isNative ? "checkmark.seal.fill" : "gearshape")
                .font(.caption2)
            Text(isNative ? "KiCad \(bridge.nativeRenderer.kicadVersion)" : "Fallback")
                .font(.caption2)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isNative
                      ? Color.green.opacity(0.2)
                      : Color.orange.opacity(0.2))
        )
        .foregroundStyle(isNative ? .green : .orange)
        .help(isNative
              ? "Rendered by KiCad's native engine — pixel-perfect"
              : "Rendered by built-in engine — install KiCad for better quality")
    }
}

// MARK: - Grid background

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
