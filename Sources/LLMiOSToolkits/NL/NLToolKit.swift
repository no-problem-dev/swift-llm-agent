import Foundation
import LLMClient
import LLMTool
import LLMMCP
import NaturalLanguage

// MARK: - NLToolKit

/// 自然言語処理を提供する ToolKit
///
/// NaturalLanguage framework を使用して、言語判定・感情分析・
/// 固有表現抽出・トークン化を提供します。すべてオフラインで動作します。
///
/// ## 使用例
///
/// ```swift
/// let tools = ToolSet {
///     NLToolKit()
/// }
/// ```
///
/// ## 提供されるツール
///
/// - `detect_language`: テキストの言語を判定
/// - `analyze_sentiment`: テキストの感情分析
/// - `extract_entities`: テキストから固有表現を抽出
/// - `tokenize`: テキストのトークン化
public final class NLToolKit: ToolKit, Sendable {

    // MARK: - Properties

    public let name: String = "nl"

    // MARK: - Initialization

    public init() {}

    // MARK: - ToolKit Protocol

    public var tools: [any Tool] {
        [
            detectLanguageTool,
            analyzeSentimentTool,
            extractEntitiesTool,
            tokenizeTool,
        ]
    }

    // MARK: - detect_language

    private var detectLanguageTool: BuiltInTool {
        BuiltInTool(
            name: "detect_language",
            description: "Detect the language of the given text. "
                + "Returns the dominant language and confidence scores for top candidates.",
            inputSchema: .object(
                properties: [
                    "text": .string(description: "Text to analyze for language detection"),
                ],
                required: ["text"]
            ),
            annotations: ToolAnnotations(
                title: "Detect Language",
                readOnlyHint: true,
                openWorldHint: false
            )
        ) { data in
            struct Input: Codable { var text: String }
            let input = try JSONDecoder().decode(Input.self, from: data)

            let recognizer = NLLanguageRecognizer()
            recognizer.processString(input.text)

            let dominant = recognizer.dominantLanguage

            let hypotheses = recognizer.languageHypotheses(withMaximum: 5)
            let candidates = hypotheses.sorted { $0.value > $1.value }.map { lang, confidence in
                LanguageCandidate(
                    language: lang.rawValue,
                    languageName: Locale.current.localizedString(forLanguageCode: lang.rawValue) ?? lang.rawValue,
                    confidence: (confidence * 1000).rounded() / 1000
                )
            }

            struct DetectionResult: Codable {
                var dominantLanguage: String?
                var dominantLanguageName: String?
                var candidates: [LanguageCandidate]

                enum CodingKeys: String, CodingKey {
                    case dominantLanguage = "dominant_language"
                    case dominantLanguageName = "dominant_language_name"
                    case candidates
                }
            }

            let result = DetectionResult(
                dominantLanguage: dominant?.rawValue,
                dominantLanguageName: dominant.flatMap {
                    Locale.current.localizedString(forLanguageCode: $0.rawValue)
                },
                candidates: candidates
            )

            return try .encoded(result)
        }
    }

    // MARK: - analyze_sentiment

    private var analyzeSentimentTool: BuiltInTool {
        BuiltInTool(
            name: "analyze_sentiment",
            description: "Analyze the sentiment of the given text. "
                + "Returns a score from -1.0 (very negative) to 1.0 (very positive). "
                + "Can analyze the overall text or sentence by sentence.",
            inputSchema: .object(
                properties: [
                    "text": .string(description: "Text to analyze for sentiment"),
                    "by_sentence": .boolean(
                        description: "If true, analyze each sentence separately (default: false)"
                    ),
                ],
                required: ["text"]
            ),
            annotations: ToolAnnotations(
                title: "Analyze Sentiment",
                readOnlyHint: true,
                openWorldHint: false
            )
        ) { data in
            struct Input: Codable {
                var text: String
                var bySentence: Bool?
                enum CodingKeys: String, CodingKey {
                    case text
                    case bySentence = "by_sentence"
                }
            }
            let input = try JSONDecoder().decode(Input.self, from: data)

            let tagger = NLTagger(tagSchemes: [.sentimentScore])
            tagger.string = input.text

            if input.bySentence == true {
                var sentences: [SentenceSentiment] = []
                tagger.enumerateTags(
                    in: input.text.startIndex..<input.text.endIndex,
                    unit: .sentence,
                    scheme: .sentimentScore,
                    options: [.omitWhitespace]
                ) { tag, range in
                    let sentence = String(input.text[range])
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    let score = tag.flatMap { Double($0.rawValue) } ?? 0
                    if !sentence.isEmpty {
                        sentences.append(SentenceSentiment(
                            sentence: sentence,
                            score: (score * 1000).rounded() / 1000,
                            label: Self.sentimentLabel(score)
                        ))
                    }
                    return true
                }

                struct SentenceResult: Codable {
                    var sentences: [SentenceSentiment]
                }
                return try .encoded(SentenceResult(sentences: sentences))
            } else {
                // 全体のセンチメント
                var totalScore = 0.0
                var count = 0
                tagger.enumerateTags(
                    in: input.text.startIndex..<input.text.endIndex,
                    unit: .sentence,
                    scheme: .sentimentScore,
                    options: [.omitWhitespace]
                ) { tag, _ in
                    if let score = tag.flatMap({ Double($0.rawValue) }) {
                        totalScore += score
                        count += 1
                    }
                    return true
                }

                let avgScore = count > 0 ? totalScore / Double(count) : 0

                struct OverallResult: Codable {
                    var score: Double
                    var label: String
                }
                return try .encoded(OverallResult(
                    score: (avgScore * 1000).rounded() / 1000,
                    label: Self.sentimentLabel(avgScore)
                ))
            }
        }
    }

