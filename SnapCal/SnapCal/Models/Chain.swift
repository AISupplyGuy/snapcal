import Foundation

struct Chain: Codable, Sendable, Identifiable {
    let id: UUID
    let slug: String
    let name: String
    let website: String?
}

struct ChainMenuItemDTO: Codable, Sendable, Identifiable {
    let id: UUID
    let chain_id: UUID
    let name: String
    let normalized_name: String
    let category: String?
    let serving_description: String?
    let serving_grams: Double?
    let calories: Double?
    let protein_g: Double?
    let carbs_g: Double?
    let fat_g: Double?
    let fiber_g: Double?
    let verified: Bool?
}
