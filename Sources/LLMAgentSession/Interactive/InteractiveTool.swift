import Foundation
import LLMTool

// MARK: - InteractiveTool

/// インタラクティブツールプロトコル
///
/// `Tool` プロトコルを拡張し、実行時に UI インタラクションを要求するツールを表す。
/// セッションのランループはこのプロトコルに準拠したツールを検出すると、
/// `InteractionRequest` を生成して UI に suspend する。
///
/// ## 設計
///
/// 通常のツールは `execute(with:)` で即座に結果を返すが、
/// `InteractiveTool` は以下の 2 段階フローで処理される:
///
/// 1. **Request 生成**: `makeInteractionRequest(from:)` で UI に表示する要求を生成
/// 2. **Response 変換**: ユーザー操作後に `makeToolResult(from:)` で ToolResult に変換
///
/// この間、セッションのランループは suspend し、UI が `respond()` を呼ぶまで待機する。
///
/// インタラクションの種類はペイロードの型で決定される。
/// `InteractionType` enum は不要。
///
/// ## 使用例
///
/// ```swift
/// struct ConfirmActionTool: InteractiveTool {
///     func makeInteractionRequest(from arguments: Data) throws -> InteractionRequest {
///         let proposal = // decode from arguments
///         return InteractionRequest(
///             prompt: "この操作を実行しますか？",
///             payload: InteractionPayload(ConfirmationPayload(
///                 proposal: proposal, allowModification: true
///             ))
///         )
///     }
///
///     func makeToolResult(from response: InteractionResponse) -> ToolResult {
///         if let confirmation = response.content.value(as: ConfirmationResponse.self) {
///             switch confirmation.decision {
///             case .approved: return .text("User approved the action")
///             case .rejected: return .text("User rejected the action")
///             case .modified(let text): return .text("User modified: \(text)")
///             }
///         }
///         return .text(response.content.textValue)
///     }
/// }
/// ```
public protocol InteractiveTool: Tool {
    /// ツール引数から InteractionRequest を生成
    ///
    /// - Parameter arguments: LLM から渡されたツール引数（JSON データ）
    /// - Returns: UI に表示する InteractionRequest
    func makeInteractionRequest(from arguments: Data) throws -> InteractionRequest

    /// InteractionResponse から ToolResult を生成
    ///
    /// - Parameter response: UI から返された InteractionResponse
    /// - Returns: ランループに返す ToolResult
    func makeToolResult(from response: InteractionResponse) -> ToolResult
}
