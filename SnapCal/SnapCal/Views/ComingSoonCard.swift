import SwiftUI

// Placeholder card used by tabs that aren't fully built yet (Cook, and
// the Insights weight-trend card). Icon on the left, title + SOON pill,
// one-line copy. Matches the existing scCardStyle look.
struct ComingSoonCard: View {
    let icon: String
    let title: String
    let copy: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .heavy))
                .foregroundStyle(SCTheme.Colors.accentOrange)
                .frame(width: 40, height: 40)
                .background(
                    SCTheme.Colors.accentOrange.opacity(0.12),
                    in: RoundedRectangle(cornerRadius: 10)
                )
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(title)
                        .font(.system(size: 16, weight: .heavy, design: .rounded))
                        .foregroundStyle(.primary)
                    Text("SOON")
                        .font(.system(size: 9, weight: .heavy, design: .rounded))
                        .tracking(1.0)
                        .foregroundStyle(SCTheme.Colors.accentPink)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(SCTheme.Colors.accentPink.opacity(0.12), in: Capsule())
                }
                Text(copy)
                    .font(SCTheme.Type_.caption())
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .scCardStyle()
    }
}
