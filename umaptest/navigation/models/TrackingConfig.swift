import CoreLocation
import UIKit

struct TrackingConfig {
    let markerId: String
    let markerReuseIdentifier: String
    let routePolylineId: String
    let routeConnectorPolylineId: String
    let carIconName: String

    let defaultDistanceFilter: CLLocationDistance
    let trackingDistanceFilter: CLLocationDistance
    let routeSnapThreshold: CLLocationDistance
    let routeArrivalThreshold: CLLocationDistance
    let connectorHideThreshold: CLLocationDistance

    let locationMaxAge: TimeInterval
    let maximumHorizontalAccuracy: CLLocationAccuracy

    let headingSmoothingFactor: Double
    let routeHeadingLookAheadDistance: CLLocationDistance
    let minReliableCourseSpeed: CLLocationSpeed
    let maxHeadingTurnRatePerSecond: CLLocationDirection
    let serverHeadingMaxAge: TimeInterval

    let markerAnimationFallbackDuration: TimeInterval
    let markerAnimationMinDuration: TimeInterval
    let markerAnimationMaxDuration: TimeInterval
    let offRouteRerouteCooldown: TimeInterval

    let cameraZoom: Double
    let cameraPitch: Double
    let pinLoadingDelay: TimeInterval

    let markerSize: CGFloat
    let routeLineWidth: CGFloat
    let routeLineColor: UIColor

    let pointA: CLLocationCoordinate2D
    let pointB: CLLocationCoordinate2D

    static let live = TrackingConfig(
        markerId: "tracked-marker",
        markerReuseIdentifier: "tracked-location-marker",
        routePolylineId: "remaining-route",
        routeConnectorPolylineId: "remaining-route-connector",
        carIconName: "icon_car_top_view",
        defaultDistanceFilter: 1.0,
        trackingDistanceFilter: 2.0,
        routeSnapThreshold: 80.0,
        routeArrivalThreshold: 8.0,
        connectorHideThreshold: 1.2,
        locationMaxAge: 5.0,
        maximumHorizontalAccuracy: 50.0,
        headingSmoothingFactor: 0.28,
        routeHeadingLookAheadDistance: 12.0,
        minReliableCourseSpeed: 2.5,
        maxHeadingTurnRatePerSecond: 120.0,
        serverHeadingMaxAge: 3.0,
        markerAnimationFallbackDuration: 0.35,
        markerAnimationMinDuration: 0.15,
        markerAnimationMaxDuration: 1.0,
        offRouteRerouteCooldown: 2.0,
        cameraZoom: 18.0,
        cameraPitch: 30.0,
        pinLoadingDelay: 1.0,
        markerSize: 42,
        routeLineWidth: 7,
        routeLineColor: .systemBlue,
        pointA: CLLocationCoordinate2D(latitude: 40.383381, longitude: 71.779115),
        pointB: CLLocationCoordinate2D(latitude: 40.394063, longitude: 71.800686)
    )
}
