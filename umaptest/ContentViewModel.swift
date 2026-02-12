import SwiftUI
import MapPack
import CoreLocation

final class ContentViewModel: ObservableObject {
    let mapModel: UniversalMapViewModel

    @Published private(set) var isTrackingMarker = false
    @Published private(set) var isRouteLoaded = false
    @Published private(set) var isRouteLoading = false

    private let config: TrackingConfig
    private let routeProvider: RouteProviding
    private let locationProvider: LocationProviding
    private let markerFactory: TrackedMarkerFactoryProviding
    private let locationValidator: LocationValidating
    private let trackingSession: RouteTrackingSessionManaging

    private var trackedMarker: UniversalMarker?
    private var hasFocusedInitialRoute = false

    init(
        mapModel: UniversalMapViewModel = UniversalMapViewModel(
            mapProvider: .mapLibre,
            config: MapConfig(config: MapLibreConfig())
        ),
        routeProvider: RouteProviding = YallaRouteProvider(),
        locationProvider: LocationProviding = CoreLocationProvider(),
        markerFactory: TrackedMarkerFactoryProviding? = nil,
        locationValidator: LocationValidating? = nil,
        trackingSession: RouteTrackingSessionManaging? = nil,
        config: TrackingConfig = .live
    ) {
        self.mapModel = mapModel
        self.config = config
        self.routeProvider = routeProvider
        self.locationProvider = locationProvider
        self.markerFactory = markerFactory ?? TrackedMarkerFactory(
            markerSize: config.markerSize,
            carIconName: config.carIconName
        )
        self.locationValidator = locationValidator ?? DefaultLocationValidationService(
            maxAge: config.locationMaxAge,
            maxHorizontalAccuracy: config.maximumHorizontalAccuracy
        )
        self.trackingSession = trackingSession ?? RouteTrackingSessionManager(
            config: config,
            headingService: HeadingComputationService()
        )

        bindLocationEvents()
    }

    func onAppear() {
        applySafeAreaInsets()
        mapModel.setInteractionDelegate(self)
        mapModel.pinModel.set(state: .waiting(time: "1", unit: "MIN"))
        schedulePinStateTransitionToSteady()
        locationProvider.requestWhenInUseAuthorization()

        Task {
            await prepareRoute(forceReload: false, autoStartTracking: false)
        }
    }

    func focusToCurrentLocation() {
        if let markerCoordinate = trackedMarker?.coordinate {
            mapModel.mapProviderInstance.updateCamera(to: .init(
                center: markerCoordinate,
                zoom: config.cameraZoom,
                bearing: trackingSession.displayHeading,
                pitch: config.cameraPitch,
                animate: true
            ))
            return
        }

        guard let coordinate = trackingSession.routeCoordinates.first ?? locationProvider.latestLocation?.coordinate else {
            return
        }

        mapModel.mapProviderInstance.updateCamera(to: .init(
            center: coordinate,
            zoom: config.cameraZoom,
            bearing: 0,
            pitch: config.cameraPitch,
            animate: true
        ))
    }

    func startTrackingMarker() {
        guard !isTrackingMarker else { return }

        guard isRouteLoaded else {
            Task {
                await prepareRoute(forceReload: false, autoStartTracking: true)
            }
            return
        }

        locationProvider.startUpdatingLocation(
            accuracy: kCLLocationAccuracyBestForNavigation,
            distanceFilter: config.trackingDistanceFilter
        )
        trackingSession.resetTrackingState()
        isTrackingMarker = true

        if trackedMarker == nil,
           let initialCoordinate = locationProvider.latestLocation?.coordinate
            ?? trackingSession.displayCoordinate
            ?? trackingSession.routeCoordinates.first {
            addTrackedMarker(at: initialCoordinate, heading: trackingSession.displayHeading)
        }

        if trackedMarker != nil {
            mapModel.trackMarker(config.markerId, zoom: config.cameraZoom)
        }

        log("Started tracking")
    }

