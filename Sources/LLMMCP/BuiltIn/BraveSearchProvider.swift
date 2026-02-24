import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// MARK: - BraveSearchProvider

/// Brave Search REST APIを使用した検索プロバイダー
///
/// Brave Search APIキーが必要です。
/// https://brave.com/search/api/ から取得できます。
///
/// ## 使用例
///
/// ```swift
/// let provider = BraveSearchProvider(apiKey: "YOUR_API_KEY")
/// let results = try await provider.search(query: "Swift concurrency", maxResults: 5)
/// ```
public final class BraveSearchProvider: WebSearchProvider, @unchecked Sendable {
    // MARK: - Properties

    private let apiKey: String
    private let searchLang: String?
    private let country: String?
    private let session: URLSession
    private let timeout: TimeInterval

    // MARK: - Initialization

    /// BraveSearchProviderを作成
    ///
    /// - Parameters:
    ///   - apiKey: Brave Search APIキー
    ///   - searchLang: 検索言語（例: "ja"）
    ///   - country: 国コード（例: "JP"）
    ///   - timeout: リクエストのタイムアウト秒数（デフォルト: 15）
    public init(apiKey: String, searchLang: String? = nil, country: String? = nil, timeout: TimeInterval = 15) {
        self.apiKey = apiKey
        self.searchLang = searchLang
        self.country = country
        self.timeout = timeout
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = timeout
        config.timeoutIntervalForResource = timeout * 2
        self.session = URLSession(configuration: config)
    }

    // MARK: - WebSearchProvider

    public func search(query: String, maxResults: Int) async throws -> [WebSearchResult] {
        var components = URLComponents(string: "https://api.search.brave.com/res/v1/web/search")!
        var queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "count", value: String(min(maxResults, 20)))
        ]
        if let searchLang {
            queryItems.append(URLQueryItem(name: "search_lang", value: searchLang))
        }
        if let country {
            queryItems.append(URLQueryItem(name: "country", value: country))
        }
        components.queryItems = queryItems

        guard let url = components.url else {
            throw WebSearchError.invalidQuery(query)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(apiKey, forHTTPHeaderField: "X-Subscription-Token")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw WebSearchError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw WebSearchError.httpError(statusCode: httpResponse.statusCode)
        }

        let braveResponse = try JSONDecoder().decode(BraveSearchResponse.self, from: data)

        return (braveResponse.web?.results ?? []).prefix(maxResults).map { result in
            WebSearchResult(
                title: result.title,
                url: result.url,
                snippet: result.description ?? ""
            )
        }
    }
}

// MARK: - Brave API Response Types

private struct BraveSearchResponse: Decodable {
    let web: BraveWebResults?
}

private struct BraveWebResults: Decodable {
    let results: [BraveWebResult]
}

private struct BraveWebResult: Decodable {
    let title: String
    let url: String
    let description: String?
}
