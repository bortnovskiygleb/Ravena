import Foundation

/// Talks to the app's own backend at `baseURL`. The backend is responsible for
/// deciding which underlying provider to call (DeepL for sentences, an LLM for
/// contextual word lookup) and for holding those provider API keys.
final class APITranslationService: TranslationService {

    private let baseURL: URL
    private let session: URLSession

    init(baseURL: URL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    func translateWord(_ word: String, contextSentence: String) async throws -> WordTranslation {
        let requestBody = WordTranslationRequest(word: word, contextSentence: contextSentence, targetLanguage: "ru")
        let response: WordTranslationResponse = try await post("translate/word", body: requestBody)
        return WordTranslation(
            word: word,
            translation: response.translation,
            partOfSpeech: response.partOfSpeech
        )
    }

    func translateSentence(_ sentence: String) async throws -> SentenceTranslation {
        let requestBody = SentenceTranslationRequest(sentence: sentence, targetLanguage: "ru")
        let response: SentenceTranslationResponse = try await post("translate/sentence", body: requestBody)
        return SentenceTranslation(original: sentence, translated: response.translated)
    }

    // MARK: - Networking

    private func post<Body: Encodable, Response: Decodable>(_ path: String, body: Body) async throws -> Response {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // Your own backend's auth (e.g. a per-device or per-user token) goes here —
        // NOT a DeepL/Anthropic key. That stays server-side.
        // request.setValue("Bearer \(deviceToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(body)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw TranslationError.network(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw TranslationError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "HTTP \(httpResponse.statusCode)"
            throw TranslationError.serverError(message)
        }

        do {
            return try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw TranslationError.invalidResponse
        }
    }
}

// MARK: - Wire models (backend request/response shapes)

private struct WordTranslationRequest: Encodable {
    let word: String
    let contextSentence: String
    let targetLanguage: String
}

private struct WordTranslationResponse: Decodable {
    let translation: String
    let partOfSpeech: String?
}

private struct SentenceTranslationRequest: Encodable {
    let sentence: String
    let targetLanguage: String
}

private struct SentenceTranslationResponse: Decodable {
    let translated: String
}
