import SwiftUI

// MARK: - Palette item

struct PaletteItem: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String
    let icon: String
    let category: String
    var badge: String? = nil
    var isDestructive: Bool = false
    let action: () -> Void
}

// MARK: - CommandPaletteView

struct CommandPaletteView: View {
    let items: [PaletteItem]
    @Binding var isPresented: Bool

    @State private var query = ""
    @State private var highlighted: PaletteItem.ID?
    @FocusState private var searchFocused: Bool

    // MARK: Filtering

    private var filtered: [PaletteItem] {
        guard !query.isEmpty else { return items }
        let q = query.lowercased()
        return items.filter {
            $0.title.lowercased().contains(q)
            || $0.subtitle.lowercased().contains(q)
            || $0.category.lowercased().contains(q)
        }
    }

    private var sections: [(category: String, items: [PaletteItem])] {
        var order: [String] = []
        var seen = Set<String>()
        for item in filtered {
            if seen.insert(item.category).inserted { order.append(item.category) }
        }
        return order.map { cat in (cat, filtered.filter { $0.category == cat }) }
    }

    // MARK: Body

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            Divider()
            resultList
            Divider()
            hintBar
        }
        .frame(width: 580, height: 420)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.35), radius: 28, y: 10)
        .onAppear {
            searchFocused = true
            highlighted = filtered.first?.id
        }
        .onChange(of: query) { _, _ in
            highlighted = filtered.first?.id
        }
    }

    // MARK: Search bar

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .font(.title3)
            TextField("Search commands, components, layers…", text: $query)
                .textFieldStyle(.plain)
                .font(.title3)
                .focused($searchFocused)
                .onSubmit { executeHighlighted() }
                .onKeyPress(.upArrow)   { navigate(-1); return .handled }
                .onKeyPress(.downArrow) { navigate( 1); return .handled }
                .onKeyPress(.escape)    { isPresented = false; return .handled }
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: Result list

    @ViewBuilder
    private var resultList: some View {
        if filtered.isEmpty {
            Spacer()
            VStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 32))
                    .foregroundStyle(.tertiary)
                Text("No results for \"\(query)\"")
                    .foregroundStyle(.secondary)
            }
            Spacer()
        } else {
            ScrollViewReader { proxy in
                List(selection: $highlighted) {
                    ForEach(sections, id: \.category) { section in
                        Section(section.category) {
                            ForEach(section.items) { item in
                                itemRow(item)
                                    .tag(item.id)
                                    .onTapGesture { execute(item) }
                            }
                        }
                    }
                }
                .listStyle(.inset)
                .onChange(of: highlighted) {
                    if let id = highlighted { proxy.scrollTo(id) }
                }
            }
        }
    }

    private func itemRow(_ item: PaletteItem) -> some View {
        HStack(spacing: 10) {
            Image(systemName: item.icon)
                .frame(width: 22)
                .foregroundStyle(item.isDestructive ? .red : Color.accentColor)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.title)
                    .font(.callout)
                    .foregroundStyle(item.isDestructive ? .red : .primary)
                if !item.subtitle.isEmpty {
                    Text(item.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if let badge = item.badge {
                Text(badge)
                    .font(.caption2.bold())
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.accentColor.opacity(0.15))
                    .clipShape(Capsule())
                    .foregroundStyle(Color.accentColor)
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }

    // MARK: Hint bar

    private var hintBar: some View {
        HStack(spacing: 16) {
            hintChip("↵", "Select")
            hintChip("↑↓", "Navigate")
            hintChip("⎋", "Close")
            if !filtered.isEmpty {
                Spacer()
                Text("\(filtered.count) result\(filtered.count == 1 ? "" : "s")")
                    .font(.caption2)
                    .foregroundStyle(.quaternary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
    }

    private func hintChip(_ key: String, _ label: String) -> some View {
        HStack(spacing: 4) {
            Text(key)
                .font(.system(.caption2, design: .monospaced))
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(.quaternary)
                .clipShape(RoundedRectangle(cornerRadius: 4))
            Text(label).font(.caption2)
        }
        .foregroundStyle(.tertiary)
    }

    // MARK: Navigation & execution

    private func navigate(_ direction: Int) {
        let all = filtered
        guard !all.isEmpty else { return }
        if let cur = highlighted, let idx = all.firstIndex(where: { $0.id == cur }) {
            highlighted = all[(idx + direction + all.count) % all.count].id
        } else {
            highlighted = direction > 0 ? all.first?.id : all.last?.id
        }
    }

    private func executeHighlighted() {
        if let id = highlighted, let item = filtered.first(where: { $0.id == id }) {
            execute(item)
        }
    }

    private func execute(_ item: PaletteItem) {
        isPresented = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) { item.action() }
    }
}

// MARK: - Palette overlay modifier

struct PaletteOverlay: ViewModifier {
    @Binding var isPresented: Bool
    let items: [PaletteItem]

    func body(content: Content) -> some View {
        ZStack {
            content
            if isPresented {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { isPresented = false }
                    .ignoresSafeArea()
                CommandPaletteView(items: items, isPresented: $isPresented)
                    .transition(.opacity.combined(with: .scale(scale: 0.97)))
                    .zIndex(100)
            }
        }
        .animation(.easeInOut(duration: 0.12), value: isPresented)
    }
}

extension View {
    func commandPalette(isPresented: Binding<Bool>, items: [PaletteItem]) -> some View {
        modifier(PaletteOverlay(isPresented: isPresented, items: items))
    }
}
