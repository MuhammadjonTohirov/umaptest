import CoreLocation

protocol LocationValidating {
    func isValid(_ location: CLLocation) -> Bool
}

struct DefaultLocationValidationService: LocationValidating {
    private let maxAge: TimeInterval
    private let maxHorizontalAccuracy: CLLocationAccuracy

    init(maxAge: TimeInterval, maxHorizontalAccuracy: CLLocationAccuracy) {
        self.maxAge = maxAge
        self.maxHorizontalAccuracy = maxHorizontalAccuracy
    }

    func isValid(_ location: CLLocation) -> Bool {
        let age = abs(location.timestamp.timeIntervalSinceNow)
        guard age <= maxAge else { return false }
        return location.horizontalAccuracy <= maxHorizontalAccuracy
    }
}
