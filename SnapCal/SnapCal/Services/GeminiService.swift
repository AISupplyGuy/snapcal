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
    private let model: String
    private let session: URLSession

    // Read from Info.plist / env. Never commit the key.
    init(
        apiKey: String? = ProcessInfo.processInfo.environment["GEMINI_API_KEY"]
            ?? (Bundle.main.object(forInfoDictionaryKey: "GEMINI_API_KEY") as? String),
        model: String = "gemini-2.5-flash",
        session: URLSession = .shared
    ) throws {
        guard let key = apiKey, !key.isEmpty else { throw GeminiError.missingAPIKey }
        self.apiKey = key
        self.model = model
        self.session = session
    }

    func identifyMeal(imageJPEG: Data) async throws -> GeminiMealResponse {
        let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent?key=\(apiKey)")!

        let body: [String: Any] = [
            "contents": [[
                "parts": [
                    ["text": GeminiPrompt.mealIdentification],
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

        let (data, response) = try await session.data(for: request)
        let rawBody = String(data: data, encoding: .utf8) ?? ""
        #if DEBUG
        print("[Gemini] status=\((response as? HTTPURLResponse)?.statusCode ?? -1)")
        print("[Gemini] body=\(rawBody)")
        #endif
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw GeminiError.httpError(status: status, body: rawBody)
        }

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
