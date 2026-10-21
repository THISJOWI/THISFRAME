#if os(iOS)
import SwiftUI

/// Floating glass pill tab bar (Netflix/Apple TV style) for iOS 17–25.
///
/// iOS 26+ keeps the native TabView — Liquid Glass already renders the
/// floating pill from the reference screenshots (and minimizes on scroll),
/// so a custom bar there would only regress the system behavior.
struct FloatingTabBar: View {
    @Binding var selection: MareaTab

    /// The capsule that moves from one tab to the next.
    @Namespace private var tabNamespace

    /// The system may ask for no animation at all.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Favorites lives inside Home rows; the pill mirrors the native tabs.
    private var tabs: [MareaTab] { [.home, .search, .profile] }

    var body: some View {
        HStack(spacing: MareaTheme.Spacing.lg) {
            ForEach(tabs, id: \.self) { tab in
                Button {
                    selection = tab
                } label: {
                    ZStack {
                        // The selection blob slides between tabs instead of
                        // the icon simply changing colour. With "reduce
                        // motion" the blob simply appears in place.
                        if selection == tab {
                            Capsule()
                                .fill(MareaTheme.Colors.glass)
                                .matchedGeometryEffect(id: "tab.selection", in: tabNamespace)
                        }
                        VStack(spacing: 2) {
                            Image(systemName: tab.icon)
                                .font(.system(size: 20, weight: .medium))
                            Text(tab.label)
                                .font(.caption2)
                        }
                        .foregroundStyle(
                            selection == tab ? MareaTheme.Colors.accentText : Color.secondary
                        )
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, MareaTheme.Spacing.lg)
        .padding(.vertical, MareaTheme.Spacing.sm)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(
            Capsule()
                .strokeBorder(MareaTheme.Colors.borderGlow, lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.4), radius: 12, y: 4)
        .padding(.horizontal, MareaTheme.Spacing.xl)
        .animation(
            MareaMotion.resolve(MareaMotion.standard, reduceMotion: reduceMotion),
            value: selection
        )
    }
}
#endif
