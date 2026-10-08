/// The screens the example pretends to have, sent as the `screen` property of `screen_view`.
enum DemoScreen: String, CaseIterable, Identifiable {
    case home
    case search
    case settings
    case paywall

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: "Home"
        case .search: "Search"
        case .settings: "Settings"
        case .paywall: "Paywall"
        }
    }
}
