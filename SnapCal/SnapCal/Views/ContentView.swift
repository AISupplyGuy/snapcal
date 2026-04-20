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
            .toolbar {
                if case .ready = viewModel.state {
                    ToolbarItem(placement: .topBarLeading) {
                        Button(role: .cancel, action: retake) {
                            Label("Retake", systemImage: "chevron.left")
                        }
                    }
                }
                if case .analyzing = viewModel.state {
                    ToolbarItem(placement: .topBarLeading) {
                        Button(role: .cancel, action: viewModel.reset) {
                            Label("Cancel", systemImage: "xmark")
                        }
                    }
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

private struct IdlePrompt: View {
    let onTapCamera: () -> Void
    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "fork.knife.circle")
                .font(.system(size: 72))
                .foregroundStyle(.secondary)
            Text("Snap your meal")
                .font(.title2)
            Text("Include your hand or a fork in the frame for better portion accuracy.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Button(action: onTapCamera) {
                Label("Open camera", systemImage: "camera.fill")
                    .font(.headline)
                    .padding()
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal)
            Spacer()
        }
    }
}

private struct AnalyzingView: View {
    let photo: UIImage?

    var body: some View {
        VStack(spacing: 16) {
            if let photo {
                Image(uiImage: photo)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity)
                    .frame(height: 260)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(.quaternary, lineWidth: 1))
                    .padding(.horizontal)
                    .overlay(alignment: .bottomTrailing) {
                        Image(systemName: "sparkle")
                            .font(.title2)
                            .padding(10)
                            .background(.thinMaterial, in: Circle())
                            .padding(24)
                    }
            }
            ProgressView().controlSize(.large)
            Text("Identifying items…")
                .foregroundStyle(.secondary)
            Text("Looking up verified nutrition")
                .font(.footnote)
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .padding(.top, 20)
    }
}

private struct FailureView: View {
    let message: String
    let onRetry: () -> Void
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.largeTitle)
                .foregroundStyle(.orange)
            Text(message).multilineTextAlignment(.center).padding(.horizontal)
            Button("Try again", action: onRetry).buttonStyle(.borderedProminent)
        }
    }
}

#Preview {
    ContentView()
}
