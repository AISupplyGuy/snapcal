import SwiftUI

// Pantry — what you have on hand. Future fills: barcode scan, receipt
// scan, manual add, expiration tracking. Feeds the Cook tab's recipe
// generator. Closed-loop input: pantry → cook → track → calibration.
struct PantryView: View {
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 10) {
                        SCKickerPill(text: "Pantry", tint: SCTheme.Colors.carbGreen)
                        Text("What's on hand")
                            .font(SCTheme.Type_.title(30))
                            .foregroundStyle(.primary)
                        Text("Scan a barcode or a receipt and we'll keep a running inventory. Cook uses it to suggest recipes that fit the day's macros.")
                            .font(SCTheme.Type_.body())
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    ComingSoonCard(
                        icon: "barcode.viewfinder",
                        title: "Barcode scanning",
                        copy: "Point at a package, the Open Food Facts lookup drops it in with macros already set."
                    )
                    ComingSoonCard(
                        icon: "doc.text.viewfinder",
                        title: "Receipt capture",
                        copy: "Snap a grocery receipt and we'll queue everything into Pantry in one pass."
                    )
                    ComingSoonCard(
                        icon: "calendar.badge.clock",
                        title: "Expiration nudges",
                        copy: "Soft reminders before ingredients go off, so the recipes we suggest use what's running out first."
                    )
                }
                .padding(.horizontal, 22)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
            .navigationTitle("")
        }
    }
}

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
                .background(SCTheme.Colors.accentOrange.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
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

#Preview {
    PantryView()
}
