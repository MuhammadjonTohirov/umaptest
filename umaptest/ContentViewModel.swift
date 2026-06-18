import SwiftUI
import MapPack
import CoreLocation
import os

@MainActor
final class ContentViewModel: ObservableObject {
    private static let logger = Logger(subsystem: "umaptest", category: "ContentViewModel")

    let mapModel: UniversalMapViewModel

    @Published private(set) var isTrackingMarker = false
    @Published private(set) var isRouteLoaded = false
    @Published private(set) var isRouteLoading = false
    @Published private(set) var isCameraFollowEnabled = true
    @Published private(set) var isNavigationModeEnabled = false
    @Published private(set) var hasRandomMarkers = false

    private let config: TrackingConfig
    private let routeProvider: RouteProviding
    private let locationProvider: LocationProviding
    private let markerFactory: TrackedMarkerFactoryProviding
    private let locationValidator: LocationValidating
    private let trackingSession: NavigationRouteTrackingSessionManaging
    private let routeProgressAnimator: NavigationRouteProgressAnimating

    private var trackedMarker: UniversalMarker?
    private var hasFocusedInitialRoute = false
    private var routeGeometry: NavigationRouteProgressGeometry?
    private var currentRouteProgress: CLLocationDistance = 0
    private var isReroutingOffRoute = false
    private var lastOffRouteRerouteAt: Date?
    private var randomMarkerIds: [String] = []

    init(
        mapModel: UniversalMapViewModel? = nil,
        routeProvider: RouteProviding = YallaRouteProvider(),
        locationProvider: LocationProviding = CoreLocationProvider(),
        markerFactory: TrackedMarkerFactoryProviding? = nil,
        locationValidator: LocationValidating? = nil,
        trackingSession: NavigationRouteTrackingSessionManaging? = nil,
        routeProgressAnimator: NavigationRouteProgressAnimating? = nil,
        config: TrackingConfig = .live
    ) {
        let headingService = NavigationHeadingComputationService()
        self.mapModel = mapModel ?? UniversalMapViewModel(
            mapProvider: .mapLibre,
            config: MapConfig(config: MapLibreConfig())
        )
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
        self.trackingSession = trackingSession ?? NavigationRouteTrackingSessionManager(
            config: config.navigationTrackingConfig,
            headingService: headingService
        )
        self.routeProgressAnimator = routeProgressAnimator ?? NavigationRouteProgressAnimationService()

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
            mapModel.updateCamera(to: .init(
                center: markerCoordinate,
                zoom: config.cameraZoom,
                bearing: isNavigationModeEnabled ? trackingSession.displayHeading : 0,
                pitch: config.cameraPitch,
                animate: true
            ))
            return
        }

        guard let coordinate = trackingSession.routeCoordinates.first ?? locationProvider.latestLocation?.coordinate else {
            return
        }