    func stopTrackingMarker() {
        guard isTrackingMarker else { return }

        locationProvider.stopUpdatingLocation()
        isTrackingMarker = false
        trackingSession.resetTrackingState()
        mapModel.stopTracking()
        mapModel.removePolyline(withId: config.routeConnectorPolylineId)

        log("Stopped tracking")
    }

    func reloadRoute() {
        let shouldRestart = isTrackingMarker
        stopTrackingMarker()

        Task {
            await prepareRoute(forceReload: true, autoStartTracking: shouldRestart)
        }
    }

    @MainActor
    func startTrackingMarkerWithFocus() {
        startTrackingMarker()

        if let coordinate = trackedMarker?.coordinate ?? trackingSession.routeCoordinates.first {
            mapModel.focusMap(on: coordinate, zoom: config.cameraZoom, animated: true)
        }
    }

    func startSmoothTracking() {
        startTrackingMarker()
    }

    func updateTrackingAccuracy(_ accuracy: CLLocationAccuracy) {
        locationProvider.setDesiredAccuracy(accuracy)
    }

    func updateDistanceFilter(_ distance: CLLocationDistance) {
        locationProvider.setDistanceFilter(distance)
    }

    func updateServerHeading(_ heading: CLLocationDirection, at timestamp: Date = Date()) {
        trackingSession.updateServerHeading(heading, timestamp: timestamp)
    }

    func setRouteHeadingStrategy(_ strategy: RouteHeadingStrategy) {
        trackingSession.setRouteHeadingStrategy(strategy)
    }

    private func bindLocationEvents() {
        locationProvider.eventHandler = { [weak self] event in
            Task { @MainActor in
                self?.handleLocationEvent(event)
            }
        }

        locationProvider.setDesiredAccuracy(kCLLocationAccuracyBest)
        locationProvider.setDistanceFilter(config.defaultDistanceFilter)
    }

    private func handleLocationEvent(_ event: LocationProviderEvent) {
        switch event {
        case .didUpdateLocation(let location):
            guard locationValidator.isValid(location) else { return }
            handleRouteTrackingUpdate(for: location)

        case .didFail(let error):
            log("Location manager failed with error: \(error)")

        case .didChangeAuthorization(let status):
            handleAuthorizationChange(status)
        }
    }

    private func handleAuthorizationChange(_ status: CLAuthorizationStatus) {
        switch status {
        case .authorizedWhenInUse, .authorizedAlways:
            log("Location access authorized")

        case .denied, .restricted:
            log("Location access denied")
            if isTrackingMarker {
                stopTrackingMarker()
            }

        case .notDetermined:
            log("Location access not determined")

        @unknown default:
            break
        }
    }

    private func applySafeAreaInsets() {
        let insets = UIApplication.shared.safeAreaInsets
        mapModel.setEdgeInsets(.init(
            top: insets.top,
            left: 0,
            bottom: 0,
            right: 0,
            animated: true,
            onEnd: nil
        ))
    }

    private func schedulePinStateTransitionToSteady() {
        DispatchQueue.main.asyncAfter(deadline: .now() + config.pinLoadingDelay) { [weak self] in
            self?.mapModel.pinModel.set(state: .steady)
        }
    }

    private func routeFallback() -> [CLLocationCoordinate2D] {
        [config.pointA, config.pointB]
    }

    private func buildRouteRequestPoints() -> [CLLocationCoordinate2D] {
        [config.pointA, config.pointB]
    }

    private func fetchRouteCoordinates() async -> [CLLocationCoordinate2D] {
        do {
            let coordinates = try await routeProvider.fetchRoute(points: buildRouteRequestPoints())
            return coordinates.count > 1 ? coordinates : routeFallback()
        } catch {
            log("Failed to load route, using fallback line. error=\(error)")
            return routeFallback()
        }
    }

