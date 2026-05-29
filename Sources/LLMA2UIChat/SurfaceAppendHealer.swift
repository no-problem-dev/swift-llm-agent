import A2UICore

/// `LLMA2UIChat` の append-only ポリシーを実現するメッセージ書き換え器。
///
/// 入力された `[ServerMessage]` バッチを 1 ターン分とみなし、以下を適用する:
///
/// 1. `createSurface`: 既存 / 同ターン内 と衝突する id は fresh id にリネーム。
///    `sendDataModel` は LLM 出力をそのまま透過（spec 準拠。ChoicePicker 等の入力値を
///    次ターンの LLM に届けるために必要）。
/// 2. `updateComponents`:
///    - 同ターン内で `createSurface` 済みの id を対象 → そのまま通す
///    - 過去ターンで作られた id（= `lockedIds`）を対象 → `createSurface` を**直前に挿入**して
///      新 id へ rename（**暗黙 fork**）
///    - どれにも該当しない id → drop（LLM の hallucination）
/// 3. `updateDataModel`:
///    - 同ターン内 surface 対象 → 通す
///    - その他 → drop
/// 4. `deleteSurface`: **常に drop**。チャット履歴的に過去メッセージは消えない
///
/// `defaultCatalogId` は 2 の暗黙 fork で生成する `createSurface` の `catalogId` に使う。
internal enum SurfaceAppendHealer {

    static func heal(
        _ messages: [ServerMessage],
        lockedIds: Set<String>,
        defaultCatalogId: String
    ) -> [ServerMessage] {
        var renames: [String: String] = [:]
        var createdThisTurn: Set<String> = []
        var taken = lockedIds
        var out: [ServerMessage] = []
        out.reserveCapacity(messages.count)

        for message in messages {
            switch message {
            case .createSurface(let cs):
                let original = cs.surfaceId
                let resolved = renames[original]
                    ?? (taken.contains(original) ? freshId(original, taken: taken) : original)
                if resolved != original {
                    renames[original] = resolved
                }
                taken.insert(resolved)
                createdThisTurn.insert(resolved)
                out.append(.createSurface(CreateSurface(
                    surfaceId: resolved,
                    catalogId: cs.catalogId,
                    theme: cs.theme,
                    sendDataModel: cs.sendDataModel   // LLM 出力をそのまま透過 (spec 準拠)
                )))

            case .updateComponents(let uc):
                let target = renames[uc.surfaceId] ?? uc.surfaceId
                if createdThisTurn.contains(target) {
                    // 同ターン surface → 透過
                    if target != uc.surfaceId {
                        out.append(.updateComponents(UpdateComponents(
                            surfaceId: target, components: uc.components
                        )))
                    } else {
                        out.append(.updateComponents(uc))
                    }
                } else if lockedIds.contains(target) {
                    // 過去 surface → 暗黙 fork
                    let forkId = freshId(target, taken: taken)
                    renames[uc.surfaceId] = forkId
                    taken.insert(forkId)
                    createdThisTurn.insert(forkId)
                    out.append(.createSurface(CreateSurface(
                        surfaceId: forkId,
                        catalogId: defaultCatalogId,
                        theme: nil,
                        sendDataModel: nil   // 暗黙 fork 時は spec default に従う
                    )))
                    out.append(.updateComponents(UpdateComponents(
                        surfaceId: forkId, components: uc.components
                    )))
                } else {
                    // hallucination → drop
                    continue
                }

            case .updateDataModel(let udm):
                let target = renames[udm.surfaceId] ?? udm.surfaceId
                guard createdThisTurn.contains(target) else {
                    // 過去 surface への dataModel 変更 / 未知 id → drop
                    continue
                }
                if target != udm.surfaceId {
                    out.append(.updateDataModel(UpdateDataModel(
                        surfaceId: target, path: udm.path, value: udm.value
                    )))
                } else {
                    out.append(.updateDataModel(udm))
                }

            case .deleteSurface:
                // append-only では削除しない
                continue
            }
        }

        return out
    }

    private static func freshId(_ original: String, taken: Set<String>) -> String {
        var counter = 2
        while taken.contains("\(original)-\(counter)") {
            counter += 1
        }
        return "\(original)-\(counter)"
    }
}
