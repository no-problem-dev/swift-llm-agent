import LLMAgentSession

// MARK: - AnalysisResult

extension AnalysisResult: StructuredOutputRenderable {
    public func toStructuredResult() -> StructuredResult {
        var md = "## 要約\n\n\(summary)\n\n"

        if !keyFindings.isEmpty {
            md += "## 主な発見事項\n\n"
            md += keyFindings.map { "- \($0)" }.joined(separator: "\n")
            md += "\n\n"
        }

        if !recommendations.isEmpty {
            md += "## 推奨事項\n\n"
            md += recommendations.map { "- \($0)" }.joined(separator: "\n")
            md += "\n\n"
        }

        if let risks, !risks.isEmpty {
            md += "## リスク\n\n"
            md += risks.map { "- \($0)" }.joined(separator: "\n")
            md += "\n\n"
        }

        md += "**信頼度:** \(Int(confidence * 100))%"

        var sections: [StructuredResult.Section] = []
        if !keyFindings.isEmpty {
            sections.append(.init(title: "主な発見事項", items: keyFindings))
        }
        if !recommendations.isEmpty {
            sections.append(.init(title: "推奨事項", items: recommendations))
        }
        if let risks, !risks.isEmpty {
            sections.append(.init(title: "リスク", items: risks))
        }

        return StructuredResult(
            typeName: "AnalysisResult",
            markdown: md,
            sections: sections,
            metadata: ["confidence": "\(Int(confidence * 100))%"]
        )
    }
}

// MARK: - CodeReview

extension CodeReview: StructuredOutputRenderable {
    public func toStructuredResult() -> StructuredResult {
        var md = "## 総合評価\n\n\(overallAssessment)\n\n"

        if let issues, !issues.isEmpty {
            md += "## 問題点\n\n"
            md += issues.map { "- [\($0.severity)] \($0.description)" }.joined(separator: "\n")
            md += "\n\n"
        }

        if let suggestions, !suggestions.isEmpty {
            md += "## 改善提案\n\n"
            md += suggestions.map { "- \($0)" }.joined(separator: "\n")
            md += "\n\n"
        }

        if let strengths, !strengths.isEmpty {
            md += "## 強み\n\n"
            md += strengths.map { "- \($0)" }.joined(separator: "\n")
            md += "\n\n"
        }

        md += "**品質スコア:** \(qualityScore)/10"

        var sections: [StructuredResult.Section] = []
        if let issues, !issues.isEmpty {
            sections.append(.init(title: "問題点", items: issues.map { "[\($0.severity)] \($0.description)" }))
        }
        if let suggestions, !suggestions.isEmpty {
            sections.append(.init(title: "改善提案", items: suggestions))
        }
        if let strengths, !strengths.isEmpty {
            sections.append(.init(title: "強み", items: strengths))
        }

        return StructuredResult(
            typeName: "CodeReview",
            markdown: md,
            sections: sections,
            metadata: ["qualityScore": "\(qualityScore)/10"]
        )
    }
}

// MARK: - TaskPlan

extension TaskPlan: StructuredOutputRenderable {
    public func toStructuredResult() -> StructuredResult {
        var md = "## 目標\n\n\(objective)\n\n"

        if !steps.isEmpty {
            md += "## ステップ\n\n"
            md += steps.map { "\($0.stepNumber). \($0.description)" }.joined(separator: "\n")
            md += "\n\n"
        }

        if let prerequisites, !prerequisites.isEmpty {
            md += "## 前提条件\n\n"
            md += prerequisites.map { "- \($0)" }.joined(separator: "\n")
            md += "\n\n"
        }

        if let risks, !risks.isEmpty {
            md += "## リスク\n\n"
            md += risks.map { "- \($0)" }.joined(separator: "\n")
            md += "\n\n"
        }

        if !successCriteria.isEmpty {
            md += "## 成功基準\n\n"
            md += successCriteria.map { "- \($0)" }.joined(separator: "\n")
        }

        var sections: [StructuredResult.Section] = []
        if !steps.isEmpty {
            sections.append(.init(title: "ステップ", items: steps.map { "\($0.stepNumber). \($0.description)" }))
        }
        if let prerequisites, !prerequisites.isEmpty {
            sections.append(.init(title: "前提条件", items: prerequisites))
        }
        if let risks, !risks.isEmpty {
            sections.append(.init(title: "リスク", items: risks))
        }
        if !successCriteria.isEmpty {
            sections.append(.init(title: "成功基準", items: successCriteria))
        }

        return StructuredResult(
            typeName: "TaskPlan",
            markdown: md,
            sections: sections
        )
    }
}

// MARK: - Summary

extension Summary: StructuredOutputRenderable {
    public func toStructuredResult() -> StructuredResult {
        var md = "## 要約\n\n\(briefSummary)\n\n"

        if !mainPoints.isEmpty {
            md += "## 主なポイント\n\n"
            md += mainPoints.map { "- \($0)" }.joined(separator: "\n")
            md += "\n\n"
        }

        if let keyTakeaways, !keyTakeaways.isEmpty {
            md += "## キーテイクアウェイ\n\n"
            md += keyTakeaways.map { "- \($0)" }.joined(separator: "\n")
            md += "\n\n"
        }

        if let targetAudience {
            md += "**対象読者:** \(targetAudience)"
        }

        var sections: [StructuredResult.Section] = []
        if !mainPoints.isEmpty {
            sections.append(.init(title: "主なポイント", items: mainPoints))
        }
        if let keyTakeaways, !keyTakeaways.isEmpty {
            sections.append(.init(title: "キーテイクアウェイ", items: keyTakeaways))
        }

        var metadata: [String: String] = [:]
        if let targetAudience {
            metadata["targetAudience"] = targetAudience
        }

        return StructuredResult(
            typeName: "Summary",
            markdown: md,
            sections: sections,
            metadata: metadata
        )
    }
}
