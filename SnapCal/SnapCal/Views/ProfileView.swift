import SwiftUI

// Profile tab — mirrors the "SnapCal Profile Tab" design spec.
// Hero (avatar + name + email + plan pill) → 3 stats → Goals/Health
// settings group → App settings group. "Daily targets" pushes to the
// sliders that drive the rings on Track.

struct ProfileView: View {
    @State private var profile = UserProfileStore.shared.profile
    @State private var goals = GoalsStore.shared.goals
    @State private var editing = false
    @State private var showingAppearance = false
    @State private var showingPrivacy = false
    @State private var showingHealth = false
    @State private var mealReminders = UserDefaults.standard.object(forKey: ProfilePrefsKeys.mealReminders) as? Bool ?? true
    @State private var mealCount = MealDiary.shared.allTimeMealCount
    @State private var streak = MealDiary.shared.dayStreak

    private let profileStore = UserProfileStore.shared
    private let goalsStore = GoalsStore.shared
    private let diary = MealDiary.shared

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    hero
                    statsRow

                    sectionTitle("Goals & health")
                    goalsGroup

                    sectionTitle("App")
                    appGroup
                }
                .padding(.horizontal, 22)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
            .scrollIndicators(.hidden)
            .tabBarFadesOnScroll()
            .navigationTitle("")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        editing = true
                    } label: {
                        Image(systemName: "square.and.pencil")
                            .foregroundStyle(SCTheme.Colors.accentPink)
                    }
                    .accessibilityLabel("Edit profile")
                }
            }
            .sheet(isPresented: $editing) {
                EditProfileSheet(profile: profile) { next in
                    profileStore.update(next)
                    profile = next
                }
            }
            .sheet(isPresented: $showingAppearance) {
                AppearanceSheet()
                    .presentationDetents([.medium])
            }
            .sheet(isPresented: $showingPrivacy) {
                PrivacySheet()
                    .presentationDetents([.medium])
            }
            .sheet(isPresented: $showingHealth) {
                ComingSoonSheet(
                    title: "Apple Health",
                    copy: "SnapCal will sync meals, macros, and weight to Apple Health so your rings, moves, and calories land in one place."
                )
                .presentationDetents([.medium])
            }
            .onAppear {
                // Stats can change after saving/deleting meals — refresh each
                // time the tab comes into view.
                mealCount = diary.allTimeMealCount
                streak = diary.dayStreak
                goals = goalsStore.goals
            }
        }
    }

    // MARK: - Header (eyebrow + title)

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("SETTINGS")
                .font(.system(size: 11, weight: .heavy, design: .rounded))
                .tracking(1.1)
                .foregroundStyle(.secondary)
            Text("Profile")
                .font(.system(size: 26, weight: .heavy, design: .rounded))
                .tracking(-0.5)
                .foregroundStyle(.primary)
        }
    }

    // MARK: - Hero card

    private var hero: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(LinearGradient(
                        colors: [Color(hex: 0xFFCC00), SCTheme.Colors.accentOrange],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                    .frame(width: 72, height: 72)
                    .shadow(color: SCTheme.Colors.accentOrange.opacity(0.35), radius: 12, y: 4)
                Text(profile.initials)
                    .font(.system(size: 24, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
            }

            Text(profile.name.isEmpty ? "You" : profile.name)
                .font(.system(size: 20, weight: .heavy, design: .rounded))
                .tracking(-0.4)
                .foregroundStyle(.primary)

            if !profile.email.isEmpty {
                Text(profile.email)
                    .font(SCTheme.Type_.caption())
                    .foregroundStyle(.secondary)
            } else {
                Text("Tap edit to add your email")
                    .font(SCTheme.Type_.caption())
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.system(size: 10, weight: .heavy))
                Text("FREE PLAN")
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .tracking(1.2)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .foregroundStyle(.white)
            .background(
                LinearGradient(
                    colors: [SCTheme.Colors.accentPink, SCTheme.Colors.accentOrange],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: Capsule()
            )
            .shadow(color: SCTheme.Colors.accentPink.opacity(0.28), radius: 4, y: 2)
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .scCardStyle()
    }

    // MARK: - Stats row

    private var statsRow: some View {
        HStack(spacing: 8) {
            StatCell(value: "\(streak)", label: "Day streak", tint: SCTheme.Colors.accentOrange)
            StatCell(value: "\(mealCount)", label: "Meals logged", tint: nil)
            StatCell(value: "0", label: "Recipes", tint: nil)
        }
    }

    // MARK: - Settings groups

    private func sectionTitle(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .heavy, design: .rounded))
            .tracking(1.1)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 4)
            .padding(.top, 4)
    }

    private var goalsGroup: some View {
        SettingsGroup {
            NavigationLink {
                DailyTargetsView()
                    .onDisappear { goals = goalsStore.goals }
            } label: {
                SettingsRow(
                    icon: .init(system: "scope", gradient: [SCTheme.Colors.accentOrange, SCTheme.Colors.accentPink]),
                    label: "Daily targets",
                    trailing: .value("\(Int(goals.calories).formattedWithCommas()) kcal")
                )
            }
            .buttonStyle(.plain)

            Button {
                showingHealth = true
            } label: {
                SettingsRow(
                    icon: .init(system: "heart.fill", gradient: [SCTheme.Colors.accentPink, Color(hex: 0xBF5AF2)]),
                    label: "Apple Health",
                    trailing: .value("Not connected")
                )
            }
            .buttonStyle(.plain)

            SettingsRow(
                icon: .init(system: "bell.fill", gradient: [Color(hex: 0xFF9F0A), SCTheme.Colors.accentOrange]),
                label: "Meal reminders",
                trailing: .toggle(Binding(
                    get: { mealReminders },
                    set: { v in
                        mealReminders = v
                        UserDefaults.standard.set(v, forKey: ProfilePrefsKeys.mealReminders)
                    }
                ), tint: SCTheme.Colors.carbGreen)
            )
        }
    }

    private var appGroup: some View {
        SettingsGroup {
            Button {
                showingAppearance = true
            } label: {
                SettingsRow(
                    icon: .init(system: "moon.fill", gradient: [Color(hex: 0x3A3A3C), Color(hex: 0x1C1C1E)]),
                    label: "Appearance",
                    trailing: .value(appearanceLabel)
                )
            }
            .buttonStyle(.plain)

            Button {
                showingPrivacy = true
            } label: {
                SettingsRow(
                    icon: .init(system: "lock.fill", gradient: [Color(hex: 0x8E8E93), Color(hex: 0x48484A)]),
                    label: "Privacy",
                    trailing: .value("On-device")
                )
            }
            .buttonStyle(.plain)

            Link(destination: URL(string: "mailto:hello@snapcal.app?subject=SnapCal%20feedback")!) {
                SettingsRow(
                    icon: .init(system: "questionmark.circle.fill", gradient: [SCTheme.Colors.proteinBlue, Color(hex: 0x5AC8FA)]),
                    label: "Help & feedback",
                    trailing: .chevronOnly
                )
            }
            .buttonStyle(.plain)
        }
    }

    private var appearanceLabel: String {
        let raw = UserDefaults.standard.string(forKey: ProfilePrefsKeys.appearance) ?? "system"
        return AppearancePreference(rawValue: raw)?.label ?? "System"
    }
}

