import SwiftUI

// MARK: - App entry point

@main
struct MakelifeCADApp: App {

    @StateObject private var bridge = KiCadBridge()
    @State private var selectedComponent: SchematicComponent?
    @State private var showFileImporter = false

    var body: some Scene {
        WindowGroup {
            ContentView(
                bridge: bridge,
                selectedComponent: $selectedComponent,
                showFileImporter: $showFileImporter
            )
        }
        .commands {
            // File menu additions
            CommandGroup(replacing: .newItem) {
                Button("Open Schematic\u{2026}") {
                    showFileImporter = true
                }
                .keyboardShortcut("o", modifiers: .command)
            }
        }
    }
}

// MARK: - ContentView

struct ContentView: View {
    @ObservedObject var bridge: KiCadBridge
    @Binding var selectedComponent: SchematicComponent?
    @Binding var showFileImporter: Bool

    var body: some View {
        NavigationSplitView {
            ComponentList(bridge: bridge, selectedComponent: $selectedComponent)
        } detail: {
            SchematicView(bridge: bridge, selectedComponent: $selectedComponent)
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            showFileImporter = true
                        } label: {
                            Label("Open", systemImage: "folder.badge.plus")
                        }
                        .help("Open .kicad_sch file")
                    }
                    if bridge.isLoaded {
                        ToolbarItem {
                            Button {
                                bridge.close()
                                selectedComponent = nil
                            } label: {
                                Label("Close", systemImage: "xmark.circle")
                            }
                            .help("Close schematic")
                        }
                    }
                }
        }
        .navigationTitle("MakelifeCAD")
        .frame(minWidth: 900, minHeight: 600)
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.init(filenameExtension: "kicad_sch")!],
            allowsMultipleSelection: false
        ) { result in
            handleFileImport(result)
        }
        .alert("Error", isPresented: .constant(bridge.errorMessage != nil), actions: {
            Button("OK") { }
        }, message: {
            Text(bridge.errorMessage ?? "")
        })
    }

    private func handleFileImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            // Security-scoped resource access for sandboxed apps
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            do {
                try bridge.openSchematic(path: url.path)
            } catch {
                // errorMessage is set inside the bridge on failure; log here too
                print("[MakelifeCAD] open failed: \(error.localizedDescription)")
            }
        case .failure(let error):
            print("[MakelifeCAD] file import error: \(error.localizedDescription)")
        }
    }
}
