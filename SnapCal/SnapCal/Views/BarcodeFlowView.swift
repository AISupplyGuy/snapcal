import SwiftUI
import UIKit

// End-to-end barcode entry flow. Owns the small state machine (scanning →
// loading → picking → confirming) so ContentView only has to mount this
// once. Per ARCHITECTURE.md Layer 2, every scan goes through a confirm
// step before logging — never auto-commit, never auto-pick on multiple
// candidates.
struct BarcodeFlowView: View {
    enum Phase: Equatable {
        case scanning
        case loading(barcode: String)
        case picking([BarcodeProduct])
        case confirming(BarcodeProduct)
        case failed(String)
    }

    let onCommit: (BarcodeProduct, Double) -> Void
    let onClose: () -> Void

    @State private var phase: Phase = .scanning
    // Bumped every time we re-enter .scanning so the AVCaptureSession is
    // freshly created instead of stuck stopped from the prior scan.
    @State private var scannerToken = 0

    var body: some View {
        ZStack {
            BarcodeScannerView(
                onScanned: handleScanned,
                onError: { phase = .failed($0) }
            )
            .id(scannerToken)
            .ignoresSafeArea()

            // Reticle + dimming above the camera. Drawn always so the
            // user sees the framing rectangle while scanning.
            reticleOverlay

            VStack {
                topBar
                Spacer()
                bottomCard
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .preferredColorScheme(.dark)
    }

    // MARK: Phase routing

    private func handleScanned(_ code: String) {
        guard case .scanning = phase else { return }
        phase = .loading(barcode: code)
        Task {
            do {
                let products = try await OpenFoodFactsService.shared.products(for: code)
                await MainActor.run {
                    if products.isEmpty {
                        phase = .failed("We couldn't find that barcode. Try again or add it manually.")
                    } else if products.count == 1 {
                        phase = .confirming(products[0])
                    } else {
                        phase = .picking(products)
                    }
                }
            } catch {
                await MainActor.run {
                    phase = .failed(error.localizedDescription)
                }
            }
        }
    }

    private func resetToScanning() {
        scannerToken &+= 1
        phase = .scanning
    }

    // MARK: Pieces

    private var topBar: some View {
        HStack {
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(.white)
                    .padding(10)
                    .background(.black.opacity(0.45), in: Circle())
                    .overlay(Circle().stroke(.white.opacity(0.18)))
            }
            Spacer()
            HStack(spacing: 6) {
                Image(systemName: "barcode.viewfinder")
                    .font(.system(size: 12, weight: .heavy))
                Text(headlineLabel)
                    .font(.system(size: 12, weight: .heavy, design: .rounded))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.black.opacity(0.45), in: Capsule())
            .overlay(Capsule().stroke(.white.opacity(0.18)))
        }
        .padding(.top, 4)
    }

    private var headlineLabel: String {
        switch phase {
        case .scanning:        return "Scan a barcode"
        case .loading:         return "Looking it up…"
        case .picking:         return "Pick the right one"
        case .confirming:      return "Confirm before logging"
        case .failed:          return "Couldn't read"
        }
    }

    private var reticleOverlay: some View {
        GeometryReader { geo in
            let width = min(geo.size.width - 64, 320)
            let height: CGFloat = 180
            ZStack {
                RoundedRectangle(cornerRadius: 18)
                    .stroke(Color.white.opacity(0.85), lineWidth: 3)
                    .frame(width: width, height: height)
                    .shadow(color: .black.opacity(0.3), radius: 6)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .opacity(reticleVisible ? 1 : 0)
        }
        .allowsHitTesting(false)
    }

    private var reticleVisible: Bool {
        if case .scanning = phase { return true }
        if case .loading = phase  { return true }
        return false
    }

    @ViewBuilder
    private var bottomCard: some View {
        switch phase {
        case .scanning:
            instructionCard
        case .loading(let code):
            loadingCard(code: code)
        case .picking(let products):
            pickerCard(products: products)
        case .confirming(let product):
            ConfirmCard(
                product: product,
                onConfirm: { servings in onCommit(product, servings) },
                onReject: resetToScanning
            )
        case .failed(let message):
            failureCard(message: message)
        }
    }

    private var instructionCard: some View {
        Text("Hold a barcode inside the frame.")
            .font(.system(size: 14, weight: .heavy, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity)
            .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.15)))
    }

