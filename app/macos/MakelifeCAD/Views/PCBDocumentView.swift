import SwiftUI

// MARK: - Modèle 3 — standalone PCB window

struct PCBDocumentView: View {
    let fileURL: URL

    @StateObject private var bridge = KiCadPCBBridge()
    @State private var activeLayerId: Int?
    @State private var selectedFootprint: PCBFootprint?
    @State private var show3D = false

    var body: some View {
        NavigationSplitView {
            LayerPanel(bridge: bridge,
                       activeLayerId: $activeLayerId,
                       selectedFootprint: $selectedFootprint)
        } detail: {
            Group {
                if show3D {
                    PCB3DView(bridge: bridge)
                } else {
                    PCBView(bridge: bridge, activeLayerId: $activeLayerId)
                }
            }
            .toolbar { toolbarItems }
        }
        .navigationTitle(fileURL.deletingPathExtension().lastPathComponent)
        .frame(minWidth: 760, minHeight: 500)
        .alert("Error", isPresented: .constant(bridge.errorMessage != nil)) {
            Button("OK") { }
        } message: {
            Text(bridge.errorMessage ?? "")
        }
        .onAppear {
            let accessing = fileURL.startAccessingSecurityScopedResource()
            try? bridge.openPCB(path: fileURL.path)
            if accessing { fileURL.stopAccessingSecurityScopedResource() }
        }
        .onDisappear { bridge.closePCB() }
    }

    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        ToolbarItem {
            Button {
                show3D.toggle()
            } label: {
                Label(show3D ? "PCB" : "3D", systemImage: show3D ? "cpu" : "view.3d")
            }
            .help(show3D ? "Switch to PCB view" : "Switch to 3D view")
            .disabled(!bridge.isLoaded)
        }

        ToolbarItem(placement: .primaryAction) {
            Button {
                bridge.closePCB()
                let accessing = fileURL.startAccessingSecurityScopedResource()
                try? bridge.openPCB(path: fileURL.path)
                if accessing { fileURL.stopAccessingSecurityScopedResource() }
            } label: {
                Label("Reload", systemImage: "arrow.clockwise")
            }
            .help("Reload PCB from disk")
            .disabled(!bridge.isLoaded)
        }
    }
}
