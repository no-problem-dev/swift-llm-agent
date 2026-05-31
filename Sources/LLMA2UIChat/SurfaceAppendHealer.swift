import A2UICore

/// `LLMA2UIChat` の append-only ポリシーを実現するメッセージ書き換え器。
///
/// 入力された `[ServerMessage]` バッチを 1 ターン分とみなし、以下を適用する:
///
/// 1. `createSurface`: 既存 / 同ターン内 と衝突する id は fresh id にリネーム。
///    `sendDataModel` は LLM 出力をそのまま透過（spec 準拠）するが、**ターン内に同 surface
///    の入力 components (TextField / CheckBox / Slider / ChoicePicker / DateTimeInput) が
///    含まれていて、かつ LLM が `sendDataModel` を未指定 (nil) の場合は true に default 化** する。
///    LLM が明示的に false にしているケースは尊重する。
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

    /// A2UI v0.9 basic catalog の入力 components 名。
    /// これらが含まれる surface は ユーザー入力を agent に届ける必要があるため、
    /// `sendDataModel` を true に default 化する。
    private static let inputComponentNames: Set<String> = [
        "TextField",
        "CheckBox",
        "Slider",
        "ChoicePicker",
        "DateTimeInput",
    ]

    static func heal(
        _ messages: [ServerMessage],
        lockedIds: Set<String>,
        defaultCatalogId: String
    ) -> [ServerMessage] {
        // Pass 1: 入力 components を含む original surfaceId を集める
        let surfacesWithInputs = collectSurfacesWithInputs(messages)

        // Pass 2: メッセージを書き換える
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

                // sendDataModel が未指定の場合のみ、入力 components 有無に応じて true に default 化。
                // 明示的な true / false はそのまま尊重する。
                let resolvedSendDataModel: Bool? = {
                    if cs.sendDataModel != nil { return cs.sendDataModel }
                    return surfacesWithInputs.contains(original) ? true : nil
                }()

                out.append(.createSurface(CreateSurface(
                    surfaceId: resolved,
                    catalogId: cs.catalogId,
                    theme: cs.theme,
                    sendDataModel: resolvedSendDataModel
                )))

            case .updateComponents(let uc):
                let target = renames[uc.surfaceId] ?? uc.surfaceId
                if createdThisTurn.contains(target) {
                    // 同ターン surface → 透過 (literal value の自動 path 化を適用)
                    let repaired = repairLiteralInputValues(uc.components)
                    out.append(.updateComponents(UpdateComponents(
                        surfaceId: target, components: repaired.components
                    )))
                    for udm in repaired.dataModelSeeds {
                        out.append(.updateDataModel(UpdateDataModel(
                            surfaceId: target, path: udm.path, value: udm.value
                        )))
                    }
                } else if lockedIds.contains(target) {
                    // 過去 surface → 暗黙 fork
                    let forkId = freshId(target, taken: taken)
                    renames[uc.surfaceId] = forkId
                    taken.insert(forkId)
                    createdThisTurn.insert(forkId)
                    // fork で生成する createSurface も、original 側に入力があれば true 化
                    let forkSendDataModel: Bool? =
                        surfacesWithInputs.contains(uc.surfaceId) ? true : nil
                    out.append(.createSurface(CreateSurface(
                        surfaceId: forkId,
                        catalogId: defaultCatalogId,
                        theme: nil,
                        sendDataModel: forkSendDataModel
                    )))
                    let repaired = repairLiteralInputValues(uc.components)
                    out.append(.updateComponents(UpdateComponents(
                        surfaceId: forkId, components: repaired.components
                    )))
                    for udm in repaired.dataModelSeeds {
                        out.append(.updateDataModel(UpdateDataModel(
                            surfaceId: forkId, path: udm.path, value: udm.value
                        )))
                    }
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

    // MARK: - Internal

    /// `repairLiteralInputValues` の結果。修復後の components と、初期値を書き戻すための
    /// `updateDataModel` 種を返す。
    fileprivate struct RepairResult {
        let components: [StructuredValue]
        let dataModelSeeds: [(path: String, value: StructuredValue)]
    }

    /// `updateComponents.components` 内の入力 components の `value` が literal (path binding でない)
    /// 場合に、自動で `{path: ...}` に書き換え、同時にデータモデルへの初期値書き込みを生成する。
    ///
    /// LLM が `value: ["a","b"]` のようなリテラルで出してきたケースを spec 通りの path binding に
    /// 矯正する。これによりユーザーの入力変更が dataModel に流れ、`sendDataModel: true` 経由で
    /// agent にも届くようになる。
    ///
    /// すでに `{path: ...}` で書かれているものは LLM の意思を尊重して触らない。
    fileprivate static func repairLiteralInputValues(_ components: [StructuredValue]) -> RepairResult {
        var seeds: [(path: String, value: StructuredValue)] = []
        let repaired = components.map { component -> StructuredValue in
            guard case .object(var dict) = component,
                  case .string(let componentName)? = dict["component"],
                  inputComponentNames.contains(componentName) else {
                return component
            }
            // value が未指定 or 既に binding なら触らない
            guard let value = dict["value"], !isPathBinding(value) else {
                return component
            }
            // componentId を取得 (なければスキップ)
            guard case .string(let componentId)? = dict["id"] else {
                return component
            }
            // 自動 path 化
            let path = "/__autoinput__/\(componentId)"
            dict["value"] = .object(["path": .string(path)])
            seeds.append((path: path, value: value))
            return .object(dict)
        }
        return RepairResult(components: repaired, dataModelSeeds: seeds)
    }

    /// 値が `{"path": "..."}` 形式の path binding かどうか。
    private static func isPathBinding(_ value: StructuredValue) -> Bool {
        guard case .object(let dict) = value, dict.count == 1 else { return false }
        guard case .string? = dict["path"] else { return false }
        return true
    }

    /// ターン内の全 updateComponents をスキャンして、入力 components を 1 つでも含む
    /// **元の** surfaceId のセットを返す（renames 適用前 = LLM 出力上の id）。
    private static func collectSurfacesWithInputs(_ messages: [ServerMessage]) -> Set<String> {
        var result: Set<String> = []
        for message in messages {
            guard case .updateComponents(let uc) = message else { continue }
            for component in uc.components {
                if componentContainsInput(component) {
                    result.insert(uc.surfaceId)
                    break
                }
            }
        }
        return result
    }

    /// 1 つの component 値が入力 component を表すか判定する。
    /// component の表現は `{"component": "ChoicePicker", ...}` の object 形式が basic catalog では標準。
    private static func componentContainsInput(_ value: StructuredValue) -> Bool {
        guard case .object(let dict) = value else { return false }
        if case .string(let name)? = dict["component"], inputComponentNames.contains(name) {
            return true
        }
        return false
    }

    private static func freshId(_ original: String, taken: Set<String>) -> String {
        var counter = 2
        while taken.contains("\(original)-\(counter)") {
            counter += 1
        }
        return "\(original)-\(counter)"
    }
}
