import Foundation
import LLMClient
import Observation

// MARK: - StepUsage

/// 単一 LLM 呼び出し（エージェント 1 ステップ）の使用量とコスト。
public struct StepUsage: Sendable, Identifiable, Hashable {
    public let id: UUID
    public let index: Int
    public let modelId: String
    public let usage: TokenUsage
    public let cost: Money<USD>?     // nil = 料金未登録モデル
    public let timestamp: Date

    public init(
        id: UUID = UUID(),
        index: Int,
        modelId: String,
        usage: TokenUsage,
        cost: Money<USD>?,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.index = index
        self.modelId = modelId
        self.usage = usage
        self.cost = cost
        self.timestamp = timestamp
    }
}

// MARK: - TurnUsage

/// エージェントのユーザー入力 1 回 = 1 ターン分の集計。
public struct TurnUsage: Sendable, Identifiable, Hashable {
    public let id: UUID
    public let index: Int
    public let label: String?
    public var steps: [StepUsage]

    public init(
        id: UUID = UUID(),
        index: Int,
        label: String? = nil,
        steps: [StepUsage] = []
    ) {
        self.id = id
        self.index = index
        self.label = label
        self.steps = steps
    }

    public var aggregatedUsage: TokenUsage {
        steps.reduce(.zero) { $0.adding($1.usage) }
    }

    public var totalCost: Money<USD> {
        steps.compactMap(\.cost).reduce(.zero, +)
    }
}

// MARK: - SessionUsage

/// 複数ターン全体（= セッション）の集計スナップショット。
public struct SessionUsage: Sendable, Hashable {
    public let turnCount: Int
    public let stepCount: Int
    public let usage: TokenUsage
    public let cost: Money<USD>

    public static let zero = SessionUsage(turnCount: 0, stepCount: 0, usage: .zero, cost: .zero)

    public static func aggregate(_ turns: [TurnUsage]) -> SessionUsage {
        let allSteps = turns.flatMap(\.steps)
        return SessionUsage(
            turnCount: turns.count,
            stepCount: allSteps.count,
            usage: allSteps.map(\.usage).reduce(.zero) { $0.adding($1) },
            cost: allSteps.compactMap(\.cost).reduce(.zero, +)
        )
    }
}

// MARK: - UsageLedger

/// エージェントの会話セッションを通じた使用量・コストを集計する Observable。
///
/// SwiftUI の `@Observable` から観察可能。
/// アプリ側はこの ledger を表示するだけで、料金計算ロジックは持たない。
@MainActor
@Observable
public final class UsageLedger {
    public private(set) var turns: [TurnUsage] = []

    public init() {}

    /// 新しいターン（ユーザー入力 1 回分）を開始する。
    public func startTurn(label: String? = nil) {
        turns.append(TurnUsage(index: turns.count + 1, label: label))
    }

    /// ターン内のステップ（LLM 呼び出し 1 回）を記録する。
    ///
    /// - Parameters:
    ///   - modelId: 使用したモデル ID
    ///   - pricing: 料金プロファイル（nil なら cost は記録されない）
    ///   - usage: 正規化済み `TokenUsage`
    public func recordStep(modelId: String, pricing: Pricing?, usage: TokenUsage) {
        precondition(!turns.isEmpty, "recordStep called before startTurn")
        let cost = pricing.map { CostCalculator.cost(of: usage, with: $0) }
        let step = StepUsage(
            index: turns[turns.count - 1].steps.count + 1,
            modelId: modelId,
            usage: usage,
            cost: cost
        )
        turns[turns.count - 1].steps.append(step)
    }

    public func clear() {
        turns.removeAll()
    }

    /// 現在のセッション全体のスナップショット。
    public var sessionTotals: SessionUsage { .aggregate(turns) }
}
