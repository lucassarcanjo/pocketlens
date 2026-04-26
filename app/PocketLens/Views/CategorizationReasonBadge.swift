import SwiftUI
import Domain

/// Small inline badge that surfaces the categorization-reason explanation
/// alongside each transaction row. Color-codes by reason so the user can
/// scan at a glance which categories came from corrections vs rules vs the
/// LLM extraction's bank label.
struct CategorizationReasonBadge: View {
    let reasonKey: CategorizationReason
    let explanation: String
    let confidence: Double

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2)
            Text(explanation)
                .font(.caption2)
                .lineLimit(1)
            if confidence > 0 {
                Text(confidenceLabel)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(tint.opacity(0.15), in: Capsule())
        .foregroundStyle(tint)
    }

    private var icon: String {
        switch reasonKey {
        case .userCorrection:       return "person.fill.checkmark"
        case .merchantAlias:        return "link"
        case .userRule:             return "person.crop.circle.badge"
        case .bankCategoryMapping:  return "building.columns"
        case .keywordRule:          return "text.magnifyingglass"
        case .similarity:           return "rectangle.on.rectangle"
        case .llmSuggestion:        return "sparkles"
        case .uncategorized:        return "questionmark.circle"
        }
    }

    private var tint: Color {
        switch reasonKey {
        case .userCorrection:       return .green
        case .merchantAlias:        return .teal
        case .userRule:             return .blue
        case .bankCategoryMapping:  return .purple
        case .keywordRule:          return .indigo
        case .similarity:           return .orange
        case .llmSuggestion:        return .pink
        case .uncategorized:        return .secondary
        }
    }

    private var confidenceLabel: String {
        let pct = Int((confidence * 100).rounded())
        return "\(pct)%"
    }
}

extension CategorizationReasonBadge {
    /// Best-effort recovery of the structured `CategorizationReason` from the
    /// stored explanation prefix. Cheap heuristic — the reason key isn't
    /// persisted directly, so we infer from the explanation phrase the
    /// engine uses.
    static func reason(forExplanation explanation: String, confidence: Double) -> CategorizationReason {
        if confidence == 0 { return .uncategorized }
        if explanation.hasPrefix("Prior user correction") { return .userCorrection }
        if explanation.hasPrefix("Matched merchant alias") { return .merchantAlias }
        if explanation.hasPrefix("User rule") { return .userRule }
        if explanation.hasPrefix("Bank category") { return .bankCategoryMapping }
        if explanation.hasPrefix("Keyword rule") { return .keywordRule }
        if explanation.hasPrefix("Similar to") { return .similarity }
        return .uncategorized
    }
}
