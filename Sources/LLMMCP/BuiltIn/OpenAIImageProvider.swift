import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import LLMClient

// MARK: - OpenAIImageProvider

/// OpenAI gpt-image-1 を使用した画像生成プロバイダー
///
/// OpenAI API キーが必要です。
/// `POST https://api.openai.com/v1/images/generations` を直接呼び出します。
public final class OpenAIImageProvider: ImageGenerationProvider, @unchecked Sendable {
    // MARK: - Properties

    private let apiKey: String
    private let session: URLSession
    private let timeout: TimeInterval

    // MARK: - Initialization

    public init(apiKey: String, timeout: TimeInterval = 60) {
        self.apiKey = apiKey
        self.timeout = timeout
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = timeout
        config.timeoutIntervalForResource = timeout * 2
        self.session = URLSession(configuration: config)
    }

    // MARK: - ImageGenerationProvider

    public func generateImage(prompt: String, size: ImageGenerationSize, quality: ImageGenerationQuality) async throws -> GeneratedImageData {
        let url = URL(string: "https://api.openai.com/v1/images/generations")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let requestBody = OpenAIImageRequest(
            model: "gpt-image-1",
            prompt: prompt,
            n: 1,
            size: openAISize(size),
            quality: quality == .hd ? "high" : "auto",
            outputFormat: "png"
        )

        request.httpBody = try JSONEncoder().encode(requestBody)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ImageGenerationToolError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            if httpResponse.statusCode == 400 {
                // Check if it's a content policy violation
                if let errorResponse = try? JSONDecoder().decode(OpenAIErrorResponse.self, from: data),
                   errorResponse.error.code == "content_policy_violation" {
                    throw ImageGenerationToolError.contentPolicyViolation
                }
            }
            throw ImageGenerationToolError.httpError(statusCode: httpResponse.statusCode)
        }

        let apiResponse = try JSONDecoder().decode(OpenAIImageResponse.self, from: data)

        guard let firstImage = apiResponse.data.first else {
            throw ImageGenerationToolError.invalidResponse
        }

        guard let imageData = Data(base64Encoded: firstImage.b64Json) else {
            throw ImageGenerationToolError.invalidResponse
        }

        return GeneratedImageData(
            data: imageData,
            mimeType: .png,
            revisedPrompt: firstImage.revisedPrompt
        )
    }

    // MARK: - Private

    private func openAISize(_ size: ImageGenerationSize) -> String {
        switch size {
        case .square: "1024x1024"
        case .landscape: "1536x1024"
        case .portrait: "1024x1536"
        }
    }
}

// MARK: - API Types

private struct OpenAIImageRequest: Encodable {
    let model: String
    let prompt: String
    let n: Int
    let size: String
    let quality: String
    let outputFormat: String

    enum CodingKeys: String, CodingKey {
        case model, prompt, n, size, quality
        case outputFormat = "output_format"
    }
}

private struct OpenAIImageResponse: Decodable {
    let data: [OpenAIImageData]
}

private struct OpenAIImageData: Decodable {
    let b64Json: String
    let revisedPrompt: String?

    enum CodingKeys: String, CodingKey {
        case b64Json = "b64_json"
        case revisedPrompt = "revised_prompt"
    }
}

private struct OpenAIErrorResponse: Decodable {
    let error: OpenAIErrorDetail
}

private struct OpenAIErrorDetail: Decodable {
    let message: String
    let code: String?
}
