import SwiftUI
import Observation

// Shared observable that drives tab bar opacity based on how far a tab's
// scroll view has traveled. Each scrollable tab pipes its content offset
// into `update(offset:)`; ContentView reads `opacity` and applies it to
// the floating bar + FAB. Full opacity at top, fades linearly to a
// minimum as the user scrolls past `fadeStart` → `fadeEnd`.

@MainActor
@Observable
final class TabBarFadeModel {
    static let shared = TabBarFadeModel()

    private let fadeStart: CGFloat = 60
    private let fadeEnd: CGFloat = 280
    private let minOpacity: Double = 0.05

    var opacity: Double = 1.0

    private init() {}

    func update(offset: CGFloat) {
        let clamped = max(fadeStart, min(fadeEnd, offset))
        let range = fadeEnd - fadeStart
        let progress = Double((clamped - fadeStart) / range) // 0 → 1
        let next = 1 - progress * (1 - minOpacity)
        // Snap back to full opacity when effectively at the top — avoids a
        // half-faded bar on small drags near the header.
        opacity = offset < fadeStart ? 1.0 : next
    }

    func reset() {
        opacity = 1.0
    }
}

extension View {
    // Attach to any ScrollView/List so its vertical content offset drives
    // the shared tab bar fade. Safe to use on all tabs — whichever tab is
    // active will own the last update.
    func tabBarFadesOnScroll() -> some View {
        self.onScrollGeometryChange(for: CGFloat.self) { geo in
            max(0, geo.contentOffset.y)
        } action: { _, newValue in
            TabBarFadeModel.shared.update(offset: newValue)
        }
    }
}
