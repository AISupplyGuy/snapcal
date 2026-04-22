import SwiftUI

// Cook — recipe surface. Future fills: generate recipes from Pantry +
// remaining macro budget + calibration history; step-by-step cooking
// view; completing a recipe auto-logs to Track. This is the "what
// should I eat" answer.
struct CookView: View {
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 10) {
                        SCKickerPill(text: "Cook", tint: SCTheme.Colors.accentPink)
                        Text("What to eat")
                            .font(SCTheme.Type_.title(30))
                            .foregroundStyle(.primary)
                        Text("Recipes built from what's in your Pantry and what you still have left in today's macro budget. Finishing a recipe logs the meal automatically.")
                            .font(SCTheme.Type_.body())
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    ComingSoonCard(
                        icon: "sparkles",
                        title: "Fits-your-day recipes",
                        copy: "We score each recipe against what's left on your rings so the suggestions aren't random."
                    )
                    ComingSoonCard(
                        icon: "list.clipboard.fill",
                        title: "Step-by-step mode",
                        copy: "Timed prompts with hands-free voice + a tally of macros as you go."
                    )
                    ComingSoonCard(
                        icon: "checkmark.circle.fill",
                        title: "Auto-log on finish",
                        copy: "Tap Done at the end of the recipe, it lands on Track with the right portion already baked in."
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

#Preview {
    CookView()
}
