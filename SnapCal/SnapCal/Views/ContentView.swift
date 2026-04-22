import SwiftUI

struct ContentView: View {
    @State private var viewModel = TrackViewModel()
    @State private var showingCamera = false
    private let lidarEnabled = DepthCapability.isLiDAREnabled

    @AppStorage(ProfilePrefsKeys.appearance) private var appearance = "system"

    var body: some View {
        TabView {
            todayTab
                .tabItem {
                    Label("Track", systemImage: "camera.viewfinder")
                }

            ProfileView()
                .tabItem {
                    Label("Profile", systemImage: "person.crop.circle.fill")
                }
        }
        .tint(SCTheme.Colors.accentPink)
        .preferredColorScheme(resolvedScheme)
    }

    private var resolvedScheme: ColorScheme? {
        switch AppearancePreference(rawValue: appearance) {
        case .light: return .light
        case .dark:  return .dark
        case .system, .none: return nil
        }
    }

    private var todayTab: some View {
        NavigationStack {
            Group {
                switch viewModel.state {
                case .idle:
                    TodayView(
                        onTapCamera: { showingCamera = true },
                        lidarEnabled: lidarEnabled
                    )
                case .analyzing:
                    AnalyzingView(photo: viewModel.capturedPhoto, lidarEnabled: lidarEnabled)
                case .ready(let meal):
                    MealCardView(
                        meal: meal,
                        photo: viewModel.capturedPhoto,
                        onCommit: { updated in
                            viewModel.commitCorrections(updated)
                        },
                        onDietaryVariantChange: { item, preference, plateContext in
                            await viewModel.rematchDietaryVariant(
                                for: item,
                                preference: preference,
                                plateContext: plateContext
                            )
                        },
                        onSizeVariantChange: { item, sizeKey, plateContext in
                            await viewModel.rematchSizeVariant(
                                for: item,
                                sizeKey: sizeKey,
                                plateContext: plateContext
                            )
                        },
                        onLoadChains: {
                            await viewModel.loadSupportedChains()
                        },
                        onChainReapply: { item, chainName, plateContext in
                            await viewModel.rematchForChain(
                                item: item,
                                chainName: chainName,
                                plateContext: plateContext
                            )
                        },
                        pristineItemsProvider: {
                            viewModel.pristineItems
                        }
                    )
                case .failed(let message):
                    FailureView(message: message, onRetry: retake)
                }
            }
            .navigationTitle("SnapCal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if case .ready = viewModel.state {
                    ToolbarItem(placement: .topBarLeading) {
                        Button(action: retake) {
                            Label("Retake", systemImage: "chevron.left")
                                .labelStyle(.titleAndIcon)
                                .foregroundStyle(SCTheme.Colors.accentPink)
                        }
                    }
                }
                if case .analyzing = viewModel.state {
                    ToolbarItem(placement: .topBarLeading) {
                        Button(action: viewModel.reset) {
                            Label("Cancel", systemImage: "xmark")
                                .foregroundStyle(SCTheme.Colors.accentPink)
                        }
                    }
                }
                ToolbarItem(placement: .principal) {
                    SCBrandMark()
                }
            }
            .sheet(isPresented: $showingCamera) {
                CaptureGuideView(lidarEnabled: lidarEnabled) { image in
                    showingCamera = false
                    viewModel.analyze(image: image)
                }
            }
        }
    }

    private func retake() {
        viewModel.reset()
        showingCamera = true
    }
}

// MARK: - Brand mark for nav bar

private struct SCBrandMark: View {
    var body: some View {
        HStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(SCTheme.Gradients.cta)
                    .frame(width: 22, height: 22)
                Circle().fill(Color.white).frame(width: 6, height: 6)
            }
            Text("SnapCal")
                .font(.system(size: 17, weight: .heavy, design: .rounded))
                .foregroundStyle(.primary)
        }
    }
}

// MARK: - Analyzing

private struct AnalyzingView: View {
    let photo: UIImage?
    let lidarEnabled: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 8) {
                SCKickerPill(text: "Identifying", tint: SCTheme.Colors.accentOrange)
                if lidarEnabled {
                    SCKickerPill(text: "LiDAR depth", tint: SCTheme.Colors.standTeal)
                }
            }

            if let photo {
                Image(uiImage: photo)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity)
                    .frame(height: 300)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: SCTheme.Radius.lg))
                    .overlay(
                        RoundedRectangle(cornerRadius: SCTheme.Radius.lg)
                            .stroke(SCTheme.Colors.accentOrange.opacity(0.3), lineWidth: 1.5)
                    )
                    .overlay(alignment: .bottomTrailing) {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small).tint(.white)
                            Text("Analyzing…")
                                .font(SCTheme.Type_.caption())
                                .foregroundStyle(.white)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial, in: Capsule())
                        .overlay(Capsule().stroke(.white.opacity(0.2)))
                        .padding(16)
                    }
            }

            Text("Looking up verified nutrition")
                .font(SCTheme.Type_.body())
                .foregroundStyle(.secondary)

            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
    }
}

private struct CaptureGuideView: View {
    let lidarEnabled: Bool
    let onPicked: (UIImage) -> Void

    var body: some View {
        ZStack {
            CameraView(onPicked: onPicked)
                .ignoresSafeArea()

            VStack {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("For better portion accuracy")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                        Text("Include your hand, fork, or a clear plate edge.")
                            .font(SCTheme.Type_.caption())
                            .foregroundStyle(.white.opacity(0.95))
                    }
                    Spacer()
                    if lidarEnabled {
                        HStack(spacing: 4) {
                            Image(systemName: "dot.radiowaves.left.and.right")
                            Text("LiDAR")
                        }
                        .font(.system(size: 11, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(SCTheme.Colors.standTeal.opacity(0.82), in: Capsule())
                    }
                }
                .padding(12)
                .background(.black.opacity(0.42), in: RoundedRectangle(cornerRadius: SCTheme.Radius.sm))
                .overlay(RoundedRectangle(cornerRadius: SCTheme.Radius.sm).stroke(.white.opacity(0.16)))
                .padding(.horizontal, 16)
                .padding(.top, 18)

                Spacer()
            }
            .allowsHitTesting(false)
        }
    }
}

// MARK: - Failure

private struct FailureView: View {
    let message: String
    let onRetry: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Spacer()
            SCKickerPill(text: "Heads up", tint: SCTheme.Colors.accentPink)

            Text("Something went sideways.")
                .font(SCTheme.Type_.title())
                .foregroundStyle(.primary)

            Text(message)
                .font(SCTheme.Type_.body())
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer()

            Button(action: onRetry) {
                Label("Try again", systemImage: "arrow.clockwise")
                    .scCTAStyle()
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
    }
}

#Preview {
    ContentView()
}