        mapModel.updateCamera(to: .init(
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

        applyCameraFollowModeIfNeeded()

        log("Started tracking")
    }

    func stopTrackingMarker() {
        guard isTrackingMarker else { return }

        locationProvider.stopUpdatingLocation()
        isTrackingMarker = false
        trackingSession.resetTrackingState()
        routeProgressAnimator.cancel()
        isReroutingOffRoute = false
        mapModel.stopTracking()
        mapModel.removePolyline(withId: config.routeConnectorPolylineId)

        log("Stopped tracking")
    }

    func toggleCameraFollow() {
        setCameraFollowEnabled(!isCameraFollowEnabled)
    }

    func toggleNavigationMode() {
        setNavigationModeEnabled(!isNavigationModeEnabled)
    }

    func setNavigationModeEnabled(_ enabled: Bool) {
        guard isNavigationModeEnabled != enabled else { return }
        isNavigationModeEnabled = enabled

        guard isTrackingMarker else { return }
        applyCameraFollowModeIfNeeded()
    }

    // MARK: - Random markers (map-rotation test harness)

    /// Drops/removes a cluster of car markers with random headings near the route
    /// area. Each marker compensates for the map bearing, so rotating the map should
    /// rotate every marker to keep its heading aligned to the map, not the screen.
    func toggleRandomMarkers() {
        hasRandomMarkers ? clearRandomMarkers() : addRandomRotatingMarkers()
    }

    private func addRandomRotatingMarkers(count: Int = 10) {
        let center = randomMarkersCenter

        for index in 0..<count {
            let id = "random_\(index)"
            let coordinate = CLLocationCoordinate2D(
                latitude: center.latitude + Double.random(in: -0.008...0.008),
                longitude: center.longitude + Double.random(in: -0.008...0.008)
            )
            let marker = markerFactory.makeMarker(
                id: id,
                reuseIdentifier: id,
                coordinate: coordinate
            )
            marker.set(heading: Double.random(in: 0..<360))
            mapModel.addMarker(marker)
            randomMarkerIds.append(id)
        }

        mapModel.updateCamera(to: .init(center: center, zoom: 13, bearing: 0, pitch: 0, animate: true))
        hasRandomMarkers = true
    }

    private func clearRandomMarkers() {
        randomMarkerIds.forEach { mapModel.removeMarker(withId: $0) }
        randomMarkerIds.removeAll()
        hasRandomMarkers = false
    }

    private var randomMarkersCenter: CLLocationCoordinate2D {
        trackedMarker?.coordinate
            ?? trackingSession.routeCoordinates.first
            ?? CLLocationCoordinate2D(latitude: 40.38942, longitude: 71.78280)
    }

    func setCameraFollowEnabled(_ enabled: Bool) {
        guard isCameraFollowEnabled != enabled else { return }
        isCameraFollowEnabled = enabled

        guard isTrackingMarker else { return }
        applyCameraFollowModeIfNeeded()
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

    func setRouteHeadingStrategy(_ strategy: NavigationRouteHeadingStrategy) {
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

    @MainActor
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

        routeProgressAnimator.cancel()
        routeGeometry = NavigationRouteProgressGeometry(route: setupState.routeCoordinates)
        currentRouteProgress = routeGeometry?.progress(of: setupState.initialMarkerCoordinate) ?? 0
        isReroutingOffRoute = false

        removeTrackedMarkerIfNeeded()
        addTrackedMarker(
            at: setupState.initialMarkerCoordinate,
            heading: setupState.initialHeading
        )
        renderRouteProgress(currentRouteProgress, fallbackHeading: setupState.initialHeading)

        if !hasFocusedInitialRoute {
            mapModel.focusTo(coordinates: setupState.routeCoordinates, padding: 48, animated: true)
            hasFocusedInitialRoute = true
        }

        isRouteLoaded = true
    }

    @MainActor
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
                applyCameraFollowModeIfNeeded()
            }

            guard let routeGeometry else {
                updateTrackedMarkerPosition(
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
                return
            }

            let rawTargetProgress = routeGeometry.progress(fromRemainingPath: renderState.remainingPath)
                ?? routeGeometry.progress(of: renderState.markerCoordinate)
            let targetProgress = max(currentRouteProgress, rawTargetProgress)

            animateRouteProgress(
                to: targetProgress,
                duration: renderState.markerTransitionDuration,
                fallbackHeading: renderState.markerHeading
            )

            if renderState.hasArrived {
                stopTrackingMarker()
            }

        case .outOfRoute:
            handleOffRoute(at: location)
        }
    }
    
    @MainActor
    private func handleOffRoute(at location: CLLocation) {
        mapModel.removePolyline(withId: config.routeConnectorPolylineId)

        let heading = location.course >= 0 ? location.course : trackingSession.displayHeading
        updateTrackedMarkerPosition(coordinate: location.coordinate, heading: heading)

        guard !isReroutingOffRoute else {
            return
        }

        if let lastOffRouteRerouteAt,
           Date().timeIntervalSince(lastOffRouteRerouteAt) < config.offRouteRerouteCooldown {
            return
        }

        guard let destination = trackingSession.routeCoordinates.last else {
            log("Out of route but no destination is available for reroute")
            return
        }

        isReroutingOffRoute = true
        lastOffRouteRerouteAt = Date()

        let start = location.coordinate

        Task { [weak self] in
            guard let self else { return }
            let coordinates = await self.fetchRerouteCoordinates(from: start, to: destination)

            await MainActor.run {
                guard self.isTrackingMarker else {
                    self.isReroutingOffRoute = false
                    return
                }
                self.applyReroutedRoute(
                    coordinates: coordinates,
                    currentLocation: start
                )
                self.isReroutingOffRoute = false
            }
        }
    }

    private func fetchRerouteCoordinates(
        from start: CLLocationCoordinate2D,
        to destination: CLLocationCoordinate2D
    ) async -> [CLLocationCoordinate2D] {
        do {
            let route = try await routeProvider.fetchRoute(points: [start, destination])
            if route.count > 1 {
                return route
            }
            return [start, destination]
        } catch {
            log("Reroute request failed, using fallback route. error=\(error)")
            return [start, destination]
        }
    }

