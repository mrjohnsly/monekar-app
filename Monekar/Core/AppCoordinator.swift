import Observation

enum AppRoute: Hashable {
    case connection
}

@MainActor
@Observable
final class AppCoordinator {
    var path: [AppRoute] = []
    let home: HomeViewModel

    init(services: AppServices) {
        home = HomeViewModel(services: services)
    }

    func showConnection() {
        guard path.last != .connection else { return }
        path.append(.connection)
    }

    func pop() {
        guard !path.isEmpty else { return }
        path.removeLast()
    }

    func reset() {
        path.removeAll()
    }
}
