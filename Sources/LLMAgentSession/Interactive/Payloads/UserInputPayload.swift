import Foundation

// MARK: - UserInputPayload

/// 統合ユーザー入力リクエストのペイロード
///
/// `RequestUserInputTool` が生成するペイロード。
/// UI 層は `typeHint` と `options` を基に最適な入力 UI を選択する。
///
/// ## typeHint 一覧
///
/// | ヒント | UI |
/// |--------|-----|
/// | `"text"` / `nil` | テキスト入力（デフォルト） |
/// | `"selection"` | 選択リスト（`options` 必須） |
/// | `"confirmation"` | 承認/却下ボタン |
/// | `"date"` | 日付ピッカー |
/// | `"photo"` | フォトピッカー |
/// | `"location"` | 位置選択 |
///
/// UI 層が未対応の `typeHint` を受け取った場合はテキスト入力にフォールバック。
public struct UserInputPayload: InteractionPayloadProtocol {
    /// ユーザーに求める情報の説明
    public let description: String

    /// UI ヒント（`"text"`, `"selection"`, `"confirmation"`, `"date"`, `"photo"` 等）
    ///
    /// `nil` の場合はテキスト入力にフォールバック。
    public let typeHint: String?

    /// 選択肢（`typeHint == "selection"` の場合に使用）
    public let options: [String]?

    public init(
        description: String,
        typeHint: String? = nil,
        options: [String]? = nil
    ) {
        self.description = description
        self.typeHint = typeHint
        self.options = options
    }
}
