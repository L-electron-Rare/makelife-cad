import Foundation

// MARK: - Data models

struct GitFileStatus: Identifiable, Hashable {
    var id: String { index + path }
    let index: String   // staged XY first char
    let workdir: String // staged XY second char
    let path: String

    var isStaged: Bool  { index != " " && index != "?" }
    var isUntracked: Bool { index == "?" }

    var displayStatus: String {
        if isUntracked { return "?" }
        if isStaged    { return index }
        return workdir
    }

    var statusColor: String {
        switch displayStatus {
        case "M":  return "orange"
        case "A":  return "green"
        case "D":  return "red"
        case "R":  return "blue"
        case "?":  return "gray"
        default:   return "secondary"
        }
    }
}

struct GitCommit: Identifiable {
    let id: String        // full hash
    let shortHash: String // 7 chars
    let message: String
    let author: String
    let date: String
}

struct GitHubPR: Identifiable {
    let id: Int
    let number: Int
    let title: String
    let state: String
    let url: String
    let author: String
}

// MARK: - ViewModel

@MainActor
final class GitHubRepoViewModel: ObservableObject {

    // Auth
    @Published private(set) var authUser: String?
    @Published private(set) var authError: String?

    // Repo info
    @Published private(set) var repoSlug: String?       // "owner/repo"
    @Published private(set) var repoWebURL: String?
    @Published private(set) var currentBranch: String?
    @Published private(set) var aheadBehind: String?    // e.g. "↑2 ↓1"

    // File status
    @Published private(set) var stagedFiles: [GitFileStatus]   = []
    @Published private(set) var unstagedFiles: [GitFileStatus] = []

    // History & PRs
    @Published private(set) var recentCommits: [GitCommit] = []
    @Published private(set) var pullRequests: [GitHubPR]   = []

    // UI state
    @Published private(set) var isLoading = false
    @Published private(set) var isPushing = false
    @Published private(set) var operationLog: String = ""
    @Published var lastError: String?
    @Published var commitMessage: String = ""

    private var projectRoot: URL?

    // MARK: - Attach

    func attach(projectRoot: URL?) {
        self.projectRoot = projectRoot
        operationLog = ""
        lastError = nil
        commitMessage = ""
        Task { await refreshAll() }
    }

    // MARK: - Refresh

    func refreshAll() async {
        guard projectRoot != nil else {
            clearState()
            return
        }
        isLoading = true
        defer { isLoading = false }

        await checkAuth()
        await refreshStatus()
        await fetchRecentCommits()

        if repoSlug != nil {
            await fetchPRs()
        }
    }

    private func clearState() {
        authUser = nil; authError = nil
        repoSlug = nil; repoWebURL = nil
        currentBranch = nil; aheadBehind = nil
        stagedFiles = []; unstagedFiles = []
        recentCommits = []; pullRequests = []
    }

    // MARK: - Auth check

    func checkAuth() async {
        let r = await shell("gh", "auth", "status", "--hostname", "github.com")
        if r.ok {
            // "Logged in to github.com account USERNAME (keyring)"
            for line in r.out.components(separatedBy: "\n") {
                if line.lowercased().contains("logged in") ||
                   line.lowercased().contains("account") {
                    let words = line.components(separatedBy: " ").filter { !$0.isEmpty }
                    if let idx = words.firstIndex(of: "account"), idx + 1 < words.count {
                        authUser = words[idx + 1]
                    }
                }
            }
            if authUser == nil { authUser = "authenticated" }
            authError = nil
        } else {
            authUser = nil
            // gh outputs to stderr
            let msg = (r.err + r.out).trimmingCharacters(in: .whitespacesAndNewlines)
            authError = msg.isEmpty ? "Not logged in — run `gh auth login`" : msg
        }
    }

    // MARK: - Git status

    func refreshStatus() async {
        guard let root = projectRoot else { return }

        // Remote URL → slug
        let remote = await git(in: root, "remote", "get-url", "origin")
        if remote.ok {
            let url = remote.out.trimmingCharacters(in: .whitespacesAndNewlines)
            repoSlug  = extractSlug(url)
            repoWebURL = url
        } else {
            repoSlug = nil; repoWebURL = nil
        }

        // Branch
        let branch = await git(in: root, "branch", "--show-current")
        currentBranch = branch.out.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty

        // Ahead/behind
        if let b = currentBranch {
            let rev = await git(in: root, "rev-list", "--left-right", "--count", "origin/\(b)...HEAD")
            if rev.ok {
                let parts = rev.out.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: "\t")
                if parts.count == 2, let behind = Int(parts[0]), let ahead = Int(parts[1]) {
                    var segments: [String] = []
                    if ahead  > 0 { segments.append("↑\(ahead)") }
                    if behind > 0 { segments.append("↓\(behind)") }
                    aheadBehind = segments.isEmpty ? nil : segments.joined(separator: " ")
                }
            }
        }

        // Porcelain status
        let status = await git(in: root, "status", "--porcelain")
        var staged: [GitFileStatus] = []
        var unstaged: [GitFileStatus] = []

        for line in status.out.components(separatedBy: "\n") {
            guard line.count >= 3 else { continue }
            let x    = String(line.prefix(1))
            let y    = String(line.dropFirst(1).prefix(1))
            let path = String(line.dropFirst(3))

            if x != " " && x != "?" {
                staged.append(GitFileStatus(index: x, workdir: y, path: path))
            }
            if y != " " || x == "?" {
                unstaged.append(GitFileStatus(index: x, workdir: y == " " ? x : y, path: path))
            }
        }

