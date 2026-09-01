import Foundation

@MainActor
final class SpotlightNavigator: ObservableObject {
    static let shared = SpotlightNavigator()
    private init() {}

    @Published private(set) var pendingToolID: String?

    func select(_ toolID: String) {
        pendingToolID = toolID
    }

    func consumePendingToolID() -> String? {
        defer { pendingToolID = nil }
        return pendingToolID
    }
}