import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import LLMClient
import LLMTool

// MARK: - WebSearchProvider Protocol

/// Web検索プロバイダーのプロトコル
///
/// 異なる検索エンジンバックエンドを差し替え可能にするための抽象化です。
///
/// ## 使用例
///
/// ```swift
/// let provider = DuckDuckGoSearchProvider()
/// let results = try await provider.search(query: "Swift concurrency", maxResults: 5)
/// ```
public protocol WebSearchProvider: Sendable {
    /// 検索を実行
    ///
    /// - Parameters:
    ///   - query: 検索クエリ
    ///   - maxResults: 最大結果数
    /// - Returns: 検索結果の配列
    func search(query: String, maxResults: Int) async throws -> [WebSearchResult]
}

// MARK: - WebSearchResult

/// Web検索の結果
public struct WebSearchResult: Codable, Sendable {
    /// ページタイトル
    public let title: String

    /// ページURL
    public let url: String

    /// 検索結果のスニペット
    public let snippet: String

    public init(title: String, url: String, snippet: String) {
        self.title = title
        self.url = url
        self.snippet = snippet
    }
}

// MARK: - DuckDuckGoSearchProvider

/// DuckDuckGo HTML APIを使用した検索プロバイダー
///
/// APIキー不要でWeb検索を実行できます。
/// DuckDuckGoのHTML検索ページをパースして結果を抽出します。
public final class DuckDuckGoSearchProvider: WebSearchProvider, @unchecked Sendable {
    // MARK: - Properties

    private let session: URLSession
    private let timeout: TimeInterval

    // MARK: - Initialization

    /// DuckDuckGoSearchProviderを作成
    ///
    /// - Parameter timeout: リクエストのタイムアウト秒数（デフォルト: 15）
    public init(timeout: TimeInterval = 15) {
        self.timeout = timeout
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = timeout
        config.timeoutIntervalForResource = timeout * 2
        self.session = URLSession(configuration: config)
    }

    // MARK: - WebSearchProvider

    public func search(query: String, maxResults: Int) async throws -> [WebSearchResult] {
        guard let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            throw WebSearchError.invalidQuery(query)
        }

        let urlString = "https://html.duckduckgo.com/html/?q=\(encodedQuery)"
        guard let url = URL(string: urlString) else {
            throw WebSearchError.invalidQuery(query)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("text/html", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw WebSearchError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw WebSearchError.httpError(statusCode: httpResponse.statusCode)
        }

        guard let html = String(data: data, encoding: .utf8)
                ?? String(data: data, encoding: .ascii) else {
            throw WebSearchError.encodingError
        }

        let results = Self.parseResults(from: html, maxResults: maxResults)
        return results
    }

    // MARK: - HTML Parsing

    /// DuckDuckGoのHTML検索結果をパース
    static func parseResults(from html: String, maxResults: Int) -> [WebSearchResult] {
        var results: [WebSearchResult] = []

        // DuckDuckGo HTML API returns results in <div class="result"> blocks
        // Each contains <a class="result__a"> for title/URL and
        // <a class="result__snippet"> for the snippet
        let resultPattern = #"<div[^>]*class="[^"]*result\b[^"]*"[^>]*>([\s\S]*?)</div>\s*(?=<div[^>]*class="[^"]*result\b|$)"#
        guard let resultRegex = try? NSRegularExpression(pattern: resultPattern, options: []) else {
            return results
        }

        let resultMatches = resultRegex.matches(in: html, range: NSRange(html.startIndex..., in: html))

        for match in resultMatches {
            guard results.count < maxResults else { break }
            guard let blockRange = Range(match.range(at: 1), in: html) else { continue }
            let block = String(html[blockRange])

            // タイトルとURLを抽出
            let linkPattern = #"<a[^>]*class="[^"]*result__a[^"]*"[^>]*href="([^"]*)"[^>]*>([\s\S]*?)</a>"#
            guard let linkRegex = try? NSRegularExpression(pattern: linkPattern, options: []),
                  let linkMatch = linkRegex.firstMatch(in: block, range: NSRange(block.startIndex..., in: block)),
                  let urlRange = Range(linkMatch.range(at: 1), in: block),
                  let titleRange = Range(linkMatch.range(at: 2), in: block) else {
                continue
            }

            let rawURL = String(block[urlRange])
            let rawTitle = String(block[titleRange])

            // URLをデコード（DuckDuckGoはリダイレクトURLを使うことがある）
            let resolvedURL = Self.resolveURL(rawURL)

            // 有効なURLかチェック
            guard resolvedURL.hasPrefix("http://") || resolvedURL.hasPrefix("https://") else {
                continue
            }

            // スニペットを抽出
            let snippetPattern = #"<a[^>]*class="[^"]*result__snippet[^"]*"[^>]*>([\s\S]*?)</a>"#
            let snippet: String
            if let snippetRegex = try? NSRegularExpression(pattern: snippetPattern, options: []),
               let snippetMatch = snippetRegex.firstMatch(in: block, range: NSRange(block.startIndex..., in: block)),
               let snippetRange = Range(snippetMatch.range(at: 1), in: block) {
                snippet = Self.stripHTML(String(block[snippetRange]))
            } else {
                snippet = ""
            }

            let title = Self.stripHTML(rawTitle)
            guard !title.isEmpty else { continue }

            results.append(WebSearchResult(
                title: title,
                url: resolvedURL,
                snippet: snippet
            ))
        }

        return results
    }