        stagedFiles   = staged
        unstagedFiles = unstaged
    }

    // MARK: - Commits

    func fetchRecentCommits() async {
        guard let root = projectRoot else { return }
        let r = await git(in: root, "log", "--pretty=format:%H|%s|%an|%ar", "-n", "25")
        recentCommits = r.out
            .components(separatedBy: "\n")
            .filter { !$0.isEmpty }
            .compactMap { line -> GitCommit? in
                let p = line.components(separatedBy: "|")
                guard p.count >= 4 else { return nil }
                return GitCommit(id: p[0], shortHash: String(p[0].prefix(7)),
                                 message: p[1], author: p[2], date: p[3])
            }
    }

    // MARK: - Stage / Unstage

    func stageAll() async {
        guard let root = projectRoot else { return }
        let r = await git(in: root, "add", "-A")
        log(r.out + r.err)
        await refreshStatus()
    }

    func stageFile(_ path: String) async {
        guard let root = projectRoot else { return }
        let r = await git(in: root, "add", "--", path)
        log(r.out + r.err)
        await refreshStatus()
    }

    func unstageFile(_ path: String) async {
        guard let root = projectRoot else { return }
        let r = await git(in: root, "restore", "--staged", "--", path)
        log(r.out + r.err)
        await refreshStatus()
    }

    // MARK: - Commit

    func commit() async {
        guard let root = projectRoot, !commitMessage.trimmingCharacters(in: .whitespaces).isEmpty else {
            lastError = "Enter a commit message."
            return
        }
        let r = await git(in: root, "commit", "-m", commitMessage)
        log(r.out + r.err)
        if r.ok {
            commitMessage = ""
            lastError = nil
            await refreshStatus()
            await fetchRecentCommits()
        } else {
            lastError = r.err.nilIfEmpty ?? r.out
        }
    }

    // MARK: - Push / Pull

    func push() async {
        guard let root = projectRoot else { return }
        isPushing = true
        defer { isPushing = false }
        let r = await git(in: root, "push")
        log(r.out + r.err)
        if !r.ok { lastError = r.err.nilIfEmpty ?? r.out }
        await refreshStatus()
        await fetchRecentCommits()
    }

    func pull() async {
        guard let root = projectRoot else { return }
        isLoading = true
        defer { isLoading = false }
        let r = await git(in: root, "pull")
        log(r.out + r.err)
        if !r.ok { lastError = r.err.nilIfEmpty ?? r.out }
        await refreshAll()
    }

    // MARK: - PRs

    func fetchPRs() async {
        guard let slug = repoSlug else { return }
        let r = await shell("gh", "pr", "list",
                            "--repo", slug,
                            "--json", "number,title,state,url,author",
                            "--limit", "10")
        if r.ok { pullRequests = decodePRs(r.out) }
    }

    func createPR(title: String, body: String) async {
        guard let _ = projectRoot, let slug = repoSlug else { return }
        let r = await shell("gh", "pr", "create",
                            "--repo", slug,
                            "--title", title,
                            "--body", body)
        log(r.out + r.err)
        if r.ok {
            lastError = nil
            await fetchPRs()
        } else {
            lastError = r.err.nilIfEmpty ?? r.out
        }
    }

    func clearLog() { operationLog = "" }

    // MARK: - Helpers

    private func log(_ text: String) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        operationLog = operationLog.isEmpty ? t : operationLog + "\n" + t
    }

    private func extractSlug(_ raw: String) -> String? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasSuffix(".git") { s = String(s.dropLast(4)) }
        if s.hasPrefix("https://github.com/") { return String(s.dropFirst("https://github.com/".count)) }
        if s.hasPrefix("git@github.com:")      { return String(s.dropFirst("git@github.com:".count)) }
        return nil
    }

    private func decodePRs(_ json: String) -> [GitHubPR] {
        guard let data = json.data(using: .utf8),
              let arr  = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else { return [] }
        return arr.compactMap { d in
            guard let n = d["number"] as? Int,
                  let t = d["title"]  as? String,
                  let s = d["state"]  as? String,
                  let u = d["url"]    as? String else { return nil }
            let author: String
            if let a = d["author"] as? [String: Any], let l = a["login"] as? String { author = l }
            else { author = "" }
            return GitHubPR(id: n, number: n, title: t, state: s, url: u, author: author)
        }
    }

    // MARK: - Process runner

    struct RunResult {
        let out: String
        let err: String
        let code: Int32
        var ok: Bool { code == 0 }
    }

    /// Run a git sub-command in a directory.
    private func git(in dir: URL, _ args: String...) async -> RunResult {
        await run(["/usr/bin/env", "git", "-C", dir.path] + args)
    }

    /// Run any shell command (gh, open, …) — searches standard Homebrew paths.
    private func shell(_ args: String...) async -> RunResult {
        await run(["/usr/bin/env"] + args)
    }

    private func run(_ args: [String]) async -> RunResult {
        await withCheckedContinuation { cont in
            Task.detached {
                let p = Process()
                p.executableURL = URL(fileURLWithPath: args[0])
                p.arguments = Array(args.dropFirst())

                var env = ProcessInfo.processInfo.environment
                env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:" + (env["PATH"] ?? "")
                p.environment = env

                let outPipe = Pipe()
                let errPipe = Pipe()
                p.standardOutput = outPipe
                p.standardError  = errPipe

                do {
                    try p.run()
                    p.waitUntilExit()
                } catch {
                    cont.resume(returning: RunResult(out: "", err: error.localizedDescription, code: -1))
                    return
                }

                let out = String(data: outPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                let err = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                cont.resume(returning: RunResult(out: out, err: err, code: p.terminationStatus))
            }
        }
    }
}

// MARK: - String helper

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
