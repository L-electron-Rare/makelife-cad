import SwiftUI
import UniformTypeIdentifiers

// MARK: - Project panel

/// Sidebar panel that shows the current KiCad project tree.
/// When no project is open, it offers "Open Project…" and a recents list.
struct ProjectPanel: View {
    @ObservedObject var manager: YiacadProjectManager

    /// Called when the user wants to switch focus to the schematic tab.
    var onOpenSchematic: ((URL) -> Void)?
    /// Called when the user wants to switch focus to the PCB tab.
    var onOpenPCB: ((URL) -> Void)?
    /// Called when the user taps "Clone from GitHub…".
    var onCloneRequested: (() -> Void)?
    /// Called when the user taps "New Project…".
    var onNewProjectRequested: (() -> Void)?

    @State private var showImporter = false

    var body: some View {
        VStack(spacing: 0) {
            if let project = manager.currentProject {
                openProjectView(project)
            } else {
                noProjectView
            }
        }
        .frame(minWidth: 220, idealWidth: 260, maxWidth: 320)
    }

    // MARK: - Open project view

    @ViewBuilder
    private func openProjectView(_ project: KiCadProject) -> some View {
        // Header row
        HStack(spacing: 6) {
            Image(systemName: "folder.fill")
                .foregroundStyle(Color.accentColor)
            Text(project.name)
                .font(.headline)
                .lineLimit(1)
            Spacer()
            Button {
                manager.close()
            } label: {
                Image(systemName: "xmark.circle")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Close project")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)

        Divider()

        // File rows
        fileRow(
            label: "\(project.name).kicad_sch",
            systemImage: "doc.richtext",
            exists: project.hasSchematic,
            action: { onOpenSchematic?(project.schematicURL) }
        )
        fileRow(
            label: "\(project.name).kicad_pcb",
            systemImage: "cpu",
            exists: project.hasPCB,
            action: { onOpenPCB?(project.pcbURL) }
        )

        // Extra hierarchical sheets (if any beyond the root)
        let extraSheets = project.sheets.filter {
            !$0.hasSuffix(".kicad_sch") || $0 != "\(project.name).kicad_sch"
        }
        if !extraSheets.isEmpty {
            Divider().padding(.leading, 12)
            ForEach(extraSheets, id: \.self) { sheet in
                fileRow(
                    label: sheet,
                    systemImage: "doc.text",
                    exists: FileManager.default.fileExists(
                        atPath: project.rootURL.appendingPathComponent(sheet).path),
                    action: {
                        let url = project.rootURL.appendingPathComponent(sheet)
                        onOpenSchematic?(url)
                    }
                )
            }
        }

        Divider()
    }

    // MARK: - No project view

    private var noProjectView: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Image(systemName: "folder")
                    .foregroundStyle(.secondary)
                Text("No Project")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial)

            Divider()

            // Open button
            Button {
                showImporter = true
            } label: {
                Label("Open Project\u{2026}", systemImage: "folder.badge.plus")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.plain)
            .contentShape(Rectangle())

            // New Project button
            Button {
                onNewProjectRequested?()
            } label: {
                Label("New Project\u{2026}", systemImage: "plus.app")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.plain)
            .contentShape(Rectangle())

            // Clone from GitHub button
            Button {
                onCloneRequested?()
            } label: {
                Label("Clone from GitHub\u{2026}", systemImage: "arrow.down.to.line.compact")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.plain)
            .contentShape(Rectangle())

            // Recents
            if !manager.recentProjects.isEmpty {
                Divider()
                SectionTitle(label: "Recent", count: manager.recentProjects.count)

                ForEach(manager.recentProjects.prefix(6)) { project in
                    RecentRow(project: project) {
                        manager.open(url: project.url)
                    }
                }
            }
        }
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [kicadProType]
        ) { result in
            if case .success(let url) = result {
                let accessing = url.startAccessingSecurityScopedResource()
                defer { if accessing { url.stopAccessingSecurityScopedResource() } }
                manager.open(url: url)
            }
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private func fileRow(label: String, systemImage: String, exists: Bool,
                         action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .frame(width: 16)
                    .foregroundStyle(exists ? Color.accentColor : Color.secondary.opacity(0.4))
                Text(label)
                    .font(.system(.caption, design: .monospaced))
                    .lineLimit(1)
                    .foregroundStyle(exists ? .primary : .tertiary)
                Spacer()
                if !exists {
                    Text("missing")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!exists)
    }

    private var kicadProType: UTType {
        UTType(filenameExtension: "kicad_pro") ?? .data
    }
}

// MARK: - Sub-views

private struct SectionTitle: View {
    let label: String
    let count: Int

    var body: some View {
        HStack {
            Text(label.uppercased())
                .font(.caption2)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
            Spacer()
            Text("\(count)")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 2)
    }
}

private struct RecentRow: View {
    let project: YiacadProject
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 8) {
                Image(systemName: "clock")
                    .foregroundStyle(.secondary)
                    .frame(width: 16)
                VStack(alignment: .leading, spacing: 1) {
                    Text(project.name)
                        .font(.caption)
                        .lineLimit(1)
                    Text(project.rootURL.lastPathComponent)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
