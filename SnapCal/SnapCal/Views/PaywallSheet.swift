import SwiftUI

#if canImport(RevenueCat)
import RevenueCat
#endif

// Shown whenever a free-tier user taps a Pro-gated feature. Pulls the
// current offering from RevenueCat and lists its packages; falls back to
// a "coming soon" state when the SDK isn't installed or no offering has
// been published yet, so the gate path is always navigable in dev builds.
struct PaywallSheet: View {
    let trigger: String                  // shown in the eyebrow ("UNLOCK SCAN ALERTS")
    let valueProps: [String]

    @Environment(\.dismiss) private var dismiss
    @State private var subs = Subscriptions.shared
    @State private var purchasing = false
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                eyebrow
                title
                propsList
                packagesSection
                restoreLink
            }
            .padding(.horizontal, 22)
            .padding(.top, 12)
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
        .alert(
            "Couldn't complete purchase",
            isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
        ) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .task { await subs.refresh() }
    }

    private var eyebrow: some View {
        HStack(spacing: 6) {
            Image(systemName: "sparkles")
                .font(.system(size: 11, weight: .heavy))
            Text(trigger.uppercased())
                .font(.system(size: 11, weight: .heavy, design: .rounded))
                .tracking(1.2)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(SCTheme.Gradients.cta, in: Capsule())
    }

    private var title: some View {
        Text("Get SnapCal Pro")
            .font(.system(size: 28, weight: .heavy, design: .rounded))
            .tracking(-0.4)
            .foregroundStyle(.primary)
    }

    private var propsList: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(valueProps, id: \.self) { line in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(SCTheme.Colors.accentPink)
                    Text(line)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    @ViewBuilder
    private var packagesSection: some View {
        #if canImport(RevenueCat)
        if let offering = subs.currentOffering, !offering.availablePackages.isEmpty {
            VStack(spacing: 10) {
                ForEach(offering.availablePackages, id: \.identifier) { pkg in
                    Button {
                        Task { await purchase(pkg) }
                    } label: {
                        packageRow(
                            title: pkg.storeProduct.localizedTitle,
                            price: pkg.storeProduct.localizedPriceString,
                            subtitle: pkg.storeProduct.localizedDescription
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(purchasing)
                }
            }
        } else {
            comingSoon
        }
        #else
        comingSoon
        #endif
    }

    private func packageRow(title: String, price: String, subtitle: String) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 16, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                Text(subtitle)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(2)
            }
            Spacer()
            Text(price)
                .font(.system(size: 17, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(SCTheme.Gradients.cta, in: RoundedRectangle(cornerRadius: 14))
        .shadow(color: SCTheme.Colors.accentPink.opacity(0.25), radius: 8, y: 4)
    }

    private var comingSoon: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Pricing coming soon")
                .font(.system(size: 16, weight: .heavy, design: .rounded))
                .foregroundStyle(.primary)
            Text("Once your RevenueCat offering is published, your packages show up here automatically.")
                .font(SCTheme.Type_.caption())
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .scCardStyle()
    }

    private var restoreLink: some View {
        HStack {
            Spacer()
            Button {
                Task { await subs.restore() }
            } label: {
                Text("Restore purchases")
                    .font(.system(size: 13, weight: .heavy, design: .rounded))
                    .foregroundStyle(SCTheme.Colors.accentPink)
            }
            Spacer()
        }
    }

    #if canImport(RevenueCat)
    private func purchase(_ package: Package) async {
        purchasing = true
        let outcome = await subs.purchase(package)
        purchasing = false
        switch outcome {
        case .purchased: dismiss()
        case .cancelled, .pending: break
        case .failed(let message): errorMessage = message
        }
    }
    #endif
}
