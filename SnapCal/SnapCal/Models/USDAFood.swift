import Foundation

// Minimal subset of USDA FoodData Central fields SnapCal needs.
// Full API docs: https://fdc.nal.usda.gov/api-guide.html

struct USDAFood: Codable, Sendable, Identifiable {
    let fdcId: Int
    let description: String
    let dataType: String?
    let foodNutrients: [USDANutrient]

    var id: Int { fdcId }

    // USDA nutrient values are "per 100 g" for Foundation/SR Legacy. Branded foods declare their own serving.
    func nutritionPer100g() -> NutritionFacts {
        NutritionFacts(
            calories: nutrientValue(.energy),
            proteinGrams: nutrientValue(.protein),
            carbGrams: nutrientValue(.carbohydrate),
            fatGrams: nutrientValue(.fat),
            fiberGrams: nutrientValue(.fiber)
        )
    }

    private func nutrientValue(_ kind: USDANutrientKind) -> Double {
        foodNutrients.first { $0.matches(kind) }?.amount ?? 0
    }
}

struct USDANutrient: Codable, Sendable {
    // /foods/search returns amount under "value"; /food/{id} uses "amount". Accept both.
    // Some endpoints also nest the nutrient metadata inside a `"nutrient"` object.
    let nutrientId: Int?
    let nutrientName: String?
    let nutrientNumber: String?
    let unitName: String?
    let amount: Double?

    func matches(_ kind: USDANutrientKind) -> Bool {
        if let id = nutrientId, kind.fdcIds.contains(id) { return true }
        if let number = nutrientNumber, kind.fdcNumbers.contains(number) { return true }
        return false
    }

    private enum TopKeys: String, CodingKey {
        case nutrientId, nutrientName, nutrientNumber, unitName
        case amount, value
        case nutrient
    }
    private enum NestedKeys: String, CodingKey {
        case id, name, number, unitName
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: TopKeys.self)

        // amount: prefer "amount", fall back to "value"
        self.amount = try c.decodeIfPresent(Double.self, forKey: .amount)
            ?? c.decodeIfPresent(Double.self, forKey: .value)

        // top-level fields
        var id = try c.decodeIfPresent(Int.self, forKey: .nutrientId)
        var name = try c.decodeIfPresent(String.self, forKey: .nutrientName)
        var number = try c.decodeIfPresent(String.self, forKey: .nutrientNumber)
        var unit = try c.decodeIfPresent(String.self, forKey: .unitName)

        // nested { "nutrient": { "id":..., "name":..., "number":..., "unitName":... } }
        if id == nil, name == nil, number == nil,
           let nested = try? c.nestedContainer(keyedBy: NestedKeys.self, forKey: .nutrient) {
            id = try nested.decodeIfPresent(Int.self, forKey: .id)
            name = try nested.decodeIfPresent(String.self, forKey: .name)
            number = try nested.decodeIfPresent(String.self, forKey: .number)
            if unit == nil {
                unit = try nested.decodeIfPresent(String.self, forKey: .unitName)
            }
        }

        self.nutrientId = id
        self.nutrientName = name
        self.nutrientNumber = number
        self.unitName = unit
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: TopKeys.self)
        try c.encodeIfPresent(nutrientId, forKey: .nutrientId)
        try c.encodeIfPresent(nutrientName, forKey: .nutrientName)
        try c.encodeIfPresent(nutrientNumber, forKey: .nutrientNumber)
        try c.encodeIfPresent(unitName, forKey: .unitName)
        try c.encodeIfPresent(amount, forKey: .amount)
    }
}

enum USDANutrientKind {
    case energy, protein, carbohydrate, fat, fiber

    // FDC uses both numeric IDs and nutrientNumber strings. Match on either.
    var fdcIds: [Int] {
        switch self {
        case .energy: return [1008, 2047, 2048] // kcal, atwater general, atwater specific
        case .protein: return [1003]
        case .carbohydrate: return [1005]
        case .fat: return [1004]
        case .fiber: return [1079]
        }
    }
    var fdcNumbers: [String] {
        switch self {
        case .energy: return ["208"]
        case .protein: return ["203"]
        case .carbohydrate: return ["205"]
        case .fat: return ["204"]
        case .fiber: return ["291"]
        }
    }
}
