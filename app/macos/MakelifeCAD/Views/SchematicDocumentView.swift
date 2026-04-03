import SwiftUI

// MARK: - Modèle 3 — standalone schematic window
// Each window owns its own KiCadBridge, enabling multiple projects open simultaneously.

struct SchematicDocumentView: View {
    let fileURL: URL

    @StateObject private var bridge   = KiCadBridge()
    @State private var selectedComponent: SchematicComponent?

    var body: some View {
        NavigationSplitView {
            ComponentList(bridge: bridge, selectedComponent: $selectedComponent)
        } detail: {
            SchematicView(bridge: bridge, selectedComponent: $selectedComponent)
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
            try? bridge.openSchematic(path: fileURL.path)
            if accessing { fileURL.stopAccessingSecurityScopedResource() }
        }
        .onDisappear { bridge.close() }
    }

    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button {
                bridge.close()
                let accessing = fileURL.startAccessingSecurityScopedResource()
                try? bridge.openSchematic(path: fileURL.path)
                if accessing { fileURL.stopAccessingSecurityScopedResource() }
            } label: {
                Label("Reload", systemImage: "arrow.clockwise")
            }
            .help("Reload schematic from disk")
            .disabled(!bridge.isLoaded)
        }
    }
}
