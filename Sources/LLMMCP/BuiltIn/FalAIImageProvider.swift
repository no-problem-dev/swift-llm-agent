import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import LLMClient

// MARK: - FalAIImageProvider

/// fal.ai FLUX.2 Schnell を使用した画像生成プロバイダー
///
/// fal.ai API キーが必要です。
/// `POST https://fal.run/fal-ai/flux/schnell` を直接呼び出します。
public final class FalAIImageProvider: ImageGenerationProvider, @unchecked Sendable {
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
        let url = URL(string: "https://fal.run/fal-ai/flux/schnell")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Key \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (width, height) = falSize(size)
        let requestBody = FalImageRequest(
            prompt: prompt,
            imageSize: FalImageSize(width: width, height: height),
            numImages: 1
        )

        request.httpBody = try JSONEncoder().encode(requestBody)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ImageGenerationToolError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw ImageGenerationToolError.httpError(statusCode: httpResponse.statusCode)
        }

        let apiResponse = try JSONDecoder().decode(FalImageResponse.self, from: data)

        guard let firstImage = apiResponse.images.first else {
            throw ImageGenerationToolError.invalidResponse
        }

        // fal.ai returns a URL; download the image
        guard let imageURL = URL(string: firstImage.url) else {
            throw ImageGenerationToolError.invalidResponse
        }

        let (imageData, imageResponse) = try await session.data(from: imageURL)

        guard let imageHttpResponse = imageResponse as? HTTPURLResponse,
              (200...299).contains(imageHttpResponse.statusCode) else {
            throw ImageGenerationToolError.imageDownloadFailed
        }

        // Determine format from content type or default to jpeg
        let mimeType: ImageMediaType
        if let contentType = imageHttpResponse.value(forHTTPHeaderField: "Content-Type") {
            mimeType = ImageMediaType(rawValue: contentType) ?? .jpeg
        } else {
            mimeType = .jpeg
        }

        return GeneratedImageData(
            data: imageData,
            mimeType: mimeType
        )
    }

    // MARK: - Private

    private func falSize(_ size: ImageGenerationSize) -> (width: Int, height: Int) {
        switch size {
        case .square: (1024, 1024)
        case .landscape: (1536, 1024)
        case .portrait: (1024, 1536)
        }
    }
}

// MARK: - API Types

private struct FalImageRequest: Encodable {
    let prompt: String
    let imageSize: FalImageSize
    let numImages: Int

    enum CodingKeys: String, CodingKey {
        case prompt
        case imageSize = "image_size"
        case numImages = "num_images"
    }
}

private struct FalImageSize: Encodable {
    let width: Int
    let height: Int
}

private struct FalImageResponse: Decodable {
    let images: [FalImage]
}

private struct FalImage: Decodable {
    let url: String
    let contentType: String?

    enum CodingKeys: String, CodingKey {
        case url
        case contentType = "content_type"
    }
}
