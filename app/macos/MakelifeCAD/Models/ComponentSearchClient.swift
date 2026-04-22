import Foundation

// MARK: - Supplier search result

struct SupplierResult: Identifiable {
    let id = UUID()
    let partNumber: String
    let manufacturer: String
    let description: String
    let unitPrice: Double?
    let stock: Int?
    let datasheetURL: URL?
    let productURL: URL?
    let source: String  // e.g. "LCSC"

    var priceString: String {
        guard let p = unitPrice else { return "—" }
        return String(format: "$%.4f", p)
    }

    var stockString: String {
        guard let s = stock else { return "—" }
        return s > 0 ? "\(s)" : "Out of stock"
    }
}

// MARK: - ComponentSearchClient

/// Searches electronic component suppliers for pricing and availability.
/// Currently supports LCSC (free, no API key).
actor ComponentSearchClient {

    enum SearchError: Error, LocalizedError {
        case invalidResponse
        case httpError(Int)
        case noResults

        var errorDescription: String? {
            switch self {
            case .invalidResponse: return "Invalid response from supplier"
            case .httpError(let code): return "HTTP \(code)"
            case .noResults: return "No results found"
            }
        }
    }

    // MARK: - LCSC Search

    /// Searches LCSC for components matching a query (value + footprint).
    func searchLCSC(query: String) async throws -> [SupplierResult] {
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        guard let url = URL(string: "https://wmsc.lcsc.com/ftps/wm/search/global?keyword=\(encoded)") else {
            throw SearchError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 10

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw SearchError.invalidResponse
        }
        guard httpResponse.statusCode == 200 else {
            throw SearchError.httpError(httpResponse.statusCode)
        }

        return parseLCSCResponse(data)
    }

    private func parseLCSCResponse(_ data: Data) -> [SupplierResult] {
        // LCSC returns JSON with productList array
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = json["result"] as? [String: Any],
              let productList = result["productList"] as? [[String: Any]] else {
            return []
        }

        return productList.prefix(5).compactMap { product -> SupplierResult? in
            guard let partNumber = product["productCode"] as? String else { return nil }

            let manufacturer = product["brandNameEn"] as? String ?? "Unknown"
            let description = product["productDescEn"] as? String
                ?? product["productModel"] as? String ?? ""

            // Price: LCSC returns price tiers in productPriceList
            var unitPrice: Double?
            if let priceList = product["productPriceList"] as? [[String: Any]],
               let firstTier = priceList.first,
               let price = firstTier["productPrice"] as? Double {
                unitPrice = price
            }

            // Stock
            let stock = product["stockNumber"] as? Int

            // Datasheet
            var datasheetURL: URL?
            if let pdfURL = product["pdfUrl"] as? String, !pdfURL.isEmpty {
                datasheetURL = URL(string: pdfURL.hasPrefix("http") ? pdfURL : "https://wmsc.lcsc.com\(pdfURL)")
            }

            // Product page
            let productURL = URL(string: "https://www.lcsc.com/product-detail/\(partNumber).html")

            return SupplierResult(
                partNumber: partNumber,
                manufacturer: manufacturer,
                description: description,
                unitPrice: unitPrice,
                stock: stock,
                datasheetURL: datasheetURL,
                productURL: productURL,
                source: "LCSC"
            )
        }
    }
}
