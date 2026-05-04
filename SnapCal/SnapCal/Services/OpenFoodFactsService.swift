import Foundation

// Layer 2 of ARCHITECTURE.md: barcode-first UX for packaged food.
// Open Food Facts is a free, ~3M-product database keyed by UPC/EAN.
// We never auto-select when the API returns multiple entries for the
// same code — the user picks. After selection we hand the product to
// TrackViewModel.commitBarcode which writes a MealEntry directly,
// skipping Gemini and the NutritionRouter entirely.
actor OpenFoodFactsService {
    static let shared = OpenFoodFactsService()

    private var cache: [String: [BarcodeProduct]] = [:]
    private let session: URLSession
    private let decoder: JSONDecoder

    init(session: URLSession = .shared) {
        self.session = session
        self.decoder = JSONDecoder()
    }

    func products(for barcode: String) async throws -> [BarcodeProduct] {
        if let hit = cache[barcode] { return hit }

        // Search endpoint returns *all* products that share the code (private
        // labels, regional repacks). It's also the heaviest endpoint and the
        // first to 5xx under load — if it errors or returns nothing, fall
        // through to the lighter single-product endpoint.
        let resolved: [BarcodeProduct]
        do {
            let searched = try await search(code: barcode)
            resolved = searched.isEmpty ? try await singleProduct(code: barcode) : searched
        } catch {
            resolved = try await singleProduct(code: barcode)
        }

        cache[barcode] = resolved
        return resolved
    }

    private func search(code: String) async throws -> [BarcodeProduct] {
        var components = URLComponents(string: "https://world.openfoodfacts.org/api/v2/search")!
        components.queryItems = [
            URLQueryItem(name: "code", value: code),
            URLQueryItem(name: "fields", value: Self.fields),
            URLQueryItem(name: "page_size", value: "10")
        ]
        let payload: SearchResponse = try await fetch(components.url!)
        return payload.products.compactMap { BarcodeProduct(raw: $0) }
    }

    private func singleProduct(code: String) async throws -> [BarcodeProduct] {
        var components = URLComponents(string: "https://world.openfoodfacts.org/api/v2/product/\(code).json")!
        components.queryItems = [URLQueryItem(name: "fields", value: Self.fields)]
        let payload: SingleResponse = try await fetch(components.url!)
        guard payload.status == 1, let raw = payload.product, let product = BarcodeProduct(raw: raw) else {
            return []
        }
        return [product]
    }

    private func fetch<T: Decodable>(_ url: URL) async throws -> T {
        var request = URLRequest(url: url)
        // OFF's etiquette page asks for "AppName/Version (contact)" so they
        // can reach out before throttling. Generic UAs get rate-limited first.
        request.setValue("SnapCal-iOS/1.0 (https://snapcal.app)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 12

        // One retry on 5xx — OFF's public API is occasionally overloaded
        // and a single short backoff fixes most transient 503s.
        for attempt in 0..<2 {
            let (data, response) = try await session.data(for: request)
            if let http = response as? HTTPURLResponse {
                if (500...599).contains(http.statusCode), attempt == 0 {
                    try await Task.sleep(nanoseconds: 600_000_000)
                    continue
                }
                if !(200...299).contains(http.statusCode) {
                    throw OpenFoodFactsError.http(http.statusCode)
                }
            }
            return try decoder.decode(T.self, from: data)
        }
        throw OpenFoodFactsError.http(503)
    }

    private static let fields = "code,product_name,generic_name,brands,image_front_url,image_url,serving_size,serving_quantity,nutriments"
}

enum OpenFoodFactsError: Error, LocalizedError {
    case http(Int)
    case noNutrition

    var errorDescription: String? {
        switch self {
        case .http(let code): return "Open Food Facts returned HTTP \(code)."
        case .noNutrition:    return "We couldn't read nutrition for this product."
        }
    }
}

// MARK: - Public model (consumed by views and TrackViewModel)

struct BarcodeProduct: Identifiable, Sendable, Equatable {
    let id: String           // OFF code or fingerprint
    let barcode: String
    let displayName: String
    let brand: String?
    let imageURL: URL?
    let servingGrams: Double?
    let per100g: NutritionFacts

    init?(raw: OpenFoodFactsService.RawProduct) {
        guard let n = raw.nutriments, let kcal = n.energyKcal100g, kcal > 0 else { return nil }
        self.barcode = raw.code ?? ""
        self.id = raw.code ?? UUID().uuidString
        self.displayName = (raw.productName?.trimmed.nonEmpty
            ?? raw.genericName?.trimmed.nonEmpty
            ?? "Unknown product")
        self.brand = raw.brands?.split(separator: ",").first.map { $0.trimmingCharacters(in: .whitespaces) }
        self.imageURL = (raw.imageFrontUrl ?? raw.imageUrl).flatMap(URL.init(string:))
        self.servingGrams = raw.servingQuantity ?? Self.parseGrams(raw.servingSize)
        self.per100g = NutritionFacts(
            calories: kcal,
            proteinGrams: n.proteins100g ?? 0,
            carbGrams: n.carbohydrates100g ?? 0,
            fatGrams: n.fat100g ?? 0,
            fiberGrams: n.fiber100g ?? 0
        )
    }

    private static func parseGrams(_ text: String?) -> Double? {
        guard let text else { return nil }
        let scanner = Scanner(string: text)
        scanner.charactersToBeSkipped = .whitespaces
        guard let value = scanner.scanDouble(), value > 0 else { return nil }
        let rest = text[scanner.currentIndex...].lowercased()
        if rest.contains("g") || rest.contains("ml") { return value }
        return nil
    }
}

// MARK: - Decoding shapes (internal)

extension OpenFoodFactsService {
    struct SingleResponse: Decodable {
        let status: Int
        let product: RawProduct?
    }

    struct SearchResponse: Decodable {
        let products: [RawProduct]
    }

    struct RawProduct: Decodable {
        let code: String?
        let productName: String?
        let genericName: String?
        let brands: String?
        let imageFrontUrl: String?
        let imageUrl: String?
        let servingSize: String?
        let servingQuantity: Double?
        let nutriments: Nutriments?

        enum CodingKeys: String, CodingKey {
            case code
            case productName = "product_name"
            case genericName = "generic_name"
            case brands
            case imageFrontUrl = "image_front_url"
            case imageUrl = "image_url"
            case servingSize = "serving_size"
            case servingQuantity = "serving_quantity"
            case nutriments
        }

        // serving_quantity arrives as a number in most responses but ships
        // as a quoted string for some legacy entries. Tolerate both.
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            self.code = try c.decodeIfPresent(String.self, forKey: .code)
            self.productName = try c.decodeIfPresent(String.self, forKey: .productName)
            self.genericName = try c.decodeIfPresent(String.self, forKey: .genericName)
            self.brands = try c.decodeIfPresent(String.self, forKey: .brands)
            self.imageFrontUrl = try c.decodeIfPresent(String.self, forKey: .imageFrontUrl)
            self.imageUrl = try c.decodeIfPresent(String.self, forKey: .imageUrl)
            self.servingSize = try c.decodeIfPresent(String.self, forKey: .servingSize)
            if let n = try? c.decodeIfPresent(Double.self, forKey: .servingQuantity) {
                self.servingQuantity = n
            } else if let s = try? c.decodeIfPresent(String.self, forKey: .servingQuantity), let n = Double(s) {
                self.servingQuantity = n
            } else {
                self.servingQuantity = nil
            }
            self.nutriments = try c.decodeIfPresent(Nutriments.self, forKey: .nutriments)
        }
    }

    struct Nutriments: Decodable {
        let energyKcal100g: Double?
        let proteins100g: Double?
        let carbohydrates100g: Double?
        let fat100g: Double?
        let fiber100g: Double?

        enum CodingKeys: String, CodingKey {
            case energyKcal100g = "energy-kcal_100g"
            case proteins100g = "proteins_100g"
            case carbohydrates100g = "carbohydrates_100g"
            case fat100g = "fat_100g"
            case fiber100g = "fiber_100g"
        }
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
    var nonEmpty: String? { isEmpty ? nil : self }
}
