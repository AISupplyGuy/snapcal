import SwiftUI
import UIKit

// Five-tab bottom bar with a lifted Track FAB in the middle. Floats above
// a soft blur so content scrolls beneath it. The center button is a larger
// gradient circle with the camera icon; the other four are flat icon + label
// pairs. All selection state lives in the parent.

enum SCTab: Hashable, CaseIterable {
    case pantry, cook, track, insights, profile

    var title: String {
        switch self {
        case .pantry:   return "Pantry"
        case .cook:     return "Cook"
        case .track:    return "Track"
        case .insights: return "Insights"
        case .profile:  return "Profile"
        }
    }

    var systemImage: String {
        switch self {
        case .pantry:   return "cabinet.fill"
        case .cook:     return "fork.knife"
        case .track:    return "camera.fill"
        case .insights: return "chart.line.uptrend.xyaxis"
        case .profile:  return "person.crop.circle.fill"
        }
    }
}

struct SCTabBar: View {
    @Binding var selection: SCTab
    var onTrackTap: () -> Void = {}

    private let sideTabs: [SCTab] = [.pantry, .cook, .insights, .profile]

    var body: some View {
        HStack(spacing: 0) {
            sideTab(.pantry)
            sideTab(.cook)
            Color.clear.frame(width: 78)
            sideTab(.insights)
            sideTab(.profile)
        }
        .frame(height: 56)
        .padding(.horizontal, 6)
        .background(.ultraThinMaterial, in: Capsule(style: .continuous))
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(.primary.opacity(0.06), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.1), radius: 12, y: 4)
        .padding(.horizontal, 14)
        .overlay(alignment: .top) {
            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                if selection == .track {
                    onTrackTap()
                } else {
                    selection = .track
                }
            } label: {
                ZStack {
                    Circle()
                        .fill(SCTheme.Gradients.cta)
                        .frame(width: 64, height: 64)
                        .shadow(color: SCTheme.Colors.accentPink.opacity(0.35), radius: 10, y: 4)
                    Image(systemName: SCTab.track.systemImage)
                        .font(.system(size: 24, weight: .heavy))
                        .foregroundStyle(.white)
                }
                .overlay(
                    Circle()
                        .stroke(.white.opacity(0.3), lineWidth: 1.2)
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Snap a meal")
            .offset(y: -22)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func sideTab(_ tab: SCTab) -> some View {
        let isActive = selection == tab
        return Button {
            UISelectionFeedbackGenerator().selectionChanged()
            selection = tab
        } label: {
            VStack(spacing: 4) {
                Image(systemName: tab.systemImage)
                    .font(.system(size: 19, weight: isActive ? .heavy : .semibold))
                Text(tab.title)
                    .font(.system(size: 10.5, weight: .heavy, design: .rounded))
            }
            .foregroundStyle(isActive ? SCTheme.Colors.accentPink : Color.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
