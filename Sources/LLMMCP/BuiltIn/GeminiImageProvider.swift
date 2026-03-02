import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import LLMClient

// MARK: - GeminiImageProvider

/// Google Imagen 4 を使用した画像生成プロバイダー
///
/// Gemini API キーが必要です。
/// `POST https://generativelanguage.googleapis.com/v1beta/models/imagen-4.0-generate-001:predict` を直接呼び出します。
public final class GeminiImageProvider: ImageGenerationProvider, @unchecked Sendable {
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
        let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/imagen-4.0-generate-001:predict")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let requestBody = ImagenRequest(
            instances: [ImagenInstance(prompt: prompt)],
            parameters: ImagenParameters(
                sampleCount: 1,
                aspectRatio: imagenAspectRatio(size),
                personGeneration: "allow_all"
            )
        )

        request.httpBody = try JSONEncoder().encode(requestBody)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ImageGenerationToolError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            if httpResponse.statusCode == 400 {
                // Check for content policy violation
                if let errorBody = String(data: data, encoding: .utf8),
                   errorBody.contains("SAFETY") || errorBody.contains("policy") {
                    throw ImageGenerationToolError.contentPolicyViolation
                }
            }
            throw ImageGenerationToolError.httpError(statusCode: httpResponse.statusCode)
        }

        let apiResponse = try JSONDecoder().decode(ImagenResponse.self, from: data)

        guard let firstPrediction = apiResponse.predictions.first else {
            throw ImageGenerationToolError.invalidResponse
        }

        guard let imageData = Data(base64Encoded: firstPrediction.bytesBase64Encoded) else {
            throw ImageGenerationToolError.invalidResponse
        }

        let mimeType = ImageMediaType(rawValue: firstPrediction.mimeType) ?? .png

        return GeneratedImageData(
            data: imageData,
            mimeType: mimeType
        )
    }

    // MARK: - Private

    private func imagenAspectRatio(_ size: ImageGenerationSize) -> String {
        switch size {
        case .square: "1:1"
        case .landscape: "16:9"
        case .portrait: "9:16"
        }
    }
}

// MARK: - API Types

private struct ImagenRequest: Encodable {
    let instances: [ImagenInstance]
    let parameters: ImagenParameters
}

private struct ImagenInstance: Encodable {
    let prompt: String
}

private struct ImagenParameters: Encodable {
    let sampleCount: Int
    let aspectRatio: String
    let personGeneration: String
}

private struct ImagenResponse: Decodable {
    let predictions: [ImagenPrediction]
}

private struct ImagenPrediction: Decodable {
    let bytesBase64Encoded: String
    let mimeType: String
}
