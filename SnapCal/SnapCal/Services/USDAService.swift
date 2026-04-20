import Foundation

enum USDAError: LocalizedError {
    case missingAPIKey
    case httpError(status: Int, body: String)
    case noMatch(query: String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey: return "USDA_API_KEY is not set."
        case .httpError(let status, let body):
            let trimmed = body.count > 400 ? String(body.prefix(400)) + "…" : body
            return "USDA HTTP \(status): \(trimmed)"
        case .noMatch(let query): return "USDA had no match for \"\(query)\"."
        }
    }
}

actor USDAService {
    private let apiKey: String
    private let session: URLSession
    private var cache: [String: USDAFood] = [:]

    init(
        apiKey: String? = ProcessInfo.processInfo.environment["USDA_API_KEY"]
            ?? (Bundle.main.object(forInfoDictionaryKey: "USDA_API_KEY") as? String),
        session: URLSession = .shared
    ) throws {
        guard let key = apiKey, !key.isEmpty else { throw USDAError.missingAPIKey }
        self.apiKey = key
        self.session = session
    }

    // Top match for a free-text food query. Prefers Foundation/SR Legacy/FNDDS
    // over Branded so we get generic lab-verified foods, not random consumer products.
    func bestMatch(for query: String) async throws -> USDAFood {
        let normalized = Self.normalizeQuery(query)
        let key = normalized.lowercased()
        if let hit = cache[key] { return hit }

        var components = URLComponents(string: "https://api.nal.usda.gov/fdc/v1/foods/search")!
        components.queryItems = [
            URLQueryItem(name: "api_key", value: apiKey),
            URLQueryItem(name: "query", value: normalized),
            URLQueryItem(name: "pageSize", value: "25")
        ]

        var request = URLRequest(url: components.url!)
        request.httpMethod = "GET"

        let (data, response) = try await session.data(for: request)
        let rawBody = String(data: data, encoding: .utf8) ?? ""
        #if DEBUG
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        print("[USDA] query=\"\(query)\" status=\(status) bytes=\(data.count)")
        print("[USDA] body-prefix=\(String(rawBody.prefix(600)))")
        #endif
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw USDAError.httpError(status: status, body: rawBody)
        }

        let result: USDASearchResponse
        do {
            result = try JSONDecoder().decode(USDASearchResponse.self, from: data)
            #if DEBUG
            print("[USDA] decoded \(result.foods.count) foods; top: \(result.foods.first?.description ?? "none")")
            if let top = result.foods.first {
                print("[USDA] top dataType=\(top.dataType ?? "nil") nutrients=\(top.foodNutrients.count) per100g=\(top.nutritionPer100g())")
            }
            #endif
        } catch {
            #if DEBUG
            print("[USDA] DECODE FAILED: \(error)")
            #endif
            throw error
        }

        let preferredOrder = ["Foundation", "SR Legacy", "Survey (FNDDS)", "Branded"]
        let queryTokens = Set(
            normalized
                .lowercased()
                .split(whereSeparator: { !$0.isLetter })
                .map(String.init)
                .filter { $0.count > 2 && !Self.stopwords.contains($0) }
        )
        // Rank by (1) token coverage in description — how many query words appear,
        // (2) dataType tier, (3) original USDA relevance order. This bubbles up
        // foods that actually mention every query word over high-scoring near-misses.
        let ranked = result.foods.enumerated().sorted { a, b in
            let aCoverage = Self.coverage(of: queryTokens, in: a.element.description)
            let bCoverage = Self.coverage(of: queryTokens, in: b.element.description)
            if aCoverage != bCoverage { return aCoverage > bCoverage }
            let ai = preferredOrder.firstIndex(of: a.element.dataType ?? "") ?? Int.max
            let bi = preferredOrder.firstIndex(of: b.element.dataType ?? "") ?? Int.max
            if ai != bi { return ai < bi }
            return a.offset < b.offset
        }.map(\.element)
        guard let top = ranked.first else { throw USDAError.noMatch(query: query) }

        #if DEBUG
        print("[USDA] ranked top: \"\(top.description)\" dataType=\(top.dataType ?? "nil") coverage=\(Self.coverage(of: queryTokens, in: top.description))/\(queryTokens.count)")
        #endif

        cache[key] = top
        return top
    }

    private static func coverage(of tokens: Set<String>, in description: String) -> Int {
        let lower = description.lowercased()
        return tokens.reduce(0) { count, token in
            count + (lower.contains(token) ? 1 : 0)
        }
    }

    // Light normalization only. Earlier version stripped prep words ("grilled",
    // "cooked") aggressively, but that made "grilled chicken" search as just
    // "chicken" — which returned "Chicken spread" as the top USDA match. USDA
    // actually has entries like "Chicken, breast, cooked, grilled" where the
    // prep word is part of the description — keeping it helps, not hurts.
    // Only strip purely cosmetic modifiers that don't affect nutrition.
    private static func normalizeQuery(_ raw: String) -> String {
        let cosmeticWords: Set<String> = [
            "fresh", "organic", "natural", "homemade", "artisanal"
        ]
        return raw
            .split(separator: " ")
            .map(String.init)
            .filter { !cosmeticWords.contains($0.lowercased()) }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
    }

    // Stopwords that shouldn't contribute to token-coverage scoring.
    // "and", "the", "with" can appear in almost any description and inflate
    // coverage scores for unrelated foods.
    private static let stopwords: Set<String> = [
        "and", "the", "with", "from", "into", "for", "plus", "some", "any"
    ]

    // Compute nutrition for a given item at a given portion size.
    // `gramsEstimate` is the normalized portion weight in grams.
    func nutrition(for food: USDAFood, gramsEstimate: Double) -> NutritionFacts {
        food.nutritionPer100g().scaled(by: gramsEstimate / 100.0)
    }
}

private struct USDASearchResponse: Decodable {
    let foods: [USDAFood]
}
