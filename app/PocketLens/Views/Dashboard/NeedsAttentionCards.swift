import SwiftUI

/// Two click-through cards: uncategorized count and needs-review count.
/// Each tap fires the navigation closure provided by the parent — typically
/// switches the sidebar to the Review screen with the matching filter.
struct NeedsAttentionCards: View {

    let uncategorizedCount: Int
    let needsReviewCount: Int
    var onTapUncategorized: () -> Void
    var onTapNeedsReview: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            attentionTile(
                title: "Uncategorized",
                count: uncategorizedCount,
                systemImage: "questionmark.diamond",
                tint: .orange,
                action: onTapUncategorized
            )
            attentionTile(
                title: "Needs review",
                count: needsReviewCount,
                systemImage: "exclamationmark.triangle",
                tint: .yellow,
                action: onTapNeedsReview
            )
        }
    }

    private func attentionTile(
        title: String,
        count: Int,
        systemImage: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: 14) {
                Image(systemName: systemImage)
                    .font(.title2)
                    .foregroundStyle(tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(count)")
                        .font(.title.weight(.semibold).monospacedDigit())
                    Text(title)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if count > 0 {
                    Image(systemName: "chevron.right")
                        .foregroundStyle(.secondary)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.secondary.opacity(0.15))
            )
        }
        .buttonStyle(.plain)
        .disabled(count == 0)
    }
}
