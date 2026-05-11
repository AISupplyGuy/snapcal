import Foundation

enum GeminiError: LocalizedError {
    case missingAPIKey
    case invalidImage
    case httpError(status: Int, body: String)
    case noContent
    case jsonParse(String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey: return "GEMINI_API_KEY is not set."
        case .invalidImage: return "Could not encode the photo for upload."
        case .httpError(let status, let body):
            let trimmed = body.count > 400 ? String(body.prefix(400)) + "…" : body
            return "Gemini HTTP \(status): \(trimmed)"
        case .noContent: return "Gemini returned an empty response."
        case .jsonParse(let detail): return "Gemini JSON parse failed: \(detail)"
        }
    }
}

actor GeminiService {
    private let apiKey: String
    private let model: String        // default (Flash) model
    private let proModel: String     // escalation model for low-confidence cases
    private let session: URLSession

    var defaultModel: String { model }
    var escalationModel: String { proModel }

    // Resolution order: process env (Xcode scheme → only present when the
    // debugger is attached) → Secrets.plist bundled with the app (gitignored)
    // → Info.plist. Secrets.plist is what makes the app work when launched
    // standalone from the home screen.
    init(
        apiKey: String? = GeminiService.resolve("GEMINI_API_KEY"),
        model: String? = GeminiService.resolve("GEMINI_MODEL"),
        proModel: String? = GeminiService.resolve("GEMINI_PRO_MODEL"),
        session: URLSession = .shared
    ) throws {
        guard let key = apiKey, !key.isEmpty else { throw GeminiError.missingAPIKey }
        self.apiKey = key
        self.model = (model?.isEmpty == false ? model : nil) ?? "gemini-2.5-flash"
        // Pro fallback for low-confidence photos. 2.5 Pro pairs with the
        // 2.5 Flash default — same generation, identical prompt
        // compatibility, and both are public (no preview allowlist).
        self.proModel = (proModel?.isEmpty == false ? proModel : nil) ?? "gemini-2.5-pro"
        self.session = session
    }

    // Look up a config value across all three sources. Returns nil if none
    // provide a non-empty string.
    static func resolve(_ key: String) -> String? {
        if let v = ProcessInfo.processInfo.environment[key], !v.isEmpty { return v }
        if let v = Self.secretsPlistValue(key), !v.isEmpty { return v }
        if let v = Bundle.main.object(forInfoDictionaryKey: key) as? String, !v.isEmpty { return v }
        return nil
    }

    // Load Secrets.plist once per process. Bundled into the app at build
    // time (gitignored on disk), which lets the app work when launched
    // from the home screen with no debugger attached.
    private static let secretsPlist: [String: Any]? = {
        guard let url = Bundle.main.url(forResource: "Secrets", withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)
                as? [String: Any]
        else { return nil }
        return plist
    }()

    private static func secretsPlistValue(_ key: String) -> String? {
        secretsPlist?[key] as? String
    }

    func identifyMeal(
        imageJPEG: Data,
        supportedChains: [String] = [],
        modelOverride: String? = nil
    ) async throws -> GeminiMealResponse {
        let modelToUse = modelOverride ?? model
        let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(modelToUse):generateContent?key=\(apiKey)")!

        let body: [String: Any] = [
            "contents": [[
                "parts": [
                    ["text": GeminiPrompt.mealIdentification(supportedChains: supportedChains)],
                    ["inline_data": [
                        "mime_type": "image/jpeg",
                        "data": imageJPEG.base64EncodedString()
                    ]]
                ]
            ]],
            "generationConfig": [
                "responseMimeType": "application/json",
                "temperature": 0.2
            ]
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 120  // photo analysis can take 30-60s end-to-end

        // Retry transient conditions with exponential backoff:
        //   - HTTP 5xx / 429: Google-side overload
        //   - URL timeouts / network lost: flaky connection or slow model cold start
        let maxAttempts = 3
        var lastStatus = -1
        var lastBody = ""
        var lastURLError: Error?
        for attempt in 1...maxAttempts {
            do {
                let (data, response) = try await session.data(for: request)
                let rawBody = String(data: data, encoding: .utf8) ?? ""
                let status = (response as? HTTPURLResponse)?.statusCode ?? -1
                #if DEBUG
                print("[Gemini] model=\(modelToUse) attempt=\(attempt) status=\(status)")
                #endif
                if (200..<300).contains(status) {
                    return try Self.parseResponse(data: data, rawBody: rawBody)
                }
                lastStatus = status
                lastBody = rawBody
                lastURLError = nil
                let retryable = (status == 503 || status == 429 || status == 500 || status == 502)
                if !retryable || attempt == maxAttempts { break }
            } catch let err as URLError where [.timedOut, .networkConnectionLost, .notConnectedToInternet].contains(err.code) {
                #if DEBUG
                print("[Gemini] attempt=\(attempt) URLError=\(err.code.rawValue)")
                #endif
                lastURLError = err
                if attempt == maxAttempts { throw err }
            }
            let delayNs = UInt64(pow(2.0, Double(attempt))) * 500_000_000 // 1s, 2s, 4s
            try await Task.sleep(nanoseconds: delayNs)
        }
        if let urlErr = lastURLError { throw urlErr }
        throw GeminiError.httpError(status: lastStatus, body: lastBody)
    }

    // Text-only generation used by the Cook tab when the device can't run
    // Foundation Models on-device. Returns the raw text the model emits —
    // caller decodes into a typed struct. Asks for JSON via responseMimeType
    // so we don't have to strip code fences.
    func generateRecipeJSON(systemPrompt: String, userPrompt: String) async throws -> String {
        let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent?key=\(apiKey)")!
        let body: [String: Any] = [
            "system_instruction": ["parts": [["text": systemPrompt]]],
            "contents": [["parts": [["text": userPrompt]]]],
            "generationConfig": [
                "responseMimeType": "application/json",
                "temperature": 0.7
            ]
        ]
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 60

        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        let raw = String(data: data, encoding: .utf8) ?? ""
        guard (200..<300).contains(status) else {
            throw GeminiError.httpError(status: status, body: raw)
        }
        let envelope = try JSONDecoder().decode(GeminiEnvelope.self, from: data)
        guard let text = envelope.candidates.first?.content.parts.first?.text, !text.isEmpty else {
            throw GeminiError.noContent
        }
        return text
    }

    private static func parseResponse(data: Data, rawBody: String) throws -> GeminiMealResponse {
        #if DEBUG
        print("[Gemini] body=\(rawBody)")
        #endif

        let envelope = try JSONDecoder().decode(GeminiEnvelope.self, from: data)
        guard let text = envelope.candidates.first?.content.parts.first?.text, !text.isEmpty else {
            throw GeminiError.noContent
        }

        guard let jsonData = text.data(using: .utf8) else {
            throw GeminiError.jsonParse("non-utf8 text from Gemini")
        }
        do {
            return try JSONDecoder().decode(GeminiMealResponse.self, from: jsonData)
        } catch {
            throw GeminiError.jsonParse("decode failed: \(error.localizedDescription) — raw: \(text)")
        }
    }
}

// Raw envelope returned by Gemini's generateContent endpoint.
private struct GeminiEnvelope: Decodable {
    struct Candidate: Decodable {
        struct Content: Decodable {
            struct Part: Decodable { let text: String? }
            let parts: [Part]
        }
        let content: Content
    }
    let candidates: [Candidate]
}