    @MainActor
    private func applyReroutedRoute(
        coordinates: [CLLocationCoordinate2D],
        currentLocation: CLLocationCoordinate2D
    ) {
        guard isTrackingMarker else { return }

        guard let rerouteState = trackingSession.configureRoute(
            coordinates: coordinates,
            currentLocation: currentLocation
        ) else {
            log("Reroute configure failed")
            return
        }

        let routePolyline = UniversalMapPolyline(
            id: config.routePolylineId,
            coordinates: rerouteState.routeCoordinates,
            color: config.routeLineColor,
            width: config.routeLineWidth,
            geodesic: true,
            title: "remaining"
        )
        mapModel.updatePolyline(routePolyline, animated: false)
        routeProgressAnimator.cancel()
        routeGeometry = NavigationRouteProgressGeometry(route: rerouteState.routeCoordinates)
        currentRouteProgress = routeGeometry?.progress(of: currentLocation) ?? 0
        renderRouteProgress(currentRouteProgress, fallbackHeading: rerouteState.initialHeading)
        applyCameraFollowModeIfNeeded()

        log("Applied rerouted path and resumed tracking")
    }

    private func applyCameraFollowModeIfNeeded() {
        guard trackedMarker != nil else { return }

        if isCameraFollowEnabled {
            mapModel.trackMarker(
                config.markerId,
                zoom: config.cameraZoom,
                mode: isNavigationModeEnabled ? .courseUp : .northUp,
                pitch: isNavigationModeEnabled ? config.cameraPitch : 0,
                followAnimationDuration: isNavigationModeEnabled ? nil : config.navigationResetAnimationDuration
            )
        } else {
            mapModel.stopTracking()
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

    private func animateRouteProgress(
        to targetProgress: CLLocationDistance,
        duration: TimeInterval,
        fallbackHeading: CLLocationDirection
    ) {
        guard let routeGeometry else {
            return
        }

        let clampedTarget = routeGeometry.clamp(progress: targetProgress)

        if abs(clampedTarget - currentRouteProgress) <= 0.05 {
            renderRouteProgress(clampedTarget, fallbackHeading: fallbackHeading)
            return
        }

        routeProgressAnimator.animate(
            from: currentRouteProgress,
            to: clampedTarget,
            duration: duration,
            onUpdate: { [weak self] progress in
                self?.renderRouteProgress(progress, fallbackHeading: fallbackHeading)
            },
            onCompletion: nil
        )
    }

    private func renderRouteProgress(
        _ progress: CLLocationDistance,
        fallbackHeading: CLLocationDirection
    ) {
        guard let routeGeometry else {
            return
        }

        let clampedProgress = routeGeometry.clamp(progress: progress)
        currentRouteProgress = clampedProgress

        let markerCoordinate = routeGeometry.coordinate(at: clampedProgress)
        let markerHeading = routeGeometry.heading(at: clampedProgress, fallback: fallbackHeading)
        updateTrackedMarkerPosition(coordinate: markerCoordinate, heading: markerHeading)

        let remainingRoute = routeGeometry.remainingRoute(from: clampedProgress)
        mapModel.updatePolyline(
            id: config.routePolylineId,
            coordinates: remainingRoute,
            animated: false
        )
        updateConnectorPath(
            connectorCoordinates(
                markerCoordinate: markerCoordinate,
                remainingRoute: remainingRoute
            )
        )
    }

    private func connectorCoordinates(
        markerCoordinate: CLLocationCoordinate2D,
        remainingRoute: [CLLocationCoordinate2D]
    ) -> [CLLocationCoordinate2D]? {
        guard let routeStartCoordinate = remainingRoute.first else {
            return nil
        }

        let connectorDistance = CLLocation(
            latitude: markerCoordinate.latitude,
            longitude: markerCoordinate.longitude
        ).distance(from: CLLocation(
            latitude: routeStartCoordinate.latitude,
            longitude: routeStartCoordinate.longitude
        ))

        guard connectorDistance > config.connectorHideThreshold else {
            return nil
        }

        return [markerCoordinate, routeStartCoordinate]
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

        routeProgressAnimator.cancel()
        mapModel.removeMarker(withId: markerId)
        trackedMarker = nil
    }

    private func updateTrackedMarkerPosition(
        coordinate: CLLocationCoordinate2D,
        heading: CLLocationDirection
    ) {
        guard let marker = trackedMarker else {
            return
        }

        marker.updatePosition(coordinate: coordinate, heading: heading)
        mapModel.updateTrackedMarker(marker)
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
        Self.logger.debug("\(message, privacy: .public)")
    }
}

extension ContentViewModel: UniversalMapViewModelDelegate {
    func mapDidEndDragging(map: any MapProviderProtocol, at location: CLLocation) {
        Self.logger.debug(
            "EndDragging lat=\(location.coordinate.latitude, privacy: .public) lon=\(location.coordinate.longitude, privacy: .public)"
        )
    }
}
