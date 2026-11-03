import SwiftUI

enum MareaTab: Int, CaseIterable, Hashable {
    case home
    case search
    case listas
    case favorites
    case profile

    var icon: String {
        switch self {
        case .home: "house.fill"
        case .search: "magnifyingglass"
        case .listas: "list.bullet"
        case .favorites: "heart.fill"
        case .profile: "gearshape.fill"
        }
    }

    var label: String {
        switch self {
        case .home: "Inicio"
        case .search: "Buscar"
        case .listas: "Listas"
        case .favorites: "Favoritos"
        case .profile: "Ajustes"
        }
    }

    var activeColor: Color {
        MareaTheme.Colors.crimsonFrame
    }
}

// Custom MareaTabBar replaced by native SwiftUI TabView (iOS 26+).
// Native TabView automatically provides: floating glass material, selection blob,
// minimize on scroll, search tab role, and all Liquid Glass animations.
// See ThisFrameRootView.swift for the TabView implementation.
