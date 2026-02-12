import CoreLocation

enum LocationProviderEvent {
    case didUpdateLocation(CLLocation)
    case didFail(Error)
    case didChangeAuthorization(CLAuthorizationStatus)
}

protocol LocationProviding: AnyObject {
    var latestLocation: CLLocation? { get }
    var eventHandler: ((LocationProviderEvent) -> Void)? { get set }

    func requestWhenInUseAuthorization()
    func startUpdatingLocation(accuracy: CLLocationAccuracy, distanceFilter: CLLocationDistance)
    func stopUpdatingLocation()
    func setDesiredAccuracy(_ accuracy: CLLocationAccuracy)
    func setDistanceFilter(_ filter: CLLocationDistance)
}

final class CoreLocationProvider: NSObject, LocationProviding {
    var eventHandler: ((LocationProviderEvent) -> Void)?

    var latestLocation: CLLocation? {
        manager.location
    }

    private let manager: CLLocationManager

    init(manager: CLLocationManager = CLLocationManager()) {
        self.manager = manager
        super.init()
        self.manager.delegate = self
        self.manager.desiredAccuracy = kCLLocationAccuracyBest
    }

    func requestWhenInUseAuthorization() {
        manager.requestWhenInUseAuthorization()
    }

    func startUpdatingLocation(accuracy: CLLocationAccuracy, distanceFilter: CLLocationDistance) {
        manager.desiredAccuracy = accuracy
        manager.distanceFilter = distanceFilter
        manager.startUpdatingLocation()
    }

    func stopUpdatingLocation() {
        manager.stopUpdatingLocation()
    }

    func setDesiredAccuracy(_ accuracy: CLLocationAccuracy) {
        manager.desiredAccuracy = accuracy
    }

    func setDistanceFilter(_ filter: CLLocationDistance) {
        manager.distanceFilter = filter
    }
}

extension CoreLocationProvider: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        eventHandler?(.didUpdateLocation(location))
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        eventHandler?(.didFail(error))
    }

    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        eventHandler?(.didChangeAuthorization(status))
    }
}
