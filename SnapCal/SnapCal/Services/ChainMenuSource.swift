import Foundation

enum ChainMenuError: LocalizedError {
    case missingConfig
    case httpError(status: Int, body: String)

    var errorDescription: String? {
        switch self {
        case .missingConfig: return "SUPABASE_URL or SUPABASE_ANON_KEY is not set."
        case .httpError(let status, let body):
            let trimmed = body.count > 400 ? String(body.prefix(400)) + "…" : body
            return "Supabase HTTP \(status): \(trimmed)"
        }
    }
}

// Looks up chain restaurant menu items from the snapcal Supabase project
// (chains + chain_menu_items tables). Only returns a match when Gemini
// surfaced a brand cue AND that cue aligns with a chain in the DB.
actor ChainMenuSource: NutritionSource {
    let id = "chain-menu"
    private let baseURL: URL
    private let apiKey: String
    private let session: URLSession
    private var chainsCache: [Chain]?

    init(
        supabaseURL: String? = ProcessInfo.processInfo.environment["SUPABASE_URL"]
            ?? (Bundle.main.object(forInfoDictionaryKey: "SUPABASE_URL") as? String),
        apiKey: String? = ProcessInfo.processInfo.environment["SUPABASE_ANON_KEY"]
            ?? (Bundle.main.object(forInfoDictionaryKey: "SUPABASE_ANON_KEY") as? String),
        session: URLSession = .shared
    ) throws {
        guard let urlString = supabaseURL, let url = URL(string: urlString),
              let key = apiKey, !key.isEmpty else {
            throw ChainMenuError.missingConfig
        }
        self.baseURL = url
        self.apiKey = key
        self.session = session
    }

    func lookup(query: NutritionQuery) async throws -> NutritionMatch? {
        guard let rawBrand = query.brandCue, !rawBrand.isEmpty else { return nil }
        guard let chain = try await matchedChain(for: rawBrand) else { return nil }
        guard let item = try await bestMenuItem(chainId: chain.id, rawName: query.itemName) else {
            #if DEBUG
            print("[Chain] \(chain.slug) matched but no item for \"\(query.itemName)\"")
            #endif
            return nil
        }

        let nutrition = Self.nutrition(from: item, targetGrams: query.gramsEstimate)
        return NutritionMatch(
            sourceId: chain.slug,
            displayName: "\(chain.name): \(item.name)",
            externalId: item.id.uuidString,
            nutrition: nutrition,
            confidence: 0.9
        )
    }

    // MARK: Chain matching

    private func matchedChain(for brandCue: String) async throws -> Chain? {
        if chainsCache == nil { try await loadChains() }
        let lower = brandCue.lowercased()
        return chainsCache?.first { chain in
            let name = chain.name.lowercased()
            if lower.contains(chain.slug) || chain.slug.contains(lower) { return true }
            if lower.contains(name) || name.contains(lower) { return true }
            let nameStripped = name.replacingOccurrences(of: "'", with: "")
            if lower.contains(nameStripped) || nameStripped.contains(lower) { return true }
            return false
        }
    }

    private func loadChains() async throws {
        var comps = URLComponents(
            url: baseURL.appendingPathComponent("rest/v1/chains"),
            resolvingAgainstBaseURL: false
        )!
        comps.queryItems = [URLQueryItem(name: "select", value: "id,slug,name,website")]
        let data = try await get(comps.url!)
        chainsCache = try JSONDecoder().decode([Chain].self, from: data)
        #if DEBUG
        print("[Chain] loaded \(chainsCache?.count ?? 0) chains")
        #endif
    }

    // MARK: Item search

    private func bestMenuItem(chainId: UUID, rawName: String) async throws -> ChainMenuItemDTO? {
        let tokens = rawName
            .lowercased()
            .split(whereSeparator: { !$0.isLetter })
            .map(String.init)
            .filter { $0.count > 2 }

        let pattern = tokens.isEmpty ? "%" : "%" + tokens.joined(separator: "%") + "%"

        var comps = URLComponents(
            url: baseURL.appendingPathComponent("rest/v1/chain_menu_items"),
            resolvingAgainstBaseURL: false
        )!
        comps.queryItems = [
            URLQueryItem(name: "select", value: "id,chain_id,name,normalized_name,category,serving_description,serving_grams,calories,protein_g,carbs_g,fat_g,fiber_g,verified"),
            URLQueryItem(name: "chain_id", value: "eq.\(chainId.uuidString)"),
            URLQueryItem(name: "name", value: "ilike.\(pattern)"),
            URLQueryItem(name: "limit", value: "15")
        ]

        let data = try await get(comps.url!)
        let candidates = try JSONDecoder().decode([ChainMenuItemDTO].self, from: data)

        #if DEBUG
        print("[Chain] chain=\(chainId) pattern=\(pattern) candidates=\(candidates.count)")
        #endif

        let tokenSet = Set(tokens)
        return candidates.max { a, b in
            coverage(of: tokenSet, in: a.name) < coverage(of: tokenSet, in: b.name)
        } ?? candidates.first
    }

    private func coverage(of tokens: Set<String>, in description: String) -> Int {
        let lower = description.lowercased()
        return tokens.reduce(0) { count, token in
            count + (lower.contains(token) ? 1 : 0)
        }
    }

    // MARK: Nutrition math

    private static func nutrition(from item: ChainMenuItemDTO, targetGrams: Double) -> NutritionFacts {
        let base = NutritionFacts(
            calories: item.calories ?? 0,
            proteinGrams: item.protein_g ?? 0,
            carbGrams: item.carbs_g ?? 0,
            fatGrams: item.fat_g ?? 0,
            fiberGrams: item.fiber_g ?? 0
        )
        guard let servingGrams = item.serving_grams, servingGrams > 0, targetGrams > 0 else {
            return base
        }
        return base.scaled(by: targetGrams / servingGrams)
    }

    // MARK: HTTP

    private func get(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue(apiKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw ChainMenuError.httpError(status: status, body: String(data: data, encoding: .utf8) ?? "")
        }
        return data
    }
}
