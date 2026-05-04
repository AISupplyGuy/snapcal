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
        case .track:    return "circle.grid.cross.fill"
        case .insights: return "chart.line.uptrend.xyaxis"
        case .profile:  return "person.crop.circle.fill"
        }
    }
}

struct SCTabBar: View {
    @Binding var selection: SCTab
    var onCameraTap: () -> Void = {}

    var body: some View {
        HStack(spacing: 0) {
            tabCell(.pantry)
            tabCell(.cook)
            tabCell(.track)
            tabCell(.insights)
            tabCell(.profile)
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
            // Floating camera FAB lives only on Track — that's where the
            // capture/analyze flow is rooted. On other tabs it'd just be
            // a confusing teleport into Track mid-task.
            if selection == .track {
                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    onCameraTap()
                } label: {
                    ZStack {
                        Circle()
                            .fill(SCTheme.Gradients.cta)
                            .frame(width: 60, height: 60)
                            .shadow(color: SCTheme.Colors.accentPink.opacity(0.45), radius: 14, y: 6)
                        Image(systemName: "camera.fill")
                            .font(.system(size: 22, weight: .heavy))
                            .foregroundStyle(.white)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Snap a meal")
                .offset(y: -68)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.18), value: selection)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func tabCell(_ tab: SCTab) -> some View {
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