    @MainActor
    private func setupRouteOnMap(with coordinates: [CLLocationCoordinate2D]) {
        guard let setupState = trackingSession.configureRoute(
            coordinates: coordinates,
            currentLocation: locationProvider.latestLocation?.coordinate
        ) else {
            isRouteLoaded = false
            return
        }

        let routePolyline = UniversalMapPolyline(
            id: config.routePolylineId,
            coordinates: setupState.routeCoordinates,
            color: config.routeLineColor,
            width: config.routeLineWidth,
            geodesic: true,
            title: "remaining"
        )
        mapModel.updatePolyline(routePolyline, animated: false)
        mapModel.removePolyline(withId: config.routeConnectorPolylineId)

        removeTrackedMarkerIfNeeded()
        addTrackedMarker(
            at: setupState.initialMarkerCoordinate,
            heading: setupState.initialHeading
        )

        if !hasFocusedInitialRoute {
            mapModel.focusTo(coordinates: setupState.routeCoordinates, padding: 48, animated: true)
            hasFocusedInitialRoute = true
        }

        isRouteLoaded = true
    }

    private func handleRouteTrackingUpdate(for location: CLLocation) {
        guard isTrackingMarker else {
            return
        }

        guard let trackingUpdate = trackingSession.handleLocationUpdate(location) else {
            return
        }

        switch trackingUpdate {
        case .onTrack(let renderState):
            if trackedMarker == nil {
                addTrackedMarker(
                    at: renderState.markerCoordinate,
                    heading: renderState.markerHeading
                )
                mapModel.trackMarker(config.markerId, zoom: config.cameraZoom)
            }

            updateMarkerLocation(
                coordinate: renderState.markerCoordinate,
                heading: renderState.markerHeading
            )

            mapModel.updatePolyline(
                id: config.routePolylineId,
                coordinates: renderState.remainingPath,
                animated: false
            )

            updateConnectorPath(renderState.connectorCoordinates)

            if renderState.hasArrived {
                stopTrackingMarker()
            }

        case .outOfRoute:
            mapModel.removePolyline(withId: config.routeConnectorPolylineId)
            log("Location is currently out of route threshold")
        }
    }

    private func updateConnectorPath(_ coordinates: [CLLocationCoordinate2D]?) {
        guard let coordinates, !coordinates.isEmpty else {
            mapModel.removePolyline(withId: config.routeConnectorPolylineId)
            return
        }

        let connectorPolyline = UniversalMapPolyline(
            id: config.routeConnectorPolylineId,
            coordinates: coordinates,
            color: config.routeLineColor,
            width: config.routeLineWidth,
            geodesic: true,
            title: "connector"
        )
        mapModel.updatePolyline(connectorPolyline, animated: false)
    }

    private func addTrackedMarker(at coordinate: CLLocationCoordinate2D, heading: CLLocationDirection) {
        let marker = markerFactory.makeMarker(
            id: config.markerId,
            reuseIdentifier: config.markerReuseIdentifier,
            coordinate: coordinate
        )
        marker.set(heading: heading)
        trackedMarker = marker
        mapModel.addMarker(marker)
    }

    private func removeTrackedMarkerIfNeeded() {
        guard let markerId = trackedMarker?.id else {
            return
        }

        mapModel.removeMarker(withId: markerId)
        trackedMarker = nil
    }

    private func updateMarkerLocation(coordinate: CLLocationCoordinate2D, heading: CLLocationDirection) {
        guard isTrackingMarker,
              let marker = trackedMarker?.copy() as? UniversalMarker else {
            return
        }

        marker.updatePosition(coordinate: coordinate, heading: heading)
        mapModel.updateMarkerWithTracking(marker)
    }

    @MainActor
    private func prepareRoute(forceReload: Bool, autoStartTracking: Bool) async {
        if !forceReload && isRouteLoaded {
            if autoStartTracking {
                startTrackingMarker()
            }
            return
        }

        isRouteLoading = true
        let coordinates = await fetchRouteCoordinates()
        await MainActor.run {
            setupRouteOnMap(with: coordinates)
            isRouteLoading = false

            if autoStartTracking {
                startTrackingMarker()
            }
        }
    }

    private func log(_ message: String) {
        print("[ContentViewModel] \(message)")
    }
}

extension ContentViewModel: UniversalMapViewModelDelegate {
    func mapDidEndDragging(map: any MapProviderProtocol, at location: CLLocation) {
        debugPrint("EndDragging", location)
    }
}
