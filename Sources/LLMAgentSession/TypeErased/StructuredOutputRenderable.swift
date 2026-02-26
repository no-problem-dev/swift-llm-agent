/// 構造化出力型を `StructuredResult` に変換するプロトコル
///
/// `StructuredProtocol` 型が自身の内容を人間可読な
/// `StructuredResult` に変換する方法を定義します。
///
/// `LLMToolkits` の組み込み出力型（`AnalysisResult`、`CodeReview` 等）は
/// デフォルトで準拠しています。独自の出力型を定義する場合は
/// このプロトコルに準拠させることで `ChatSession` の convenience init が利用可能になります。
public protocol StructuredOutputRenderable {
    func toStructuredResult() -> StructuredResult
}
