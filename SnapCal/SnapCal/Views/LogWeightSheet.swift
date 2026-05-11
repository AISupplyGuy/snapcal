import SwiftUI

struct LogWeightSheet: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(ProfilePrefsKeys.weightUnit) private var unitRaw = WeightUnit.pounds.rawValue

    @State private var valueString: String = ""
    @State private var measuredAt: Date = .now
    @FocusState private var valueFocused: Bool

    private var unit: WeightUnit { WeightUnit(rawValue: unitRaw) ?? .pounds }
    private var parsedValue: Double? { Double(valueString.trimmingCharacters(in: .whitespaces)) }
    private var canSave: Bool { (parsedValue ?? 0) > 0 }

    var body: some View {
        ZStack(alignment: .top) {
            ambient
            VStack(spacing: 0) {
                topBar
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        header
                        weightCard
                        whenCard
                    }
                    .padding(.horizontal, 22)
                    .padding(.top, 4)
                    .padding(.bottom, 140)
                }
                .scrollIndicators(.hidden)
            }
            .safeAreaInset(edge: .bottom) { saveBar }
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                valueFocused = true
            }
        }
    }

    // MARK: Ambient

    private var ambient: some View {
        ZStack {
            RadialGradient(
                colors: [SCTheme.Colors.accentPink.opacity(0.22), .clear],
                center: .topTrailing,
                startRadius: 10,
                endRadius: 380
            )
            RadialGradient(
                colors: [SCTheme.Colors.accentOrange.opacity(0.12), .clear],
                center: .bottomLeading,
                startRadius: 10,
                endRadius: 360
            )
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    // MARK: Top bar

    private var topBar: some View {
        HStack {
            Spacer()
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                dismiss()
            } label: {
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

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            SCKickerPill(text: "Log weight", tint: SCTheme.Colors.accentPink)
            Text("How'd today land?")
                .font(SCTheme.Type_.title(28))
                .foregroundStyle(.primary)
            Text("Quick check-in. We chart it on Insights and sync it to Apple Health.")
                .font(SCTheme.Type_.body())
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 4)
    }

    // MARK: Weight card

    private var weightCard: some View {
        glassCard {
            VStack(alignment: .leading, spacing: 16) {
                fieldLabel("Weight")
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    TextField("0.0", text: $valueString)
                        .keyboardType(.decimalPad)
                        .focused($valueFocused)
                        .font(.system(size: 56, weight: .heavy, design: .rounded))
                        .foregroundStyle(.primary)
                        .tracking(-1.5)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(unit.label)
                        .font(.system(size: 18, weight: .heavy, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                unitToggle
            }
        }
    }

    private var unitToggle: some View {
        HStack(spacing: 4) {
            ForEach(WeightUnit.allCases) { u in
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    unitRaw = u.rawValue
                } label: {
                    Text(u.label)
                        .font(.system(size: 13, weight: .heavy, design: .rounded))
                        .foregroundStyle(unitRaw == u.rawValue ? .white : .secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background {
                            if unitRaw == u.rawValue {
                                Capsule().fill(SCTheme.Gradients.cta)
                                    .shadow(color: SCTheme.Colors.accentPink.opacity(0.35), radius: 6, y: 3)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(Capsule().fill(.white.opacity(0.05)))
        .overlay(Capsule().strokeBorder(.white.opacity(0.06)))
    }

    // MARK: When card

    private var whenCard: some View {
        glassCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    fieldLabel("When")
                    Spacer()
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        measuredAt = .now
                    } label: {
                        Text("Now")
                            .font(.system(size: 11, weight: .heavy, design: .rounded))
                            .tracking(0.6)
                            .foregroundStyle(SCTheme.Colors.accentPink)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Capsule().fill(SCTheme.Colors.accentPink.opacity(0.14)))
                    }
                    .buttonStyle(.plain)
                }
                HStack(spacing: 0) {
                    Text(measuredAt, format: .dateTime.weekday(.wide).month(.abbreviated).day())
                        .font(.system(size: 17, weight: .heavy, design: .rounded))
                        .foregroundStyle(.primary)
                    Spacer()
                    Text(measuredAt, format: .dateTime.hour().minute())
                        .font(.system(size: 17, weight: .heavy, design: .rounded))
                        .foregroundStyle(.primary)
                }
                DatePicker(
                    "",
                    selection: $measuredAt,
                    in: ...Date.now,
                    displayedComponents: [.date, .hourAndMinute]
                )
                .labelsHidden()
                .datePickerStyle(.compact)
                .tint(SCTheme.Colors.accentPink)
                .opacity(0.001)
                .frame(height: 1)
                .accessibilityHidden(true)
            }
        }
    }

    // MARK: Save bar

    private var saveBar: some View {
        VStack(spacing: 0) {
            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                save()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                    Text("Save weight")
                }
                .font(.system(size: 16, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(SCTheme.Gradients.cta, in: Capsule())
                .shadow(color: SCTheme.Colors.accentPink.opacity(canSave ? 0.32 : 0), radius: 12, y: 6)
                .opacity(canSave ? 1 : 0.4)
            }
            .buttonStyle(.plain)
            .disabled(!canSave)
            .padding(.horizontal, 22)
            .padding(.top, 12)
            .padding(.bottom, 18)
        }
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) {
            Rectangle().fill(.white.opacity(0.06)).frame(height: 0.5)
        }
    }

    // MARK: Helpers

    private func glassCard<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            content()
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: SCTheme.Radius.lg, style: .continuous)
                .fill(.ultraThinMaterial)
        }
        .overlay {
            RoundedRectangle(cornerRadius: SCTheme.Radius.lg, style: .continuous)
                .strokeBorder(.white.opacity(0.07))
        }
        .shadow(color: .black.opacity(0.22), radius: 18, y: 10)
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .heavy, design: .rounded))
            .tracking(1.2)
            .foregroundStyle(.secondary)
    }

    private func save() {
        guard let value = parsedValue, value > 0 else { return }
        let kg: Double = unit == .kilograms ? value : value / 2.20462
        WeightLog.shared.log(WeightEntry(measuredAt: measuredAt, kilograms: kg))
        dismiss()
    }
}
