import SwiftUI

// Design tokens ported from the waitlist site (projects/snapcal/waitlist/index.html).
// Keep this the single source of truth — all views should reference SCTheme, never literals.
enum SCTheme {

    // MARK: Colors

    enum Colors {
        // Brand
        static let accentPink   = Color(hex: 0xFF375F)
        static let accentOrange = Color(hex: 0xFF6B35)
        static let proteinBlue  = Color(hex: 0x007AFF)
        static let carbGreen    = Color(hex: 0x34C759)
        static let standTeal    = Color(hex: 0x00C7BE)

        // Soft/tinted backgrounds (for chips, badges)
        static let caloriesSoft = Color(hex: 0xFFF0E8)
        static let proteinSoft  = Color(hex: 0xE1EFFF)
        static let carbSoft     = Color(hex: 0xDCFCE1)
    }

    // MARK: Gradients

    enum Gradients {
        static let cta = LinearGradient(
            colors: [Colors.accentPink, Colors.accentOrange],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        static let heroText = LinearGradient(
            colors: [Colors.accentOrange, Colors.accentPink],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    // MARK: Typography

    enum Type_ {
        static func hero(_ size: CGFloat = 44) -> Font { .system(size: size, weight: .heavy, design: .rounded) }
        static func title(_ size: CGFloat = 28) -> Font { .system(size: size, weight: .heavy, design: .rounded) }
        static func cardTitle() -> Font { .system(size: 22, weight: .heavy, design: .rounded) }
        static func body() -> Font { .system(size: 17, weight: .regular, design: .default) }
        static func button() -> Font { .system(size: 16, weight: .semibold, design: .rounded) }
        static func caption() -> Font { .system(size: 13, weight: .medium, design: .default) }
        static func kicker() -> Font { .system(size: 12, weight: .heavy, design: .rounded) }
    }

    // MARK: Radii

    enum Radius {
        static let sm: CGFloat = 14
        static let md: CGFloat = 20
        static let lg: CGFloat = 28
        static let pill: CGFloat = 999
    }

    // MARK: Shadow helpers

    enum Shadow {
        static func card(for scheme: ColorScheme) -> Color {
            scheme == .dark ? Color.black.opacity(0.35) : Color.black.opacity(0.05)
        }
        static func ctaGlow() -> Color {
            Color(hex: 0xFF375F).opacity(0.28)
        }
    }
}

// MARK: - View helpers

extension View {
    // Primary CTA button styling — accent gradient + glow
    func scCTAStyle() -> some View {
        self
            .font(SCTheme.Type_.button())
            .foregroundStyle(.white)
            .padding(.vertical, 18)
            .frame(maxWidth: .infinity)
            .background(SCTheme.Gradients.cta, in: RoundedRectangle(cornerRadius: SCTheme.Radius.pill))
            .shadow(color: SCTheme.Shadow.ctaGlow(), radius: 14, x: 0, y: 8)
    }

    // Card surface (rounded, subtle elevation, respects color scheme)
    func scCardStyle() -> some View {
        self
            .background {
                RoundedRectangle(cornerRadius: SCTheme.Radius.md)
                    .fill(Color(.secondarySystemBackground))
                    .shadow(color: .black.opacity(0.04), radius: 2, x: 0, y: 1)
                    .shadow(color: .black.opacity(0.05), radius: 32, x: 0, y: 10)
            }
            .overlay {
                RoundedRectangle(cornerRadius: SCTheme.Radius.md)
                    .strokeBorder(.primary.opacity(0.05))
            }
    }
}

// Small kicker pill with pulsing dot, used at the top of screens.
struct SCKickerPill: View {
    let text: String
    let tint: Color
    @State private var pulse = false

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(tint)
                .frame(width: 6, height: 6)
                .scaleEffect(pulse ? 1.3 : 1.0)
                .opacity(pulse ? 0.6 : 1.0)
                .animation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true), value: pulse)
            Text(text)
                .font(SCTheme.Type_.kicker())
                .tracking(1.2)
                .textCase(.uppercase)
                .foregroundStyle(tint)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            Capsule().fill(tint.opacity(0.12))
        )
        .onAppear { pulse = true }
    }
}

// Soft macro chip (used on totals card)
struct SCMacroChip: View {
    let label: String
    let value: String
    let tint: Color
    let softBg: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(SCTheme.Type_.kicker())
                .tracking(1.0)
                .foregroundStyle(tint)
            Text(value)
                .font(.system(size: 17, weight: .heavy, design: .rounded))
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(softBg.opacity(0.85), in: RoundedRectangle(cornerRadius: SCTheme.Radius.sm))
    }
}

// Hex color helper
extension Color {
    init(hex: UInt32, alpha: Double = 1.0) {
        let r = Double((hex >> 16) & 0xff) / 255.0
        let g = Double((hex >> 8) & 0xff) / 255.0
        let b = Double(hex & 0xff) / 255.0
        self.init(.sRGB, red: r, green: g, blue: b, opacity: alpha)
    }
}
