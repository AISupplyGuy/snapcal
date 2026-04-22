import Foundation
import Observation

// Lightweight identity for the Profile tab. No real auth yet — just what
// the user wants rendered at the top of their screen. Persists to
// UserDefaults. When real auth lands, back this with the auth session.
struct UserProfile: Codable, Sendable, Equatable {
    var name: String
    var email: String

    var initials: String {
        let parts = name
            .split(separator: " ", omittingEmptySubsequences: true)
            .prefix(2)
        let chars = parts.compactMap { $0.first }
        let joined = String(chars).uppercased()
        return joined.isEmpty ? "YOU" : joined
    }

    static let `default` = UserProfile(name: "You", email: "")
}

@MainActor
@Observable
final class UserProfileStore {
    static let shared = UserProfileStore()

    private let key = "SnapCal.UserProfile.v1"

    private(set) var profile: UserProfile

    private init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode(UserProfile.self, from: data) {
            self.profile = decoded
        } else {
            self.profile = .default
        }
    }

    func update(_ next: UserProfile) {
        profile = next
        if let data = try? JSONEncoder().encode(next) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}

// Toggles and simple preferences exposed on the Profile tab. Keeping these
// here as @AppStorage-compatible keys so Views can bind directly.
enum ProfilePrefsKeys {
    static let mealReminders = "SnapCal.prefs.mealReminders.v1"
    static let appearance = "SnapCal.prefs.appearance.v1" // "system" | "light" | "dark"
}

enum AppearancePreference: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var label: String {
        switch self {
        case .system: return "System"
        case .light:  return "Light"
        case .dark:   return "Dark"
        }
    }
}
