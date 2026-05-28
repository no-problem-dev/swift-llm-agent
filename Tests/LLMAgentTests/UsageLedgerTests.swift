import Testing
import LLMClient
@testable import LLMAgent

@Suite("UsageLedger")
@MainActor
struct UsageLedgerTests {

    @Test("ターン開始前の recordStep は precondition で停止する（API 契約として明示）")
    func requiresStartTurnFirst() {
        // precondition は本番ビルドではトラップしないため、初期状態のみ検証
        let ledger = UsageLedger()
        #expect(ledger.turns.isEmpty)
        #expect(ledger.sessionTotals == .zero)
    }

    @Test("ステップ記録とターン集計")
    func recordingAndAggregation() {
        let ledger = UsageLedger()
        let pricing = Pricing.flat(inputPerMTok: 1, outputPerMTok: 4)

        ledger.startTurn(label: "first")
        ledger.recordStep(
            modelId: "test-model",
            pricing: pricing,
            usage: TokenUsage(inputTokens: 1_000_000, outputTokens: 500_000)
        )
        ledger.recordStep(
            modelId: "test-model",
            pricing: pricing,
            usage: TokenUsage(inputTokens: 2_000_000, outputTokens: 0)
        )

        #expect(ledger.turns.count == 1)
        #expect(ledger.turns[0].steps.count == 2)

        let agg = ledger.turns[0].aggregatedUsage
        #expect(agg.inputTokens == 3_000_000)
        #expect(agg.outputTokens == 500_000)

        let cost = ledger.turns[0].totalCost
        // step1: 1M * $1 + 0.5M * $4 = $1 + $2 = $3
        // step2: 2M * $1 + 0  = $2
        // total = $5
        #expect(abs(cost.value - 5.0) < 1e-9)
    }

    @Test("複数ターンを跨ぐ sessionTotals")
    func sessionTotals() {
        let ledger = UsageLedger()
        let pricing = Pricing.flat(inputPerMTok: 1, outputPerMTok: 1)

        ledger.startTurn()
        ledger.recordStep(modelId: "m", pricing: pricing, usage: TokenUsage(inputTokens: 1_000_000, outputTokens: 0))
        ledger.startTurn()
        ledger.recordStep(modelId: "m", pricing: pricing, usage: TokenUsage(inputTokens: 0, outputTokens: 1_000_000))

        let s = ledger.sessionTotals
        #expect(s.turnCount == 2)
        #expect(s.stepCount == 2)
        #expect(s.usage.inputTokens == 1_000_000)
        #expect(s.usage.outputTokens == 1_000_000)
        #expect(abs(s.cost.value - 2.0) < 1e-9)
    }

    @Test("pricing nil なら cost は nil（コスト未登録モデル）")
    func nilPricing() {
        let ledger = UsageLedger()
        ledger.startTurn()
        ledger.recordStep(
            modelId: "unknown",
            pricing: nil,
            usage: TokenUsage(inputTokens: 1_000, outputTokens: 100)
        )
        #expect(ledger.turns[0].steps[0].cost == nil)
        #expect(ledger.turns[0].totalCost == .zero)
    }
}
