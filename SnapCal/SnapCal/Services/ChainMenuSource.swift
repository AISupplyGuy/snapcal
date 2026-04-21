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

    // Canonical chain display names — used by the Gemini prompt so the model
    // knows which chains have a backing database and should be collapsed into
    // a single menu-item name vs. decomposed into ingredients. Loads and
    // caches the chains table on first call; subsequent calls are free.
    func supportedChainNames() async -> [String] {
        if chainsCache == nil {
            do {
                try await loadChains()
            } catch {
                #if DEBUG
                print("[Chain] supportedChainNames load failed: \(error.localizedDescription)")
                #endif
                return []
            }
        }
        return chainsCache?.map { $0.name } ?? []
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

    // Strategy: any-token OR search (PostgREST or=(name.ilike.%a%,name.ilike.%b%...))
    // rather than the old strict-order %a%b%c% pattern, which missed rows
    // when Gemini's wording drifted from the stored menu name (e.g. "Chocolate
    // Chunk Pizookie" vs stored "Chocolate Chunk Pizookie®"). Locally we then
    // (1) require meaningful coverage, (2) prefer verified rows, (3) prefer
    // candidates whose token-count is closest to the query — that pushes
    // exact matches above generic parent items.
    private func bestMenuItem(chainId: UUID, rawName: String) async throws -> ChainMenuItemDTO? {
        let tokens = rawName
            .lowercased()
            .split(whereSeparator: { !$0.isLetter })
            .map(String.init)
            .filter { $0.count > 2 && !Self.stopwords.contains($0) }

        guard !tokens.isEmpty else { return nil }

        let orClauses = tokens.map { "name.ilike.%\($0)%" }.joined(separator: ",")
        let orExpr = "(" + orClauses + ")"

        var comps = URLComponents(
            url: baseURL.appendingPathComponent("rest/v1/chain_menu_items"),
            resolvingAgainstBaseURL: false
        )!
        comps.queryItems = [
            URLQueryItem(name: "select", value: "id,chain_id,name,normalized_name,category,serving_description,serving_grams,calories,protein_g,carbs_g,fat_g,fiber_g,verified"),
            URLQueryItem(name: "chain_id", value: "eq.\(chainId.uuidString)"),
            URLQueryItem(name: "or", value: orExpr),
            URLQueryItem(name: "limit", value: "50")
        ]

        let data = try await get(comps.url!)
        let candidates = try JSONDecoder().decode([ChainMenuItemDTO].self, from: data)

        #if DEBUG
        print("[Chain] chain=\(chainId) tokens=\(tokens) candidates=\(candidates.count)")
        #endif

        let tokenSet = Set(tokens)
        let scored: [(ChainMenuItemDTO, Int, Int)] = candidates.compactMap { item in
            let cov = coverage(of: tokenSet, in: item.name)
            let candTokens = item.name.lowercased()
                .split(whereSeparator: { !$0.isLetter }).count
            let minRequired = max(1, (tokens.count + 1) / 2)
            // Accept if at least half the query tokens match, OR candidate is
            // short (≤3 tokens) and we matched at least one — catches the
            // case where the menu row is "Pizookie" but the query is
            // "Chocolate Chunk Pizookie".
            if cov >= minRequired || (candTokens <= 3 && cov >= 1) {
                return (item, cov, candTokens)
            }
            return nil
        }

        let wantsGlutenFree = tokenSet.contains("gluten") || tokenSet.contains("gf")
        let gfFiltered: [(ChainMenuItemDTO, Int, Int)] = {
            if wantsGlutenFree {
                let onlyGF = scored.filter { isGlutenFreeVariant($0.0.name) }
                return onlyGF.isEmpty ? scored : onlyGF
            }
            let onlyNonGF = scored.filter { !isGlutenFreeVariant($0.0.name) }
            return onlyNonGF.isEmpty ? scored : onlyNonGF
        }()

        // Rank: verified first, then coverage desc, then candidate-length
        // closest to query length (tighter match wins). `verified` is
        // Bool? — treat nil as false.
        let best = gfFiltered.max { a, b in
            let av = a.0.verified ?? false
            let bv = b.0.verified ?? false
            if av != bv { return !av }
            if a.1 != b.1 { return a.1 < b.1 }
            return abs(a.2 - tokens.count) > abs(b.2 - tokens.count)
        }

        #if DEBUG
        if let pick = best {
            print("[Chain] picked \"\(pick.0.name)\" verified=\(pick.0.verified ?? false) coverage=\(pick.1)/\(tokens.count)")
        } else {
            print("[Chain] no viable candidate out of \(candidates.count)")
        }
        #endif

        return best?.0
    }

    private func isGlutenFreeVariant(_ name: String) -> Bool {
        let lower = name.lowercased()
        return lower.contains("gluten free") || lower.contains(" gf ")
    }

    private func coverage(of tokens: Set<String>, in description: String) -> Int {
        let lower = description.lowercased()
        return tokens.reduce(0) { count, token in
            count + (lower.contains(token) ? 1 : 0)
        }
    }

    // Same stopword set the USDA path uses so both ranking systems agree.
    private static let stopwords: Set<String> = [
        "and", "the", "with", "from", "into", "for", "plus", "some", "any"
    ]

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
