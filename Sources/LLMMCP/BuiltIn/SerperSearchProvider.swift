import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// MARK: - SerperSearchProvider

/// Serper (Google SERP) REST APIを使用した検索プロバイダー
///
/// Serper APIキーが必要です。
/// https://serper.dev/ から取得できます。
///
/// ## 使用例
///
/// ```swift
/// let provider = SerperSearchProvider(apiKey: "YOUR_API_KEY", gl: "jp", hl: "ja")
/// let results = try await provider.search(query: "Swift concurrency", maxResults: 5)
/// ```
public final class SerperSearchProvider: WebSearchProvider, @unchecked Sendable {
    // MARK: - Properties

    private let apiKey: String
    private let gl: String?
    private let hl: String?
    private let session: URLSession
    private let timeout: TimeInterval

    // MARK: - Initialization

    /// SerperSearchProviderを作成
    ///
    /// - Parameters:
    ///   - apiKey: Serper APIキー
    ///   - gl: 地域コード（例: "jp"）
    ///   - hl: 言語コード（例: "ja"）
    ///   - timeout: リクエストのタイムアウト秒数（デフォルト: 15）
    public init(apiKey: String, gl: String? = nil, hl: String? = nil, timeout: TimeInterval = 15) {
        self.apiKey = apiKey
        self.gl = gl
        self.hl = hl
        self.timeout = timeout
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = timeout
        config.timeoutIntervalForResource = timeout * 2
        self.session = URLSession(configuration: config)
    }

    // MARK: - WebSearchProvider

    public func search(query: String, maxResults: Int) async throws -> [WebSearchResult] {
        guard let url = URL(string: "https://google.serper.dev/search") else {
            throw WebSearchError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "X-API-KEY")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var body: [String: Any] = [
            "q": query,
            "num": min(maxResults, 100)
        ]
        if let gl {
            body["gl"] = gl
        }
        if let hl {
            body["hl"] = hl
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw WebSearchError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw WebSearchError.httpError(statusCode: httpResponse.statusCode)
        }

        let serperResponse = try JSONDecoder().decode(SerperSearchResponse.self, from: data)

        return (serperResponse.organic ?? []).prefix(maxResults).map { result in
            WebSearchResult(
                title: result.title,
                url: result.link,
                snippet: result.snippet ?? ""
            )
        }
    }
}

// MARK: - Serper API Response Types

private struct SerperSearchResponse: Decodable {
    let organic: [SerperOrganicResult]?
}

private struct SerperOrganicResult: Decodable {
    let title: String
    let link: String
    let snippet: String?
}