    private func loadingCard(code: String) -> some View {
        HStack(spacing: 12) {
            ProgressView().tint(.white)
            VStack(alignment: .leading, spacing: 2) {
                Text("Looking up \(code)")
                    .font(.system(size: 14, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                Text("Open Food Facts")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.7))
            }
            Spacer()
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.18)))
    }

    private func pickerCard(products: [BarcodeProduct]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Multiple products share that code. Pick the one in front of you.")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.85))

            ScrollView {
                VStack(spacing: 8) {
                    ForEach(products) { product in
                        Button {
                            phase = .confirming(product)
                        } label: {
                            HStack(spacing: 12) {
                                ProductThumb(url: product.imageURL)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(product.displayName)
                                        .font(.system(size: 14, weight: .heavy, design: .rounded))
                                        .foregroundStyle(.white)
                                        .lineLimit(2)
                                        .multilineTextAlignment(.leading)
                                    if let brand = product.brand {
                                        Text(brand)
                                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                                            .foregroundStyle(.white.opacity(0.7))
                                    }
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .foregroundStyle(.white.opacity(0.6))
                            }
                            .padding(12)
                            .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.12)))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(maxHeight: 240)
        }
        .padding(14)
        .background(.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.18)))
    }

    private func failureCard(message: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(SCTheme.Colors.accentOrange)
                Text("Couldn't read this one")
                    .font(.system(size: 14, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
            }
            Text(message)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                Button(action: resetToScanning) {
                    Label("Scan again", systemImage: "arrow.clockwise")
                        .font(.system(size: 13, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(SCTheme.Gradients.cta, in: Capsule())
                }
                .buttonStyle(.plain)

                Button(action: onClose) {
                    Text("Close")
                        .font(.system(size: 13, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(.white.opacity(0.12), in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.18)))
    }
}

// MARK: - Confirm card (shared between single-result and post-pick)

private struct ConfirmCard: View {
    let product: BarcodeProduct
    let onConfirm: (Double) -> Void
    let onReject: () -> Void

    @State private var servings: Double = 1.0

    private var perServing: NutritionFacts {
        product.per100g.scaled(by: (product.servingGrams ?? 100) / 100.0)
    }
    private var totalNutrition: NutritionFacts {
        perServing.scaled(by: servings)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                ProductThumb(url: product.imageURL, size: 64)
                VStack(alignment: .leading, spacing: 2) {
                    Text(product.displayName)
                        .font(.system(size: 16, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                    if let brand = product.brand {
                        Text(brand)
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.7))
                    }
                    Text(servingLabel)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.6))
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 0) {
                    Text("\(Int(totalNutrition.calories.rounded()))")
                        .font(.system(size: 28, weight: .heavy, design: .rounded))
                        .foregroundStyle(SCTheme.Colors.accentOrange)
                    Text("kcal")
                        .font(.system(size: 11, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white.opacity(0.7))
                }
            }

            HStack(spacing: 8) {
                macroChip("P", grams: totalNutrition.proteinGrams)
                macroChip("C", grams: totalNutrition.carbGrams)
                macroChip("F", grams: totalNutrition.fatGrams)
            }

            servingsStepper

            HStack(spacing: 10) {
                Button(action: onReject) {
                    Text("Not this one")
                        .font(.system(size: 13, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(.white.opacity(0.12), in: Capsule())
                }
                .buttonStyle(.plain)

                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    onConfirm(servings)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                        Text("Log it")
                    }
                    .font(.system(size: 14, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(SCTheme.Gradients.cta, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .background(.black.opacity(0.78), in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(.white.opacity(0.18)))
    }

    private var servingLabel: String {
        if let grams = product.servingGrams {
            return "Serving \(Int(grams.rounded())) g"
        }
        return "Per 100 g"
    }

    private var servingsStepper: some View {
        HStack(spacing: 12) {
            Text("Servings")
                .font(.system(size: 12, weight: .heavy, design: .rounded))
                .foregroundStyle(.white.opacity(0.75))
            Spacer()
            Button {
                servings = max(0.25, servings - 0.25)
            } label: {
                Image(systemName: "minus")
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(.white.opacity(0.14), in: Circle())
            }
            .buttonStyle(.plain)

            Text(String(format: "%.2g", servings))
                .font(.system(size: 16, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .monospacedDigit()
                .frame(minWidth: 40)

            Button {
                servings += 0.25
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(.white.opacity(0.14), in: Circle())
            }
            .buttonStyle(.plain)
        }
    }

    private func macroChip(_ letter: String, grams: Double) -> some View {
        HStack(spacing: 4) {
            Text(letter)
                .font(.system(size: 10, weight: .heavy, design: .rounded))
                .foregroundStyle(.white.opacity(0.7))
            Text("\(Int(grams.rounded()))g")
                .font(.system(size: 12, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(.white.opacity(0.1), in: Capsule())
    }
}

// MARK: - Image helper

private struct ProductThumb: View {
    let url: URL?
    var size: CGFloat = 44

    var body: some View {
        Group {
            if let url {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(.white.opacity(0.18)))
    }

    private var placeholder: some View {
        ZStack {
            Color.white.opacity(0.08)
            Image(systemName: "shippingbox.fill")
                .foregroundStyle(.white.opacity(0.5))
        }
    }
}
