import SwiftUI

#if canImport(RevenueCat)
import RevenueCat
#endif

// Shown whenever a free-tier user taps a Pro-gated feature. Pulls the
// current offering from RevenueCat and lists its packages; falls back to
// a "soon" state when the SDK isn't installed or no offering has been
// published, so the gate path is always navigable in dev builds.
struct PaywallSheet: View {
    let trigger: String
    let valueProps: [String]

    @Environment(\.dismiss) private var dismiss
    @State private var subs = Subscriptions.shared
    @State private var purchasing = false
    @State private var errorMessage: String?
    @State private var heroPulse = false

    var body: some View {
        ZStack(alignment: .top) {
            ambient
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    hero
                    propsList
                    packagesSection
                    fineprint
                }
                .padding(.horizontal, 22)
                .padding(.top, 24)
                .padding(.bottom, 60)
            }
            .scrollIndicators(.hidden)
            closeButton
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
        .onAppear { heroPulse = true }
    }

    // MARK: Ambient

    private var ambient: some View {
        ZStack {
            RadialGradient(
                colors: [SCTheme.Colors.accentPink.opacity(0.32), .clear],
                center: .top,
                startRadius: 20,
                endRadius: 460
            )
            RadialGradient(
                colors: [SCTheme.Colors.accentOrange.opacity(0.18), .clear],
                center: .topTrailing,
                startRadius: 20,
                endRadius: 360
            )
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    private var closeButton: some View {
        HStack {
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(.secondary)
                    .frame(width: 32, height: 32)
                    .background(.ultraThinMaterial, in: Circle())
                    .overlay(Circle().strokeBorder(.white.opacity(0.08)))
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 14)
    }

    // MARK: Hero

    private var hero: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle()
                    .fill(SCTheme.Gradients.cta)
                    .frame(width: 96, height: 96)
                    .blur(radius: heroPulse ? 22 : 14)
                    .opacity(0.55)
                    .animation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true), value: heroPulse)
                Circle()
                    .fill(SCTheme.Gradients.cta)
                    .frame(width: 76, height: 76)
                    .overlay {
                        Image(systemName: "sparkles")
                            .font(.system(size: 30, weight: .heavy))
                            .foregroundStyle(.white)
                    }
                    .shadow(color: SCTheme.Colors.accentPink.opacity(0.45), radius: 14, y: 8)
            }
            .padding(.top, 12)

            VStack(spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "lock.open.fill")
                        .font(.system(size: 10, weight: .heavy))
                    Text(trigger.uppercased())
                        .font(.system(size: 11, weight: .heavy, design: .rounded))
                        .tracking(1.2)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(SCTheme.Gradients.cta, in: Capsule())

                Text("SnapCal Pro")
                    .font(.system(size: 38, weight: .heavy, design: .rounded))
                    .tracking(-0.6)
                    .foregroundStyle(SCTheme.Gradients.heroText)

                Text("Everything in SnapCal, no daily limits, plus the projection charts.")
                    .font(SCTheme.Type_.body())
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 12)
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Value props

    private var propsList: some View {
        VStack(spacing: 10) {
            ForEach(Array(valueProps.enumerated()), id: \.offset) { idx, line in
                propRow(idx: idx, text: line)
            }
        }
    }

    private func propRow(idx: Int, text: String) -> some View {
        HStack(alignment: .center, spacing: 14) {
            ZStack {
                Circle()
                    .fill(SCTheme.Colors.accentPink.opacity(0.18))
                    .frame(width: 36, height: 36)
                Image(systemName: propIcon(for: idx))
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(SCTheme.Colors.accentPink)
            }
            Text(text)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: SCTheme.Radius.md, style: .continuous)
                .fill(.ultraThinMaterial)
        }
        .overlay {
            RoundedRectangle(cornerRadius: SCTheme.Radius.md, style: .continuous)
                .strokeBorder(.white.opacity(0.06))
        }
    }

    private func propIcon(for index: Int) -> String {
        let icons = ["chart.line.uptrend.xyaxis", "heart.text.square.fill", "infinity", "wand.and.stars", "sparkles"]
        return icons[index % icons.count]
    }

    // MARK: Packages

    @ViewBuilder
    private var packagesSection: some View {
        #if canImport(RevenueCat)
        if let offering = subs.currentOffering, !offering.availablePackages.isEmpty {
            let ranked = rankedPackages(offering.availablePackages)
            VStack(spacing: 12) {
                ForEach(Array(ranked.enumerated()), id: \.element.identifier) { idx, pkg in
                    Button {
                        Task { await purchase(pkg) }
                    } label: {
                        packageCard(pkg, isPrimary: idx == 0, savingsLabel: savings(for: pkg, against: ranked))
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

    #if canImport(RevenueCat)
    private func rankedPackages(_ packages: [Package]) -> [Package] {
        // Annual first (most value), then monthly, then anything else.
        packages.sorted { lhs, rhs in
            packagePriority(lhs) < packagePriority(rhs)
        }
    }

    private func packagePriority(_ package: Package) -> Int {
        let id = package.identifier.lowercased()
        if id.contains("annual") || id.contains("year") { return 0 }
        if id.contains("month") { return 1 }
        return 2
    }

    private func savings(for package: Package, against ranked: [Package]) -> String? {
        guard packagePriority(package) == 0,
              let monthly = ranked.first(where: { packagePriority($0) == 1 })
        else { return nil }
        let annualPrice = package.storeProduct.price as Decimal
        let monthlyPrice = monthly.storeProduct.price as Decimal
        let perMonth = annualPrice / 12
        let pct = NSDecimalNumber(decimal: (monthlyPrice - perMonth) / monthlyPrice).doubleValue
        guard pct > 0.01 else { return nil }
        return "Save \(Int((pct * 100).rounded()))%"
    }

    private func packageCard(_ package: Package, isPrimary: Bool, savingsLabel: String?) -> some View {
        let title = packageTitle(package)
        let priceMain = package.storeProduct.localizedPriceString
        let perMonth = perMonthString(package)

        return HStack(alignment: .center, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isPrimary ? Color.white.opacity(0.18) : SCTheme.Colors.accentPink.opacity(0.18))
                    .frame(width: 44, height: 44)
                Image(systemName: isPrimary ? "crown.fill" : "calendar")
                    .font(.system(size: 16, weight: .heavy))
                    .foregroundStyle(isPrimary ? .white : SCTheme.Colors.accentPink)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(title)
                        .font(.system(size: 16, weight: .heavy, design: .rounded))
                    if let savingsLabel {
                        Text(savingsLabel.uppercased())
                            .font(.system(size: 9, weight: .heavy, design: .rounded))
                            .tracking(0.8)
                            .foregroundStyle(isPrimary ? SCTheme.Colors.accentPink : .white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(isPrimary ? .white : SCTheme.Colors.accentPink))
                    }
                }
                if let perMonth {
                    Text(perMonth)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(isPrimary ? .white.opacity(0.85) : .secondary)
                }
            }
            .foregroundStyle(isPrimary ? .white : .primary)

            Spacer()

            Text(priceMain)
                .font(.system(size: 17, weight: .heavy, design: .rounded))
                .foregroundStyle(isPrimary ? .white : .primary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .background {
            if isPrimary {
                RoundedRectangle(cornerRadius: SCTheme.Radius.md, style: .continuous)
                    .fill(SCTheme.Gradients.cta)
            } else {
                RoundedRectangle(cornerRadius: SCTheme.Radius.md, style: .continuous)
                    .fill(.ultraThinMaterial)
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: SCTheme.Radius.md, style: .continuous)
                .strokeBorder(isPrimary ? .white.opacity(0.18) : .white.opacity(0.06))
        }
        .shadow(
            color: isPrimary ? SCTheme.Colors.accentPink.opacity(0.32) : .black.opacity(0.18),
            radius: isPrimary ? 14 : 10,
            y: isPrimary ? 8 : 5
        )
    }

    private func packageTitle(_ package: Package) -> String {
        let id = package.identifier.lowercased()
        if id.contains("annual") || id.contains("year") { return "Annual" }
        if id.contains("month") { return "Monthly" }
        return package.storeProduct.localizedTitle
    }

    private func perMonthString(_ package: Package) -> String? {
        let id = package.identifier.lowercased()
        guard id.contains("annual") || id.contains("year") else { return nil }
        let price = package.storeProduct.price as Decimal
        let perMonth = price / 12
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = package.storeProduct.priceFormatter?.locale ?? .current
        formatter.currencyCode = package.storeProduct.currencyCode
        let value = NSDecimalNumber(decimal: perMonth)
        guard let formatted = formatter.string(from: value) else { return nil }
        return "\(formatted)/mo billed yearly"
    }
    #endif

    private var comingSoon: some View {
        VStack(spacing: 10) {
            Image(systemName: "hourglass")
                .font(.system(size: 22, weight: .heavy))
                .foregroundStyle(SCTheme.Colors.accentPink)
                .padding(10)
                .background(Circle().fill(SCTheme.Colors.accentPink.opacity(0.14)))
            Text("Pricing arriving shortly")
                .font(.system(size: 16, weight: .heavy, design: .rounded))
                .foregroundStyle(.primary)
            Text("Plans show up here automatically once the App Store offering is live.")
                .font(SCTheme.Type_.caption())
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background {
            RoundedRectangle(cornerRadius: SCTheme.Radius.md, style: .continuous)
                .fill(.ultraThinMaterial)
        }
        .overlay {
            RoundedRectangle(cornerRadius: SCTheme.Radius.md, style: .continuous)
                .strokeBorder(.white.opacity(0.06))
        }
    }

    // MARK: Fineprint

    private var fineprint: some View {
        VStack(spacing: 10) {
            HStack(spacing: 14) {
                Button {
                    Task { await subs.restore() }
                } label: {
                    Text("Restore purchases")
                        .font(.system(size: 12, weight: .heavy, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                Text("·").foregroundStyle(.tertiary)
                Text("Cancel anytime")
                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            Text("Auto-renews until cancelled. Manage in App Store settings.")
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 4)
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
