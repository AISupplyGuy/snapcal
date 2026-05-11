import SwiftUI
import UIKit

// Hands-on cooking mode. Full-bleed, one step at a time, big timer, swipe
// or tap to advance. The intent is "phone on the counter, hands free
// minus a tap" — text is large, contrast is high, the screen stays awake
// while you're in the flow.
//
// Final step swaps "Next" for "I cooked it" — that fires logToTrack() at
// the active serving size and pops back to the recipe detail with a
// confetti-ish toast.
struct CookModeView: View {
    let recipe: Recipe

    @Environment(\.dismiss) private var dismiss

    @State private var currentIndex = 0
    @State private var timerRemaining: Int = 0
    @State private var timerRunning = false
    @State private var timer: Timer?
    @State private var servingsToLog: Double = 1
    @State private var didLog = false

    private var step: RecipeStep { recipe.steps[currentIndex] }
    private var isLast: Bool { currentIndex == recipe.steps.count - 1 }
    private var progress: Double { Double(currentIndex + 1) / Double(max(1, recipe.steps.count)) }

    var body: some View {
        ZStack {
            background.ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                progressTrack
                Spacer(minLength: 0)
                stepBody
                Spacer(minLength: 0)
                if let _ = step.timerSeconds {
                    timerCard
                }
                bottomMacroBar
                advanceControls
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 18)
        }
        .toolbar(.hidden)
        .onAppear { resetTimerForCurrentStep() }
        .onDisappear { invalidateTimer(); UIApplication.shared.isIdleTimerDisabled = false }
        .gesture(
            DragGesture(minimumDistance: 30)
                .onEnded { value in
                    if value.translation.width < -50 { advance() }
                    else if value.translation.width > 50 { regress() }
                }
        )
    }

    private var background: LinearGradient {
        switch recipe.palette {
        case .sunset: return LinearGradient(colors: [SCTheme.Colors.accentPink, SCTheme.Colors.accentOrange.opacity(0.9)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .grove:  return LinearGradient(colors: [SCTheme.Colors.carbGreen, Color(hex: 0x16A34A)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .ocean:  return LinearGradient(colors: [SCTheme.Colors.proteinBlue, Color(hex: 0x5856D6)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .berry:  return LinearGradient(colors: [Color(hex: 0xBF5AF2), SCTheme.Colors.accentPink], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .ember:  return LinearGradient(colors: [Color(hex: 0xFF6B35), Color(hex: 0xC42D52)], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }

    // MARK: Top bar

    private var topBar: some View {
        HStack {
            Button {
                invalidateTimer()
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(.white)
                    .padding(10)
                    .background(.white.opacity(0.18), in: Circle())
                    .overlay(Circle().stroke(.white.opacity(0.25)))
            }
            Spacer()
            Text(recipe.name)
                .font(.system(size: 13, weight: .heavy, design: .rounded))
                .foregroundStyle(.white.opacity(0.92))
                .lineLimit(1)
            Spacer()
            Color.clear.frame(width: 36, height: 36)
        }
        .padding(.top, 8)
    }

    private var progressTrack: some View {
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.18))
                    Capsule()
                        .fill(.white)
                        .frame(width: max(8, geo.size.width * progress))
                        .animation(.easeOut(duration: 0.25), value: progress)
                }
            }
            .frame(height: 6)
            HStack {
                Text("Step \(currentIndex + 1) of \(recipe.steps.count)")
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white.opacity(0.85))
                    .tracking(0.8)
                Spacer()
                Text("Swipe to advance")
                    .font(.system(size: 10, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
        .padding(.top, 12)
    }

    // MARK: Step body

    private var stepBody: some View {
        Text(step.instruction)
            .font(.system(size: 28, weight: .heavy, design: .rounded))
            .tracking(-0.4)
            .foregroundStyle(.white)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 24)
            .transition(.opacity.combined(with: .move(edge: .trailing)))
            .id(currentIndex)
    }

    // MARK: Timer

    @ViewBuilder
    private var timerCard: some View {
        let display = formatTime(timerRemaining)
        VStack(spacing: 8) {
            Text(display)
                .font(.system(size: 48, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
                .contentTransition(.numericText(value: Double(timerRemaining)))
            HStack(spacing: 10) {
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    if timerRunning { pauseTimer() } else { startTimer() }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: timerRunning ? "pause.fill" : "play.fill")
                        Text(timerRunning ? "Pause" : "Start")
                    }
                    .font(.system(size: 13, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(.white.opacity(0.18), in: Capsule())
                    .overlay(Capsule().stroke(.white.opacity(0.3)))
                }
                .buttonStyle(.plain)
                Button {
                    resetTimerForCurrentStep()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 13, weight: .heavy))
                        .foregroundStyle(.white)
                        .padding(10)
                        .background(.white.opacity(0.18), in: Circle())
                        .overlay(Circle().stroke(.white.opacity(0.3)))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.bottom, 8)
    }

    // MARK: Bottom macro tally

    private var bottomMacroBar: some View {
        HStack(spacing: 8) {
            macroChip("kcal", "\(Int(recipe.perServing.calories))")
            macroChip("P", "\(Int(recipe.perServing.proteinGrams))g")
            macroChip("C", "\(Int(recipe.perServing.carbGrams))g")
            macroChip("F", "\(Int(recipe.perServing.fatGrams))g")
        }
        .padding(.vertical, 8)
    }

    private func macroChip(_ label: String, _ value: String) -> some View {
        VStack(spacing: 1) {
            Text(value)
                .font(.system(size: 13, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
            Text(label.uppercased())
                .font(.system(size: 9, weight: .heavy, design: .rounded))
                .tracking(0.8)
                .foregroundStyle(.white.opacity(0.7))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(.white.opacity(0.16), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.18)))
    }

    // MARK: Advance / finish

    @ViewBuilder
    private var advanceControls: some View {
        if isLast {
            VStack(spacing: 10) {
                servingsStepper
                Button {
                    UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
                    logToTrack(recipe: recipe, servings: servingsToLog)
                    didLog = true
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 800_000_000)
                        dismiss()
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: didLog ? "checkmark.circle.fill" : "checkmark.circle")
                        Text(didLog ? "Logged" : "I cooked it — log to Track")
                    }
                    .font(.system(size: 16, weight: .heavy, design: .rounded))
                    .foregroundStyle(SCTheme.Colors.accentPink)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(.white, in: Capsule())
                    .shadow(color: .black.opacity(0.2), radius: 10, y: 5)
                }
                .buttonStyle(.plain)
                .disabled(didLog)
            }
        } else {
            Button {
                advance()
            } label: {
                HStack(spacing: 8) {
                    Text("Next step")
                    Image(systemName: "arrow.right")
                }
                .font(.system(size: 16, weight: .heavy, design: .rounded))
                .foregroundStyle(SCTheme.Colors.accentPink)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(.white, in: Capsule())
                .shadow(color: .black.opacity(0.18), radius: 10, y: 5)
            }
            .buttonStyle(.plain)
        }
    }

    private var servingsStepper: some View {
        HStack(spacing: 12) {
            Text("How many servings did you eat?")
                .font(.system(size: 12, weight: .heavy, design: .rounded))
                .foregroundStyle(.white.opacity(0.85))
            Spacer()
            Button { servingsToLog = max(0.5, servingsToLog - 0.5) } label: {
                Image(systemName: "minus")
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(.white.opacity(0.18), in: Circle())
            }
            .buttonStyle(.plain)
            Text(String(format: "%.1g", servingsToLog))
                .font(.system(size: 16, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .monospacedDigit()
                .frame(minWidth: 32)
            Button { servingsToLog += 0.5 } label: {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(.white.opacity(0.18), in: Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.2)))
    }

    // MARK: Step transitions

    private func advance() {
        guard !isLast else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        invalidateTimer()
        withAnimation(.easeInOut(duration: 0.2)) {
            currentIndex += 1
        }
        resetTimerForCurrentStep()
    }

    private func regress() {
        guard currentIndex > 0 else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        invalidateTimer()
        withAnimation(.easeInOut(duration: 0.2)) {
            currentIndex -= 1
        }
        resetTimerForCurrentStep()
    }

    // MARK: Timer plumbing

    private func resetTimerForCurrentStep() {
        invalidateTimer()
        timerRemaining = step.timerSeconds ?? 0
        UIApplication.shared.isIdleTimerDisabled = (timerRemaining > 0)
    }

    private func startTimer() {
        guard timerRemaining > 0 else { return }
        timerRunning = true
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            Task { @MainActor in
                if timerRemaining > 0 {
                    timerRemaining -= 1
                    if timerRemaining == 0 {
                        timerRunning = false
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                    }
                }
            }
        }
    }

    private func pauseTimer() {
        timer?.invalidate()
        timer = nil
        timerRunning = false
    }

    private func invalidateTimer() {
        timer?.invalidate()
        timer = nil
        timerRunning = false
    }

    private func formatTime(_ seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        return String(format: "%02d:%02d", m, s)
    }
}
