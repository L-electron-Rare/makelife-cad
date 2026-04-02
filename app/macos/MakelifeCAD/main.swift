import SwiftUI

@MainActor
final class GatewayViewModel: ObservableObject {
    @Published var gatewayStatus = "loading"
    @Published var yiacadStatus = "loading"
    @Published var yiacadGatewayHealth = "loading"
    @Published var yiacadAiStatus = "loading"
    @Published var query = "esp32"
    @Published var searchCount = 0
    @Published var message = ""

    func refresh() async {
        message = ""

        do {
            let gatewayURL = URL(string: "http://127.0.0.1:8001/health")!
            let (gatewayData, _) = try await URLSession.shared.data(from: gatewayURL)
            let gateway = try JSONDecoder().decode(HealthResponse.self, from: gatewayData)
            gatewayStatus = gateway.status
        } catch {
            gatewayStatus = "unreachable"
            message = "Gateway makelife-cad indisponible sur http://127.0.0.1:8001"
        }

        do {
            let statusURL = URL(string: "http://127.0.0.1:8001/yiacad/status")!
            let (statusData, _) = try await URLSession.shared.data(from: statusURL)
            let status = try JSONDecoder().decode(YiacadStatusResponse.self, from: statusData)
            yiacadStatus = status.status

            if status.status == "available" {
                message = "YiACAD runtime connecte"
            } else {
                message = "YiACAD runtime non disponible: \(status.configuredPath)"
            }
        } catch {
            yiacadStatus = "unreachable"
            if message.isEmpty {
                message = "Impossible de lire /yiacad/status"
            }
        }

        do {
            let yiacadHealthURL = URL(string: "http://127.0.0.1:8001/yiacad/health")!
            let (_, response) = try await URLSession.shared.data(from: yiacadHealthURL)
            yiacadGatewayHealth = (response as? HTTPURLResponse)?.statusCode == 200 ? "ok" : "error"
        } catch {
            yiacadGatewayHealth = "unreachable"
        }

        do {
            let yiacadAiStatusURL = URL(string: "http://127.0.0.1:8001/yiacad/ai/status")!
            let (_, response) = try await URLSession.shared.data(from: yiacadAiStatusURL)
            yiacadAiStatus = (response as? HTTPURLResponse)?.statusCode == 200 ? "ok" : "error"
        } catch {
            yiacadAiStatus = "unreachable"
        }
    }

    func runComponentSearch() async {
        do {
            let url = URL(string: "http://127.0.0.1:8001/yiacad/components/search")!
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            let body = ["query": query]
            request.httpBody = try JSONSerialization.data(withJSONObject: body)

            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                message = "Recherche composants en echec"
                return
            }

            if let parsed = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let inner = parsed["response"] as? [String: Any],
               let results = inner["results"] as? [[String: Any]] {
                searchCount = results.count
                message = "Recherche YiACAD OK: \(results.count) resultat(s)"
            } else {
                searchCount = 0
                message = "Recherche YiACAD OK"
            }
        } catch {
            message = "Erreur requete composants: \(error.localizedDescription)"
        }
    }
}

private struct HealthResponse: Decodable {
    let status: String
}

private struct YiacadStatusResponse: Decodable {
    let status: String
    let configuredPath: String

    private enum CodingKeys: String, CodingKey {
        case status
        case configuredPath = "configured_path"
    }
}

@main
struct MakelifeCADApp: App {
    @StateObject private var viewModel = GatewayViewModel()

    var body: some Scene {
        WindowGroup {
            VStack(alignment: .leading, spacing: 16) {
                Text("Makelife CAD")
                    .font(.largeTitle)
                    .bold()

                HStack {
                    Text("Gateway")
                        .frame(width: 120, alignment: .leading)
                    Text(viewModel.gatewayStatus)
                        .foregroundStyle(viewModel.gatewayStatus == "ok" ? .green : .orange)
                }

                HStack {
                    Text("YiACAD")
                        .frame(width: 120, alignment: .leading)
                    Text(viewModel.yiacadStatus)
                        .foregroundStyle(viewModel.yiacadStatus == "available" ? .green : .orange)
                }

                HStack {
                    Text("YiACAD health")
                        .frame(width: 120, alignment: .leading)
                    Text(viewModel.yiacadGatewayHealth)
                        .foregroundStyle(viewModel.yiacadGatewayHealth == "ok" ? .green : .orange)
                }

                HStack {
                    Text("YiACAD AI")
                        .frame(width: 120, alignment: .leading)
                    Text(viewModel.yiacadAiStatus)
                        .foregroundStyle(viewModel.yiacadAiStatus == "ok" ? .green : .orange)
                }

                HStack {
                    TextField("component query", text: $viewModel.query)
                        .textFieldStyle(.roundedBorder)
                    Button("Search") {
                        Task {
                            await viewModel.runComponentSearch()
                        }
                    }
                }

                if viewModel.searchCount > 0 {
                    Text("Results: \(viewModel.searchCount)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text(viewModel.message)
                    .font(.body)

                Button("Refresh runtime") {
                    Task {
                        await viewModel.refresh()
                    }
                }
            }
            .frame(minWidth: 620, minHeight: 300)
            .padding(24)
            .task {
                await viewModel.refresh()
            }
        }
    }
}
