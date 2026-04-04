import SwiftUI
import AppKit

// MARK: - NewProjectView

/// Sheet for creating a new FineFab/KiCad project from scratch.
/// Scaffolds the standard structure and optionally runs `git init` and `gh repo create`.
struct NewProjectView: View {
    @Environment(\.dismiss) private var dismiss

    /// Called with the URL of the generated `.kicad_pro` file when the user taps "Open Project".
    let onOpen: (URL) -> Void

    // ── Form fields ──────────────────────────────────────────────────────────
    @State private var repoName        = ""
    @State private var boardName       = ""
    @State private var boardNameEdited = false
    @State private var destination: URL? = defaultDestination
    @State private var gitInit         = true
    @State private var createGH        = false
    @State private var ghVisibility    = NewProjectScaffolder.RepoVisibility.private
    @State private var ghOrg           = ""

    // ── Progress ─────────────────────────────────────────────────────────────
    private enum Phase { case form, creating, done }
    @State private var phase: Phase    = .form
    @State private var log             = ""
    @State private var errorMessage: String?
    @State private var createdProURL: URL?

    // ── Default destination: ~/Documents ─────────────────────────────────────
    private static var defaultDestination: URL? {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            switch phase {
            case .form:     formBody
            case .creating: creatingBody
            case .done:     doneBody
            }
        }
        .frame(width: 560, height: 500)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "folder.badge.plus")
                .font(.title2)
                .foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 2) {
                Text("New Project")
                    .font(.headline)
                Text("Scaffold a KiCad project with the FineFab structure")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    // MARK: - Form

    private var formBody: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {

                    // ── Names & location ──────────────────────────────────────
                    GroupBox("Project") {
                        VStack(alignment: .leading, spacing: 10) {
                            FieldRow(label: "Repo name") {
                                TextField("e.g. my-pcb-project", text: $repoName)
                                    .onChange(of: repoName) { _, v in
                                        if !boardNameEdited { boardName = v }
                                    }
                            }
                            FieldRow(label: "Board name") {
                                TextField("e.g. MainBoard", text: $boardName)
                                    .onChange(of: boardName) { _, _ in
                                        boardNameEdited = true
                                    }
                            }
                            FieldRow(label: "Location") {
                                HStack {
                                    Text(destination?.abbreviatingWithTildeInPath ?? "—")
                                        .font(.system(.caption, design: .monospaced))
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                        .foregroundStyle(.secondary)
                                    Spacer(minLength: 4)
                                    Button("Choose…") { pickDestination() }
                                        .controlSize(.mini)
                                        .buttonStyle(.bordered)
                                }
                            }
                        }
                        .padding(.vertical, 8)
                        .padding(.horizontal, 4)
                    }

                    // ── Structure preview ─────────────────────────────────────
                    GroupBox("Structure") {
                        Text(structurePreview)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                    }

                    // ── Git ───────────────────────────────────────────────────
                    GroupBox("Git") {
                        VStack(alignment: .leading, spacing: 10) {
                            Toggle("Initialize git repository (git init + initial commit)", isOn: $gitInit)

                            if gitInit {
                                Divider().padding(.vertical, 2)

                                Toggle("Create GitHub repository (requires gh CLI)", isOn: $createGH)

                                if createGH {
                                    Picker("Visibility", selection: $ghVisibility) {
                                        Text("Private").tag(NewProjectScaffolder.RepoVisibility.private)
                                        Text("Public").tag(NewProjectScaffolder.RepoVisibility.public)
                                    }
                                    .pickerStyle(.segmented)
                                    .frame(maxWidth: 220)

                                    FieldRow(label: "GitHub org") {
                                        TextField("Empty = personal account", text: $ghOrg)
                                    }
                                }
                            }
                        }
                        .padding(.vertical, 8)
                        .padding(.horizontal, 4)
                    }
                }
                .padding(20)
            }

            Divider()

            // ── Action buttons ────────────────────────────────────────────────
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.escape, modifiers: [])
                Button("Create Project") { createProject() }
                    .keyboardShortcut(.return, modifiers: .command)
                    .buttonStyle(.borderedProminent)
                    .disabled(!canCreate)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
    }

    // MARK: - Creating

    private var creatingBody: some View {
        VStack(spacing: 20) {
            Spacer()
            ProgressView()
                .scaleEffect(1.4)
            Text("Creating project structure…")
                .font(.headline)
            if !log.isEmpty {
                ScrollView {
                    Text(log)
                        .font(.system(.caption2, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                }
                .frame(height: 150)
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .padding(.horizontal, 20)
            }
            Spacer()
        }
    }

    // MARK: - Done

    private var doneBody: some View {
        VStack(spacing: 16) {
            Spacer()

            if let err = errorMessage {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(.red)
                Text("Failed to create project")
                    .font(.headline)
                Text(err)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                if !log.isEmpty {
                    ScrollView {
                        Text(log)
                            .font(.system(.caption2, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                    }
                    .frame(height: 120)
                    .background(Color(nsColor: .textBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .padding(.horizontal, 20)
                }
                Button("Close") { dismiss() }
                    .controlSize(.large)

            } else {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(.green)
                Text("Project Created")
                    .font(.headline)
                if let url = createdProURL {
                    Text(url.path.replacingOccurrences(
                        of: NSHomeDirectory(), with: "~"))
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }
                Button("Open Project") {
                    if let url = createdProURL {
                        onOpen(url)
                        dismiss()
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.return, modifiers: [])

                Button("Close") { dismiss() }
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
    }

    // MARK: - Logic

    private var canCreate: Bool {
        !repoName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !boardName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        destination != nil
    }

    private var structurePreview: String {
        let r = repoName.isEmpty  ? "<repo>"  : repoName
        let b = boardName.isEmpty ? "<board>" : boardName
        return """
        \(r)/
        ├── .gitignore
        ├── .github/workflows/ci.yml
        ├── hardware/
        │   ├── pcb/\(b)/
        │   │   ├── \(b).kicad_pro
        │   │   ├── \(b).kicad_sch
        │   │   ├── \(b).kicad_pcb
        │   │   └── library/
        │   ├── simulation/
        │   └── bom/
        ├── firmware/
        ├── docs/
        └── fabrication/
        """
    }

    private func pickDestination() {
        let panel = NSOpenPanel()
        panel.title = "Choose destination folder"
        panel.message = "The project folder will be created inside this location."
        panel.canChooseFiles        = false
        panel.canChooseDirectories  = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories  = true
        if let current = destination { panel.directoryURL = current }
        if panel.runModal() == .OK { destination = panel.url }
    }

    private func createProject() {
        guard let dest = destination else { return }
        let scaffolder = NewProjectScaffolder(
            repoName:          repoName.trimmingCharacters(in: .whitespacesAndNewlines),
            boardName:         boardName.trimmingCharacters(in: .whitespacesAndNewlines),
            destination:       dest,
            gitInit:           gitInit,
            createGitHubRepo:  createGH,
            repoVisibility:    ghVisibility,
            ghOrg:             ghOrg.trimmingCharacters(in: .whitespacesAndNewlines)
        )

        phase = .creating
        log   = ""

        Task.detached(priority: .userInitiated) {
            do {
                let result = try scaffolder.scaffold()
                await MainActor.run {
                    self.log            = result.log
                    self.createdProURL  = result.projectFileURL
                    self.errorMessage   = nil
                    self.phase          = .done
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.phase        = .done
                }
            }
        }
    }
}

// MARK: - FieldRow

/// A label + content row used inside GroupBox in NewProjectView.
private struct FieldRow<Content: View>: View {
    let label: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 78, alignment: .trailing)
            content()
        }
    }
}

// MARK: - URL helper

private extension URL {
    var abbreviatingWithTildeInPath: String {
        path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
    }
}
