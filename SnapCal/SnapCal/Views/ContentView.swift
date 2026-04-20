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
                    AnalyzingView()
                case .ready(let meal):
                    MealCardView(meal: meal) { updated in
                        viewModel.commitCorrections(updated)
                    }
                case .failed(let message):
                    FailureView(message: message, onRetry: { showingCamera = true })
                }
            }
            .navigationTitle("SnapCal")
            .sheet(isPresented: $showingCamera) {
                CameraView { image in
                    showingCamera = false
                    viewModel.analyze(image: image)
                }
            }
        }
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
    var body: some View {
        VStack(spacing: 16) {
            ProgressView().controlSize(.large)
            Text("Identifying items…")
                .foregroundStyle(.secondary)
            Text("Looking up verified nutrition")
                .font(.footnote)
                .foregroundStyle(.tertiary)
        }
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
