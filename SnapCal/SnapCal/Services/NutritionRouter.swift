import Foundation

// Decides which NutritionSource to try first for a given query, then falls
// through if the primary returns nil or throws. Per ARCHITECTURE.md:
//   brand_cue present → chain menu first, USDA fallback
//   no brand_cue      → USDA first
actor NutritionRouter {
    private let sources: [NutritionSource]

    init(sources: [NutritionSource]) {
        self.sources = sources
    }

    func lookup(query: NutritionQuery) async -> NutritionMatch? {
        let ordered = prioritize(sources, for: query)
        for source in ordered {
            do {
                if let match = try await source.lookup(query: query) {
                    #if DEBUG
                    print("[Router] \(source.id) matched \"\(match.displayName)\" for \"\(query.itemName)\"")
                    #endif
                    return match
                }
            } catch {
                #if DEBUG
                print("[Router] \(source.id) error: \(error.localizedDescription)")
                #endif
                continue
            }
        }
        #if DEBUG
        print("[Router] no source matched \"\(query.itemName)\" (brand=\(query.brandCue ?? "nil"))")
        #endif
        return nil
    }

    private func prioritize(_ sources: [NutritionSource], for query: NutritionQuery) -> [NutritionSource] {
        if query.brandCue != nil {
            return sources.sorted { a, b in
                (a.id == "chain-menu") && (b.id != "chain-menu")
            }
        }
        return sources
    }
}
