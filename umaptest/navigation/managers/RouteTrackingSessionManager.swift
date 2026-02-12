import CoreLocation
import MapPack

struct RouteSetupState {
    let routeCoordinates: [CLLocationCoordinate2D]
    let initialMarkerCoordinate: CLLocationCoordinate2D
    let initialHeading: CLLocationDirection
}

struct RouteTrackingRenderState {
    let markerCoordinate: CLLocationCoordinate2D
    let markerHeading: CLLocationDirection
    let remainingPath: [CLLocationCoordinate2D]
    let connectorCoordinates: [CLLocationCoordinate2D]?
    let hasArrived: Bool
}

enum RouteTrackingUpdate {
    case onTrack(RouteTrackingRenderState)
    case outOfRoute
}

protocol RouteTrackingSessionManaging: AnyObject {
    var routeCoordinates: [CLLocationCoordinate2D] { get }
    var displayHeading: CLLocationDirection { get }
    var displayCoordinate: CLLocationCoordinate2D? { get }

    func configureRoute(
        coordinates: [CLLocationCoordinate2D],
        currentLocation: CLLocationCoordinate2D?
    ) -> RouteSetupState?

    func handleLocationUpdate(_ location: CLLocation) -> RouteTrackingUpdate?
    func resetTrackingState()
    func clearRouteState()
    func updateServerHeading(_ heading: CLLocationDirection, timestamp: Date)
    func setRouteHeadingStrategy(_ strategy: RouteHeadingStrategy)
}

final class RouteTrackingSessionManager: RouteTrackingSessionManaging {
    var routeCoordinates: [CLLocationCoordinate2D] {
        storedRouteCoordinates
    }

    var displayHeading: CLLocationDirection {
        storedDisplayHeading
    }

    var displayCoordinate: CLLocationCoordinate2D? {
        storedDisplayCoordinate
    }

    private let config: TrackingConfig
    private let headingService: HeadingComputing

    private var routeTracker: RouteTrackingManager?
    private var storedRouteCoordinates: [CLLocationCoordinate2D] = []
    private var storedDisplayHeading: CLLocationDirection = 0
    private var storedDisplayCoordinate: CLLocationCoordinate2D?
    private var routeHeadingStrategy: RouteHeadingStrategy = .lookAhead
    private var latestServerHeading: (value: CLLocationDirection, timestamp: Date)?
    private var lastHeadingUpdateAt: Date?

    init(
        config: TrackingConfig,
        headingService: HeadingComputing
    ) {
        self.config = config
        self.headingService = headingService
    }

    func configureRoute(
        coordinates: [CLLocationCoordinate2D],
        currentLocation: CLLocationCoordinate2D?
    ) -> RouteSetupState? {
        storedRouteCoordinates = coordinates
        routeTracker = RouteTrackingManager(
            routeCoordinates: coordinates,
            threshold: config.routeSnapThreshold
        )

        guard let start = coordinates.first else {
            clearRouteState()
            return nil
        }

        let initialCoordinate = currentLocation ?? start
        let initialHeading: CLLocationDirection
        if coordinates.count > 1 {
            initialHeading = headingService.bearing(from: coordinates[0], to: coordinates[1])
        } else {
            initialHeading = 0
        }

        storedDisplayCoordinate = initialCoordinate
        storedDisplayHeading = initialHeading
        lastHeadingUpdateAt = nil

        return RouteSetupState(
            routeCoordinates: coordinates,
            initialMarkerCoordinate: initialCoordinate,
            initialHeading: initialHeading
        )
    }

    func handleLocationUpdate(_ location: CLLocation) -> RouteTrackingUpdate? {
        guard let routeTracker else {
            return nil
        }

        switch routeTracker.updateDriverLocation(location.coordinate) {
        case .onTrack(let snappedLocation, let remainingPath):
            let nextHeading = headingService.computeTargetHeading(input: .init(
                snappedCoordinate: snappedLocation,
                remainingPath: remainingPath,
                location: location,
                lastDisplayCoordinate: storedDisplayCoordinate,
                currentDisplayHeading: storedDisplayHeading,
                routeHeadingStrategy: routeHeadingStrategy,
                lookAheadDistance: config.routeHeadingLookAheadDistance,
                minReliableCourseSpeed: config.minReliableCourseSpeed,
                serverHeading: latestServerHeading,
                serverHeadingMaxAge: config.serverHeadingMaxAge
            ))

            let deltaTime = headingDeltaTime(at: location.timestamp)
            let smoothedHeading = headingService.smoothHeading(
                from: storedDisplayHeading,
                to: nextHeading,
                factor: config.headingSmoothingFactor,
                deltaTime: deltaTime,
                maxTurnRatePerSecond: config.maxHeadingTurnRatePerSecond
            )

            storedDisplayCoordinate = snappedLocation
            storedDisplayHeading = smoothedHeading

            let connectorCoordinates = connectorPath(
                markerCoordinate: snappedLocation,
                remainingPath: remainingPath
            )

            let hasArrived: Bool
            if let destination = storedRouteCoordinates.last {
                hasArrived = headingService.distance(from: snappedLocation, to: destination) <= config.routeArrivalThreshold
            } else {
                hasArrived = false
            }

            return .onTrack(.init(
                markerCoordinate: snappedLocation,
                markerHeading: smoothedHeading,
                remainingPath: remainingPath,
                connectorCoordinates: connectorCoordinates,
                hasArrived: hasArrived
            ))

        case .outOfRoute:
            return .outOfRoute
        }
    }

    func resetTrackingState() {
        lastHeadingUpdateAt = nil
    }

    func clearRouteState() {
        routeTracker = nil
        storedRouteCoordinates = []
        storedDisplayCoordinate = nil
        storedDisplayHeading = 0
        lastHeadingUpdateAt = nil
    }

    func updateServerHeading(_ heading: CLLocationDirection, timestamp: Date) {
        latestServerHeading = (heading.normalizedHeading, timestamp)
    }

    func setRouteHeadingStrategy(_ strategy: RouteHeadingStrategy) {
        routeHeadingStrategy = strategy
    }

    private func headingDeltaTime(at eventTime: Date) -> TimeInterval {
        defer { lastHeadingUpdateAt = eventTime }

        guard let lastHeadingUpdateAt else {
            return 1.0 / 30.0
        }

        return max(1.0 / 60.0, min(1.0, eventTime.timeIntervalSince(lastHeadingUpdateAt)))
    }

    private func connectorPath(
        markerCoordinate: CLLocationCoordinate2D,
        remainingPath: [CLLocationCoordinate2D]
    ) -> [CLLocationCoordinate2D]? {
        guard let routeStartCoordinate = remainingPath.first else {
            return nil
        }

        let connectorDistance = headingService.distance(from: markerCoordinate, to: routeStartCoordinate)
//        guard connectorDistance > config.connectorHideThreshold else {
//            return nil
//        }

        return [markerCoordinate, routeStartCoordinate]
    }
}

private extension Double {
    var normalizedHeading: Double {
        var value = self.truncatingRemainder(dividingBy: 360)
        if value < 0 { value += 360 }
        return value
    }
}
