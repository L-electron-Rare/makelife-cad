import SwiftUI

// MARK: - DesignNote model

struct DesignNote: Identifiable, Codable {
    var id: UUID = UUID()
    var text: String
    var kind: NoteKind = .todo
    var componentRef: String = ""
    var resolved: Bool = false
    var createdAt: Date = Date()

    enum NoteKind: String, Codable, CaseIterable {
        case todo    = "TODO"
        case info    = "Info"
        case warning = "Warning"
        case bug     = "Bug"

        var icon: String {
            switch self {
            case .todo:    return "circle"
            case .info:    return "info.circle"
            case .warning: return "exclamationmark.triangle"
            case .bug:     return "ant.circle"
            }
        }

        var color: Color {
            switch self {
            case .todo:    return .primary
            case .info:    return .blue
            case .warning: return .orange
            case .bug:     return .red
            }
        }
    }
}

// MARK: - AnnotationsViewModel

@MainActor
final class AnnotationsViewModel: ObservableObject {
    @Published var notes: [DesignNote] = []

    private let storageKey = "makelife.design.annotations"

    init() { load() }

    func add(text: String, kind: DesignNote.NoteKind, ref: String = "") {
        notes.append(DesignNote(text: text, kind: kind, componentRef: ref))
        save()
    }

    func toggle(id: UUID) {
        guard let idx = notes.firstIndex(where: { $0.id == id }) else { return }
        notes[idx].resolved.toggle()
        save()
    }

    func delete(id: UUID) {
        notes.removeAll { $0.id == id }
        save()
    }

    func deleteResolved() {
        notes.removeAll(where: \.resolved)
        save()
    }

    // MARK: Persistence

    private func save() {
        guard let data = try? JSONEncoder().encode(notes) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([DesignNote].self, from: data)
        else { return }
        notes = decoded
    }
}

// MARK: - AnnotationsView

struct AnnotationsView: View {
    @StateObject private var vm = AnnotationsViewModel()

    @State private var newText = ""
    @State private var newKind: DesignNote.NoteKind = .todo
    @State private var newRef  = ""
    @State private var showResolved = false

    private var visible: [DesignNote] {
        vm.notes
            .filter { showResolved || !$0.resolved }
            .sorted { $0.createdAt > $1.createdAt }
    }

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider()
            if visible.isEmpty {
                emptyState
            } else {
                noteList
            }
            Divider()
            addBar
        }
        .frame(minWidth: 420, minHeight: 300)
        .navigationTitle("Design Notes")
    }

    // MARK: Header

    private var headerBar: some View {
        HStack(spacing: 6) {
            // Kind chips (open only)
            ForEach(DesignNote.NoteKind.allCases, id: \.self) { kind in
                let n = vm.notes.filter { $0.kind == kind && !$0.resolved }.count
                if n > 0 { kindChip(n, kind: kind) }
            }
            Spacer()
            Toggle("Resolved", isOn: $showResolved)
                .toggleStyle(.checkbox)
                .controlSize(.small)
            if vm.notes.contains(where: \.resolved) {
                Button("Clear resolved") { vm.deleteResolved() }
                    .buttonStyle(.borderless)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
    }

    // MARK: List

    private var noteList: some View {
        List(visible) { note in
            noteRow(note)
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) { vm.delete(id: note.id) } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
                .swipeActions(edge: .leading) {
                    Button { vm.toggle(id: note.id) } label: {
                        Label(note.resolved ? "Reopen" : "Resolve",
                              systemImage: note.resolved ? "arrow.uturn.backward" : "checkmark")
                    }
                    .tint(note.resolved ? .orange : .green)
                }
        }
        .listStyle(.inset)
    }

    private func noteRow(_ note: DesignNote) -> some View {
        HStack(spacing: 10) {
            Button {
                vm.toggle(id: note.id)
            } label: {
                Image(systemName: note.resolved
                      ? "checkmark.circle.fill"
                      : note.kind.icon)
                    .foregroundStyle(note.resolved ? Color.secondary : note.kind.color)
                    .frame(width: 18)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                Text(note.text)
                    .strikethrough(note.resolved)
                    .foregroundStyle(note.resolved ? Color.secondary : Color.primary)
                    .lineLimit(2)
                if !note.componentRef.isEmpty {
                    Text(note.componentRef)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            Text(note.kind.rawValue)
                .font(.caption.bold())
                .foregroundStyle(note.kind.color)
        }
        .padding(.vertical, 2)
    }

    // MARK: Add bar

    private var addBar: some View {
        HStack(spacing: 6) {
            Picker("", selection: $newKind) {
                ForEach(DesignNote.NoteKind.allCases, id: \.self) {
                    Text($0.rawValue).tag($0)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 95)
            .help("Note type")

            TextField("Ref", text: $newRef)
                .textFieldStyle(.roundedBorder)
                .frame(width: 75)
                .help("Component reference (optional)")

            TextField("Add note…", text: $newText)
                .textFieldStyle(.roundedBorder)
                .onSubmit { commit() }

            Button(action: commit) {
                Image(systemName: "plus.circle.fill")
                    .foregroundStyle(newText.isEmpty ? Color.secondary : Color.accentColor)
            }
            .buttonStyle(.plain)
            .disabled(newText.isEmpty)
        }
        .padding(10)
    }

    // MARK: Empty state

    private var emptyState: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: "note.text")
                .font(.system(size: 44))
                .foregroundStyle(.tertiary)
            Text(showResolved ? "No notes" : "No open notes")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("Add TODOs, warnings, and bugs to track design decisions")
                .font(.callout)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Helpers

    private func kindChip(_ count: Int, kind: DesignNote.NoteKind) -> some View {
        Text("\(count) \(kind.rawValue)")
            .font(.caption.bold())
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(kind.color.opacity(0.15))
            .foregroundStyle(kind.color)
            .clipShape(Capsule())
    }

    private func commit() {
        guard !newText.isEmpty else { return }
        vm.add(text: newText, kind: newKind, ref: newRef)
        newText = ""
        newRef  = ""
    }
}