    /// DuckDuckGoのリダイレクトURLを解決
    private static func resolveURL(_ rawURL: String) -> String {
        // DuckDuckGo uses //duckduckgo.com/l/?uddg=<encoded_url>&rut=... format
        if rawURL.contains("duckduckgo.com/l/") || rawURL.contains("uddg=") {
            // uddg パラメータからURLを抽出
            if let range = rawURL.range(of: "uddg="),
               let endRange = rawURL[range.upperBound...].range(of: "&") {
                let encoded = String(rawURL[range.upperBound..<endRange.lowerBound])
                if let decoded = encoded.removingPercentEncoding {
                    return decoded
                }
            } else if let range = rawURL.range(of: "uddg=") {
                let encoded = String(rawURL[range.upperBound...])
                if let decoded = encoded.removingPercentEncoding {
                    return decoded
                }
            }
        }
        return rawURL
    }

    /// HTMLタグを除去してプレーンテキストに変換
    private static func stripHTML(_ html: String) -> String {
        var text = html
        // HTMLタグを除去
        if let regex = try? NSRegularExpression(pattern: "<[^>]+>", options: []) {
            text = regex.stringByReplacingMatches(
                in: text,
                range: NSRange(text.startIndex..., in: text),
                withTemplate: ""
            )
        }
        // HTMLエンティティを基本的にデコード
        let entities: [(String, String)] = [
            ("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"),
            ("&quot;", "\""), ("&apos;", "'"), ("&#39;", "'"),
            ("&nbsp;", " "),
        ]
        for (entity, replacement) in entities {
            text = text.replacingOccurrences(of: entity, with: replacement)
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - WebSearchToolKit

/// Web検索ツールを提供するToolKit
///
/// Web検索を実行し、タイトル・URL・スニペットの一覧を返します。
/// デフォルトではDuckDuckGoをバックエンドとして使用します（APIキー不要）。
///
/// ## 使用例
///
/// ```swift
/// let tools = ToolSet {
///     WebSearchToolKit()
/// }
///
/// // カスタムプロバイダーを使用
/// let tools = ToolSet {
///     WebSearchToolKit(provider: MyCustomSearchProvider())
/// }
/// ```
///
/// ## 提供されるツール
///
/// - `web_search`: クエリでWeb検索を実行し、結果一覧を返す
public final class WebSearchToolKit: ToolKit, @unchecked Sendable {
    // MARK: - Properties

    public let name: String = "web_search"

    /// 検索プロバイダー
    private let provider: any WebSearchProvider

    // MARK: - Initialization

    /// WebSearchToolKitを作成
    ///
    /// - Parameter provider: 検索プロバイダー（デフォルト: DuckDuckGo）
    public init(provider: (any WebSearchProvider)? = nil) {
        self.provider = provider ?? DuckDuckGoSearchProvider()
    }

    // MARK: - ToolKit Protocol

    public var tools: [any Tool] {
        [
            webSearchTool
        ]
    }

    // MARK: - Tool Definitions

    /// web_search ツール
    private var webSearchTool: BuiltInTool {
        BuiltInTool(
            name: "web_search",
            description: "Search the web and return a list of results with titles, URLs, and snippets. Use this to find information, discover URLs, or research topics.",
            inputSchema: .object(
                properties: [
                    "query": .string(description: "The search query"),
                    "max_results": .integer(description: "Maximum number of results to return (1-10, default: 5)")
                ],
                required: ["query"]
            ),
            annotations: ToolAnnotations(
                title: "Web Search",
                readOnlyHint: true,
                openWorldHint: true
            )
        ) { [self] data in
            let input = try JSONDecoder().decode(WebSearchInput.self, from: data)

            let maxResults = min(max(input.maxResults ?? 5, 1), 10)

            let results = try await provider.search(query: input.query, maxResults: maxResults)

            let output = WebSearchOutput(
                query: input.query,
                resultCount: results.count,
                results: results
            )

            let encoded = try JSONEncoder().encode(output)
            return .json(encoded)
        }
    }
}

// MARK: - Input / Output Types

private struct WebSearchInput: Codable {
    var query: String
    var maxResults: Int?

    enum CodingKeys: String, CodingKey {
        case query
        case maxResults = "max_results"
    }
}

private struct WebSearchOutput: Codable {
    var query: String
    var resultCount: Int
    var results: [WebSearchResult]

    enum CodingKeys: String, CodingKey {
        case query
        case resultCount = "result_count"
        case results
    }
}

// MARK: - Errors

/// WebSearchToolKitのエラー
public enum WebSearchError: Error, LocalizedError {
    case invalidQuery(String)
    case invalidResponse
    case httpError(statusCode: Int)
    case encodingError
    case noResults

    public var errorDescription: String? {
        switch self {
        case .invalidQuery(let query):
            return "Invalid search query: \(query). Try rephrasing your query."
        case .invalidResponse:
            return "Search engine returned an invalid response. Try again or rephrase your query."
        case .httpError(let statusCode):
            switch statusCode {
            case 429:
                return "Search rate limited (HTTP 429). Wait before retrying."
            case 403:
                return "Search access blocked (HTTP 403). Try again later."
            default:
                return "Search failed with HTTP \(statusCode). Try again or rephrase your query."
            }
        case .encodingError:
            return "Cannot decode the search results. Try again."
        case .noResults:
            return "No results found. Try different keywords or a broader query."
        }
    }
}
