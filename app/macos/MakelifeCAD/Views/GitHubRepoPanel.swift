import SwiftUI

// MARK: - Sidebar

struct GitRepoSidebarView: View {
    @ObservedObject var vm: GitHubRepoViewModel

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if vm.isLoading && vm.repoSlug == nil {
                loadingPlaceholder
            } else {
                content
            }
        }
        .frame(minWidth: 220, idealWidth: 260, maxWidth: 320)
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "arrow.triangle.branch")
                .foregroundStyle(Color.accentColor)
            Text("Git")
                .font(.headline)
            Spacer()
            if vm.isLoading {
                ProgressView().scaleEffect(0.6)
            } else {
                Button {
                    Task { await vm.refreshAll() }
                } label: {
                    Image(systemName: "arrow.clockwise").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Refresh")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                authRow
                Divider()
                repoRow
                branchRow
                Divider()
                changesSection
                Divider()
                pullButton
            }
        }
    }

    // Auth badge
    private var authRow: some View {
        HStack(spacing: 8) {
            Image(systemName: vm.authUser != nil ? "checkmark.seal.fill" : "xmark.seal")
                .foregroundStyle(vm.authUser != nil ? Color.green : Color.red)
                .font(.caption)
            if let user = vm.authUser {
                Text(user)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                Text("· github.com")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            } else {
                Text(vm.authError ?? "Not authenticated")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    // Repo slug
    private var repoRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "network")
                .frame(width: 14)
                .foregroundStyle(.secondary)
                .font(.caption)
            if let slug = vm.repoSlug {
                Text(slug)
                    .font(.system(.caption, design: .monospaced))
                    .lineLimit(1)
                if let webURL = vm.repoWebURL,
                   let url = URL(string: webURL.hasPrefix("http") ? webURL : "https://github.com/\(slug)") {
                    Spacer()
                    Link(destination: url) {
                        Image(systemName: "arrow.up.right.square")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .help("Open on GitHub")
                }
            } else {
                Text("No remote origin")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
    }

    // Branch
    private var branchRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.triangle.branch")
                .frame(width: 14)
                .foregroundStyle(.secondary)
                .font(.caption)
            Text(vm.currentBranch ?? "—")
                .font(.system(.caption, design: .monospaced))
            Spacer()
            if let ab = vm.aheadBehind {
                Text(ab)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
    }

    // Changes section
    private var changesSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Section title
            HStack {
                Text("CHANGES")
                    .font(.caption2).fontWeight(.semibold).foregroundStyle(.secondary)
                Spacer()
                let total = vm.stagedFiles.count + vm.unstagedFiles.count
                if total > 0 {
                    Text("\(total)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 4)

            if vm.stagedFiles.isEmpty && vm.unstagedFiles.isEmpty {
                Text("Clean working tree")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
            }

            // Staged
            if !vm.stagedFiles.isEmpty {
                Text("Staged")
                    .font(.caption2).foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 2)
                ForEach(vm.stagedFiles) { f in
                    FileStatusRow(file: f, action: {
                        Task { await vm.unstageFile(f.path) }
                    }, actionLabel: "Unstage", actionIcon: "minus.circle")
                }
            }

            // Unstaged
            if !vm.unstagedFiles.isEmpty {
                Text("Unstaged")
                    .font(.caption2).foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.top, vm.stagedFiles.isEmpty ? 0 : 6)
                    .padding(.bottom, 2)
                ForEach(vm.unstagedFiles) { f in
                    FileStatusRow(file: f, action: {
                        Task { await vm.stageFile(f.path) }
                    }, actionLabel: "Stage", actionIcon: "plus.circle")
                }
            }
        }
    }

    // Pull button
    private var pullButton: some View {
        Button {
            Task { await vm.pull() }
        } label: {
            Label("Pull", systemImage: "arrow.down.circle")
                .frame(maxWidth: .infinity, alignment: .leading)
                .font(.caption)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .disabled(vm.isLoading)
    }

    private var loadingPlaceholder: some View {
        VStack(spacing: 10) {
            Spacer()
            ProgressView()
            Text("Checking repository…")
                .font(.caption).foregroundStyle(.tertiary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - File row

private struct FileStatusRow: View {
    let file: GitFileStatus
    let action: () -> Void
    let actionLabel: String
    let actionIcon: String

    var body: some View {
        HStack(spacing: 6) {
            // Status badge
            Text(file.displayStatus)
                .font(.system(.caption2, design: .monospaced).bold())
                .frame(width: 14)
                .foregroundStyle(statusColor)

            Text(file.path.split(separator: "/").last.map(String.init) ?? file.path)
                .font(.system(.caption, design: .monospaced))
                .lineLimit(1)
                .foregroundStyle(.primary)

            Spacer()

            Button {
                action()
            } label: {
                Image(systemName: actionIcon)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help(actionLabel)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 3)
    }

    private var statusColor: Color {
        switch file.displayStatus {
        case "M": return .orange
        case "A": return .green
        case "D": return .red
        case "R": return .blue
        default:  return .secondary
        }
    }
}

// MARK: - Detail

struct GitRepoDetailView: View {
    @ObservedObject var vm: GitHubRepoViewModel
    @State private var showNewPR = false
    @State private var prTitle  = ""
    @State private var prBody   = ""

    var body: some View {
        VStack(spacing: 0) {
            commitPanel
            Divider()
            HStack(alignment: .top, spacing: 0) {
                commitsColumn
                Divider()
                prsColumn
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if !vm.operationLog.isEmpty {
                Divider()
                logPanel
            }
        }
        .sheet(isPresented: $showNewPR) {
            newPRSheet
        }
        .alert("Error", isPresented: Binding(
            get: { vm.lastError != nil },
            set: { if !$0 { vm.lastError = nil } }
        )) {
            Button("OK") { vm.lastError = nil }
        } message: {
            Text(vm.lastError ?? "")
        }
    }

    // MARK: Commit panel

    private var commitPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Commit")
                .font(.headline)

            TextField("Commit message…", text: $vm.commitMessage, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(2...4)
                .font(.system(.callout, design: .monospaced))

            HStack(spacing: 8) {
                Button("Stage All") {
                    Task { await vm.stageAll() }
                }
                .buttonStyle(.bordered)
                .disabled(vm.unstagedFiles.isEmpty)

                Button("Commit") {
                    Task { await vm.commit() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(vm.stagedFiles.isEmpty || vm.commitMessage.trimmingCharacters(in: .whitespaces).isEmpty)

                Button {
                    Task { await vm.push() }
                } label: {
                    if vm.isPushing {
                        ProgressView().scaleEffect(0.7)
                    } else {
                        Label("Push", systemImage: "arrow.up.circle")
                    }
                }
                .buttonStyle(.bordered)
                .disabled(vm.isPushing || vm.repoSlug == nil)

                Spacer()

                if let ab = vm.aheadBehind {
                    Text(ab)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(16)
        .background(.ultraThinMaterial)
    }

    // MARK: Commits column

    private var commitsColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("Recent Commits", count: vm.recentCommits.count, icon: "clock")
            Divider()
            if vm.recentCommits.isEmpty {
                emptyState(icon: "clock.badge.xmark", msg: "No commits yet")
            } else {
                List(vm.recentCommits) { commit in
                    CommitRow(commit: commit)
                }
                .listStyle(.inset)
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: PRs column

    private var prsColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                sectionHeader("Pull Requests", count: vm.pullRequests.count, icon: "arrow.triangle.merge")
                Spacer()
                Button {
                    prTitle = ""; prBody = ""
                    showNewPR = true
                } label: {
                    Image(systemName: "plus")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .padding(.trailing, 12)
                .help("New PR")
                .disabled(vm.repoSlug == nil || vm.authUser == nil)
            }
            Divider()
            if vm.pullRequests.isEmpty {
                emptyState(icon: "arrow.triangle.merge", msg: vm.repoSlug == nil ? "No remote" : "No open PRs")
            } else {
                List(vm.pullRequests) { pr in
                    PRRow(pr: pr)
                }
                .listStyle(.inset)
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Log

    private var logPanel: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Log")
                    .font(.caption2.bold())
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Clear") { vm.clearLog() }
                    .font(.caption2)
                    .buttonStyle(.plain)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12)
            .padding(.top, 6)

            ScrollView {
                Text(vm.operationLog)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
                    .textSelection(.enabled)
            }
            .frame(maxHeight: 120)
            .background(Color(.windowBackgroundColor).opacity(0.5))
        }
    }

    // MARK: New PR sheet

    private var newPRSheet: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("New Pull Request")
                .font(.title3.bold())

            TextField("Title", text: $prTitle)
                .textFieldStyle(.roundedBorder)

            TextField("Description (optional)", text: $prBody, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(4...8)

            HStack {
                Spacer()
                Button("Cancel") { showNewPR = false }
                    .keyboardShortcut(.cancelAction)
                Button("Create PR") {
                    showNewPR = false
                    Task { await vm.createPR(title: prTitle, body: prBody) }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(prTitle.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(24)
        .frame(minWidth: 400, minHeight: 260)
    }

    // MARK: Helpers

    private func sectionHeader(_ label: String, count: Int, icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(label)
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            Spacer()
            if count > 0 {
                Text("\(count)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private func emptyState(icon: String, msg: String) -> some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: icon)
                .font(.system(size: 28))
                .foregroundStyle(.tertiary)
            Text(msg)
                .font(.callout)
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Commit row

private struct CommitRow: View {
    let commit: GitCommit

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(commit.message)
                .font(.callout)
                .lineLimit(2)
            HStack(spacing: 6) {
                Text(commit.shortHash)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.secondary)
                Text("·")
                    .foregroundStyle(.tertiary)
                Text(commit.author)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text("·")
                    .foregroundStyle(.tertiary)
                Text(commit.date)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - PR row

private struct PRRow: View {
    let pr: GitHubPR

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: pr.state == "OPEN" ? "arrow.triangle.merge" : "checkmark.circle.fill")
                .foregroundStyle(pr.state == "OPEN" ? Color.green : Color.purple)
                .font(.callout)

            VStack(alignment: .leading, spacing: 2) {
                Text(pr.title)
                    .font(.callout)
                    .lineLimit(2)
                HStack(spacing: 4) {
                    Text("#\(pr.number)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                    if !pr.author.isEmpty {
                        Text("by \(pr.author)")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            Spacer()

            if let url = URL(string: pr.url) {
                Link(destination: url) {
                    Image(systemName: "arrow.up.right.square")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .help("Open PR on GitHub")
            }
        }
        .padding(.vertical, 2)
    }
}
