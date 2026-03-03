import Foundation
import LLMAgent

// MARK: - ScopedSubAgent

/// スコープ情報付きのサブエージェントタイプ
public struct ScopedSubAgent: Sendable {
    /// エージェントタイプ定義
    public let agentType: any SubAgentType
    /// スコープ
    public let scope: ItemScope

    public init(agentType: any SubAgentType, scope: ItemScope) {
        self.agentType = agentType
        self.scope = scope
    }
}

// MARK: - ScopedSubAgentCatalog

/// 3層スコープマージ対応のサブエージェントカタログ
///
/// `project` > `global` > `builtIn` の優先度で同名エージェントタイプを解決します。
/// `SubAgentCatalog` プロトコルに準拠し、`DelegateTaskTool` にそのまま渡せます。
///
/// ## 使用例
///
/// ```swift
/// let catalog = ScopedSubAgentCatalog(
///     builtIn: [ResearcherAgentType(), DeviceAgentType()],
///     global: globalCustomAgents,
///     project: projectCustomAgents
/// )
/// ```
public struct ScopedSubAgentCatalog: SubAgentCatalog {

    /// スコープ付きの全エージェントタイプ（マージ・重複除去済み）
    public let scopedAgentTypes: [ScopedSubAgent]

    /// `SubAgentCatalog` 準拠: マージ済みエージェントタイプ一覧
    public var agentTypes: [any SubAgentType] {
        scopedAgentTypes.map(\.agentType)
    }

    /// 3層スコープからマージ
    ///
    /// - Parameters:
    ///   - builtIn: ビルトインエージェントタイプ（最低優先度）
    ///   - global: グローバルカスタムエージェントタイプ
    ///   - project: プロジェクトカスタムエージェントタイプ（最高優先度）
    public init(
        builtIn: [any SubAgentType] = [],
        global: [any SubAgentType] = [],
        project: [any SubAgentType] = []
    ) {
        var seen = Set<String>()
        var result: [ScopedSubAgent] = []

        // 高優先度から追加（同名は先勝ち）
        for agentType in project {
            if seen.insert(agentType.name).inserted {
                result.append(ScopedSubAgent(agentType: agentType, scope: .project))
            }
        }
        for agentType in global {
            if seen.insert(agentType.name).inserted {
                result.append(ScopedSubAgent(agentType: agentType, scope: .global))
            }
        }
        for agentType in builtIn {
            if seen.insert(agentType.name).inserted {
                result.append(ScopedSubAgent(agentType: agentType, scope: .builtIn))
            }
        }

        self.scopedAgentTypes = result
    }
}