    // MARK: - extract_entities

    private var extractEntitiesTool: BuiltInTool {
        BuiltInTool(
            name: "extract_entities",
            description: "Extract named entities from text. "
                + "Finds person names, place names, organization names, and other entities.",
            inputSchema: .object(
                properties: [
                    "text": .string(description: "Text to extract entities from"),
                ],
                required: ["text"]
            ),
            annotations: ToolAnnotations(
                title: "Extract Entities",
                readOnlyHint: true,
                openWorldHint: false
            )
        ) { data in
            struct Input: Codable { var text: String }
            let input = try JSONDecoder().decode(Input.self, from: data)

            let tagger = NLTagger(tagSchemes: [.nameType])
            tagger.string = input.text

            var entities: [EntityInfo] = []
            let options: NLTagger.Options = [.omitPunctuation, .omitWhitespace, .joinNames]

            tagger.enumerateTags(
                in: input.text.startIndex..<input.text.endIndex,
                unit: .word,
                scheme: .nameType,
                options: options
            ) { tag, range in
                guard let tag else { return true }
                let entityType: String?
                switch tag {
                case .personalName: entityType = "person"
                case .placeName: entityType = "place"
                case .organizationName: entityType = "organization"
                default: entityType = nil
                }

                if let type = entityType {
                    entities.append(EntityInfo(
                        text: String(input.text[range]),
                        type: type,
                        range: "\(range.lowerBound)...\(range.upperBound)"
                    ))
                }
                return true
            }

            struct EntitiesResult: Codable {
                var entities: [EntityInfo]
                var count: Int
            }
            return try .encoded(EntitiesResult(
                entities: entities,
                count: entities.count
            ))
        }
    }

    // MARK: - tokenize

    private var tokenizeTool: BuiltInTool {
        BuiltInTool(
            name: "tokenize",
            description: "Tokenize text into words or sentences. "
                + "Useful for text preprocessing and analysis.",
            inputSchema: .object(
                properties: [
                    "text": .string(description: "Text to tokenize"),
                    "unit": .string(
                        description: "Tokenization unit: 'word' (default), 'sentence', or 'paragraph'"
                    ),
                ],
                required: ["text"]
            ),
            annotations: ToolAnnotations(
                title: "Tokenize",
                readOnlyHint: true,
                openWorldHint: false
            )
        ) { data in
            struct Input: Codable {
                var text: String
                var unit: String?
            }
            let input = try JSONDecoder().decode(Input.self, from: data)

            let unit: NLTokenUnit
            switch input.unit?.lowercased() {
            case "sentence": unit = .sentence
            case "paragraph": unit = .paragraph
            default: unit = .word
            }

            let tokenizer = NLTokenizer(unit: unit)
            tokenizer.string = input.text

            var tokens: [String] = []
            tokenizer.enumerateTokens(
                in: input.text.startIndex..<input.text.endIndex
            ) { range, _ in
                let token = String(input.text[range])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !token.isEmpty {
                    tokens.append(token)
                }
                return true
            }

            struct TokenizeResult: Codable {
                var tokens: [String]
                var count: Int
                var unit: String
            }
            let unitName: String
            switch unit {
            case .sentence: unitName = "sentence"
            case .paragraph: unitName = "paragraph"
            default: unitName = "word"
            }
            return try .encoded(TokenizeResult(
                tokens: tokens,
                count: tokens.count,
                unit: unitName
            ))
        }
    }

    // MARK: - Helpers

    private static func sentimentLabel(_ score: Double) -> String {
        switch score {
        case 0.3...: return "positive"
        case (-0.3)...0.3: return "neutral"
        default: return "negative"
        }
    }
}

// MARK: - Supporting Types

struct LanguageCandidate: Codable, Sendable {
    var language: String
    var languageName: String
    var confidence: Double

    enum CodingKeys: String, CodingKey {
        case language
        case languageName = "language_name"
        case confidence
    }
}

struct SentenceSentiment: Codable, Sendable {
    var sentence: String
    var score: Double
    var label: String
}

struct EntityInfo: Codable, Sendable {
    var text: String
    var type: String
    var range: String
}
