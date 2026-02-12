import CoreLocation
import YallaKit

protocol RouteProviding {
    func fetchRoute(points: [CLLocationCoordinate2D]) async throws -> [CLLocationCoordinate2D]
}

struct YallaRouteProvider: RouteProviding {
    private let useCase: RoutingUseCaseProtocol

    init(useCase: RoutingUseCaseProtocol = RoutingUseCase()) {
        self.useCase = useCase
    }

    func fetchRoute(points: [CLLocationCoordinate2D]) async throws -> [CLLocationCoordinate2D] {
        let request = points.map { (lat: $0.latitude, lng: $0.longitude) }
        let response = try await useCase.execute(req: request)
        return (response?.routing ?? []).map {
            CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lng)
        }
    }
}
