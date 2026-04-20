import SwiftUI

struct ContentView: View {
    @State private var viewModel = TrackViewModel()
    @State private var showingCamera = false

    var body: some View {
        NavigationStack {
            Group {
                switch viewModel.state {
                case .idle:
                    IdlePrompt(onTapCamera: { showingCamera = true })
                case .analyzing:
                    AnalyzingView(photo: viewModel.capturedPhoto)
                case .ready(let meal):
                    MealCardView(meal: meal, photo: viewModel.capturedPhoto) { updated in
                        viewModel.commitCorrections(updated)
                    }
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
                CameraView { image in
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

// MARK: - Idle prompt

private struct IdlePrompt: View {
    let onTapCamera: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Spacer(minLength: 20)

            SCKickerPill(text: "AI meal tracking", tint: SCTheme.Colors.accentOrange)

            VStack(alignment: .leading, spacing: 8) {
                Text("Snap.")
                    .font(SCTheme.Type_.hero(56))
                (
                    Text("Log.")
                        .font(SCTheme.Type_.hero(56))
                        .foregroundStyle(SCTheme.Gradients.heroText)
                    + Text(" Done.")
                        .font(SCTheme.Type_.hero(56))
                )
            }
            .foregroundStyle(.primary)

            Text("Point your camera at a meal. Calories and macros come from USDA's verified database, not a model's guess.")
                .font(SCTheme.Type_.body())
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer()

            VStack(spacing: 14) {
                Button(action: onTapCamera) {
                    Label("Snap a meal", systemImage: "camera.fill")
                        .scCTAStyle()
                }
                .buttonStyle(.plain)

                HStack(spacing: 14) {
                    SCMetaBadge(text: "Lab-verified")
                    SCMetaBadge(text: "No account")
                    SCMetaBadge(text: "Personalized")
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
    }
}

private struct SCMetaBadge: View {
    let text: String
    var body: some View {
        Text(text)
            .font(SCTheme.Type_.caption())
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Capsule().fill(.quaternary.opacity(0.4)))
    }
}

// MARK: - Analyzing

private struct AnalyzingView: View {
    let photo: UIImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            SCKickerPill(text: "Identifying", tint: SCTheme.Colors.accentOrange)

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