// MARK: - Stat cell

private struct StatCell: View {
    let value: String
    let label: String
    let tint: Color?

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 22, weight: .heavy, design: .rounded))
                .tracking(-0.4)
                .foregroundStyle(tint ?? .primary)
            Text(label.uppercased())
                .font(.system(size: 10, weight: .heavy, design: .rounded))
                .tracking(1.0)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .padding(.horizontal, 10)
        .scCardStyle()
    }
}

// MARK: - Settings group shell

private struct SettingsGroup<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        VStack(spacing: 0) {
            content
        }
        .scCardStyle()
    }
}

// MARK: - Settings row

private struct SettingsIconSpec {
    let system: String
    let gradient: [Color]
}

private enum SettingsRowTrailing {
    case value(String)
    case toggle(Binding<Bool>, tint: Color)
    case chevronOnly
}

private struct SettingsRow: View {
    let icon: SettingsIconSpec
    let label: String
    let trailing: SettingsRowTrailing

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(LinearGradient(
                        colors: icon.gradient,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                Image(systemName: icon.system)
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(.white)
            }
            .frame(width: 30, height: 30)

            Text(label)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)

            Spacer(minLength: 8)

            switch trailing {
            case .value(let text):
                HStack(spacing: 6) {
                    Text(text)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundStyle(Color.secondary.opacity(0.55))
                }
            case .toggle(let binding, let tint):
                Toggle("", isOn: binding)
                    .labelsHidden()
                    .tint(tint)
            case .chevronOnly:
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(Color.secondary.opacity(0.55))
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .contentShape(Rectangle())
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.primary.opacity(0.06))
                .frame(height: 0.5)
                .padding(.leading, 56)
                .opacity(isLastRow ? 0 : 1)
        }
    }

    // No easy way to know "last row" without parent state; keep the hairline
    // always drawn and rely on the group's last overlay being clipped by
    // .scCardStyle's rounded clip. Visually this matches the design.
    private var isLastRow: Bool { false }
}

// MARK: - Edit sheet

private struct EditProfileSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State var profile: UserProfile
    let onSave: (UserProfile) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("Your name", text: $profile.name)
                        .textInputAutocapitalization(.words)
                }
                Section("Email") {
                    TextField("you@example.com", text: $profile.email)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
            }
            .navigationTitle("Edit profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        onSave(profile)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
}

// MARK: - Appearance sheet

private struct AppearanceSheet: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(ProfilePrefsKeys.appearance) private var appearance = "system"

    var body: some View {
        NavigationStack {
            List {
                ForEach(AppearancePreference.allCases) { option in
                    Button {
                        appearance = option.rawValue
                        dismiss()
                    } label: {
                        HStack {
                            Text(option.label)
                                .foregroundStyle(.primary)
                            Spacer()
                            if appearance == option.rawValue {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(SCTheme.Colors.accentPink)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Appearance")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Privacy sheet

private struct PrivacySheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Your meal log stays on your device.")
                        .font(.system(size: 22, weight: .heavy, design: .rounded))
                        .tracking(-0.3)
                    Text("SnapCal saves meal entries to your device's app storage. Photos you snap are analyzed to estimate nutrition, then the photo is used only to render the meal card — we don't upload it to a server of ours.")
                        .font(SCTheme.Type_.body())
                        .foregroundStyle(.secondary)
                    Text("Nutrition lookups use public databases (USDA) and the Gemini API for photo understanding. No account required.")
                        .font(SCTheme.Type_.body())
                        .foregroundStyle(.secondary)
                }
                .padding(20)
            }
            .navigationTitle("Privacy")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Coming soon sheet

private struct ComingSoonSheet: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    let copy: String

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("Coming soon")
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .tracking(1.1)
                    .foregroundStyle(SCTheme.Colors.accentPink)
                Text(title)
                    .font(.system(size: 24, weight: .heavy, design: .rounded))
                    .tracking(-0.3)
                Text(copy)
                    .font(SCTheme.Type_.body())
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(24)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Helpers

private extension Int {
    func formattedWithCommas() -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        return f.string(from: NSNumber(value: self)) ?? "\(self)"
    }
}
