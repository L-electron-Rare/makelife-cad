import Foundation

// MARK: - GitHub API models

struct GitHubEntry: Identifiable, Decodable {
    var id: String { path }
    let name: String
    let path: String
    let type: String       // "file" or "dir"
    let downloadUrl: String?
    let htmlUrl: String?

    enum CodingKeys: String, CodingKey {
        case name, path, type
        case downloadUrl = "download_url"
        case htmlUrl     = "html_url"
    }
}

struct GitHubCategory: Identifiable {
    let id: String          // directory name
    let name: String
    let entries: [GitHubEntry]
}

// MARK: - ViewModel

@MainActor
final class GitHubLibraryViewModel: ObservableObject {

    @Published private(set) var categories: [GitHubCategory] = []
    @Published private(set) var isLoading = false
    @Published private(set) var error: String?
    @Published var selectedEntry: GitHubEntry?

    private let repo = "L-electron-Rare/makelife-hard"
    private var hasLoaded = false

    // MARK: - Public

    func load() async {
        guard !hasLoaded else { return }
        await fetch()
    }

    func refresh() async {
        hasLoaded = false
        categories = []
        selectedEntry = nil
        await fetch()
    }

    // MARK: - Private

    private func fetch() async {
        isLoading = true
        error = nil

        do {
            let root = try await fetchContents(path: "")
            let dirs = root
                .filter { $0.type == "dir" && !$0.name.hasPrefix(".") }
                .sorted { $0.name < $1.name }

            var result: [GitHubCategory] = []
            for dir in dirs {
                let files = try await fetchContents(path: dir.path)
                let kicad = files.filter {
                    $0.type == "file" && (
                        $0.name.hasSuffix(".kicad_sch") ||
                        $0.name.hasSuffix(".kicad_pcb") ||
                        $0.name.hasSuffix(".kicad_pro")
                    )
                }
                if !kicad.isEmpty {
                    result.append(GitHubCategory(id: dir.name, name: dir.name, entries: kicad))
                }
            }

            categories = result
            hasLoaded = true
        } catch {
            self.error = error.localizedDescription
        }

        isLoading = false
    }

    private func fetchContents(path: String) async throws -> [GitHubEntry] {
        let base = "https://api.github.com/repos/\(repo)/contents"
        let urlString = path.isEmpty ? base : "\(base)/\(path)"

        guard let url = URL(string: urlString) else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        request.setValue("MakelifeCAD/1.0", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)

        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw URLError(.badServerResponse)
        }

        return try JSONDecoder().decode([GitHubEntry].self, from: data)
    }
}
