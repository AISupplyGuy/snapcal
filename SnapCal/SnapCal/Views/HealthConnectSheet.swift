import SwiftUI

// Sheet shown when the user taps "Apple Health" in Profile. Lays out the
// three scopes SnapCal asks for, shows a single big button that fires
// HealthKit's permission sheet (one prompt covers all scopes), then
// updates the row in Profile with the resolved status.
//
// Design intent: NOT a generic "connect" sheet. Each scope has its own
// row with the SnapCal-specific reason. Apple's permission UI shows the
// system text from Info.plist; this sheet sells the value first so the
// user knows why before the OS asks them to confirm.
struct HealthConnectSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var health = HealthKitService.shared
    @State private var requesting = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                heroBlock
                scopeList
                statusRow
                primaryButton
                disclaimer
            }
            .padding(.horizontal, 22)
            .padding(.top, 18)
            .padding(.bottom, 32)
        }
        .background(.background)
        .overlay(alignment: .topTrailing) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(.secondary)
                    .padding(10)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .padding(.top, 12)
            .padding(.trailing, 16)
        }
        .onAppear { health.refreshAuthState() }
    }

    private var heroBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            ZStack {
                Circle()
                    .fill(LinearGradient(
                        colors: [SCTheme.Colors.accentPink, Color(hex: 0xBF5AF2)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                    .frame(width: 64, height: 64)
                    .shadow(color: SCTheme.Colors.accentPink.opacity(0.35), radius: 14, y: 6)
                Image(systemName: "heart.fill")
                    .font(.system(size: 28, weight: .heavy))
                    .foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Apple Health")
                    .font(.system(size: 28, weight: .heavy, design: .rounded))
                    .tracking(-0.4)
                    .foregroundStyle(.primary)
                Text("Two-way sync. Your weights, meals, and Watch energy land in one place — no double entry.")
                    .font(SCTheme.Type_.body())
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var scopeList: some View {
        VStack(spacing: 10) {
            ScopeRow(
                icon: "scalemass.fill",
                tint: SCTheme.Colors.proteinBlue,
                title: "Body weight",
                copy: "We pull your weight history into Insights and write back any weight you log in SnapCal."
            )
            ScopeRow(
                icon: "fork.knife",
                tint: SCTheme.Colors.accentOrange,
                title: "Nutrition",
                copy: "Every meal you log writes calories, protein, carbs, and fat into Apple Health's Nutrition tab."
            )
            ScopeRow(
                icon: "flame.fill",
                tint: SCTheme.Colors.accentPink,
                title: "Active energy",
                copy: "We read your Apple Watch active energy so Insights can show net calories vs your weight trend."
            )
        }
    }

    private var statusRow: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(statusTint)
                .frame(width: 8, height: 8)
            Text(statusText)
                .font(.system(size: 13, weight: .heavy, design: .rounded))
                .foregroundStyle(.primary)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(statusTint.opacity(0.1), in: Capsule())
        .overlay(Capsule().stroke(statusTint.opacity(0.3), lineWidth: 0.5))
    }

    private var statusTint: Color {
        switch health.authState {
        case .granted:     return SCTheme.Colors.carbGreen
        case .denied:      return SCTheme.Colors.accentPink
        case .unavailable: return .secondary
        case .unknown:     return SCTheme.Colors.accentOrange
        }
    }

    private var statusText: String {
        switch health.authState {
        case .granted:     return "Connected — syncing in both directions"
        case .denied:      return "Permission denied — open Settings to allow"
        case .unavailable: return "Apple Health is unavailable on this device"
        case .unknown:     return "Tap connect to grant permissions"
        }
    }

    @ViewBuilder
    private var primaryButton: some View {
        if health.authState == .granted {
            Button {
                dismiss()
            } label: {
                Label("Done", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 16, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(SCTheme.Gradients.cta, in: Capsule())
                    .shadow(color: SCTheme.Colors.accentPink.opacity(0.3), radius: 10, y: 5)
            }
            .buttonStyle(.plain)
        } else if health.authState == .denied {
            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            } label: {
                Label("Open Settings", systemImage: "gear")
                    .font(.system(size: 16, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(SCTheme.Gradients.cta, in: Capsule())
            }
            .buttonStyle(.plain)
        } else {
            Button {
                Task { await connect() }
            } label: {
                HStack(spacing: 8) {
                    if requesting {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: "heart.fill")
                    }
                    Text(requesting ? "Connecting…" : "Connect Apple Health")
                }
                .font(.system(size: 16, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(SCTheme.Gradients.cta, in: Capsule())
                .shadow(color: SCTheme.Colors.accentPink.opacity(0.3), radius: 10, y: 5)
            }
            .buttonStyle(.plain)
            .disabled(requesting || health.authState == .unavailable)
        }
    }

    private var disclaimer: some View {
        Text("Apple Health stays on your device. SnapCal only reads what you grant and writes only what you log here.")
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func connect() async {
        requesting = true
        let result = await health.requestAuthorization()
        requesting = false
        if result == .granted {
            // Backfill: pull weight history and refresh active energy cache.
            let imported = await health.recentWeights()
            WeightLog.shared.ingestFromHealth(imported)
        }
    }
}

// MARK: - Row

private struct ScopeRow: View {
    let icon: String
    let tint: Color
    let title: String
    let copy: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(tint.opacity(0.15))
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .heavy))
                    .foregroundStyle(tint)
            }
            .frame(width: 38, height: 38)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .foregroundStyle(.primary)
                Text(copy)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .scCardStyle()
    }
}
