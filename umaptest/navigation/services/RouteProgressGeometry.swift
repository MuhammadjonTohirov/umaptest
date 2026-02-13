import CoreLocation
import MapKit

struct RouteProgressGeometry {
    private let route: [CLLocationCoordinate2D]
    private let routePoints: [MKMapPoint]
    private let cumulativeDistances: [CLLocationDistance]
    let totalDistance: CLLocationDistance

    init(route: [CLLocationCoordinate2D]) {
        self.route = route
        self.routePoints = route.map(MKMapPoint.init)

        var cumulative: [CLLocationDistance] = [0]
        var total: CLLocationDistance = 0

        if route.count > 1 {
            for index in 1..<route.count {
                total += route[index - 1].distance(to: route[index])
                cumulative.append(total)
            }
        }

        self.cumulativeDistances = cumulative
        self.totalDistance = total
    }

    var isValid: Bool {
        route.count >= 2
    }

    func clamp(progress: CLLocationDistance) -> CLLocationDistance {
        max(0, min(totalDistance, progress))
    }

    func progress(of coordinate: CLLocationCoordinate2D) -> CLLocationDistance {
        guard routePoints.count > 1 else { return 0 }

        let point = MKMapPoint(coordinate)
        var bestProgress: CLLocationDistance = 0
        var bestDistance: CLLocationDistance = .greatestFiniteMagnitude

        for index in 0..<(routePoints.count - 1) {
            let start = routePoints[index]
            let end = routePoints[index + 1]
            let projection = project(point: point, start: start, end: end)

            if projection.distance < bestDistance {
                bestDistance = projection.distance
                let segmentLength = cumulativeDistances[index + 1] - cumulativeDistances[index]
                bestProgress = cumulativeDistances[index] + (segmentLength * projection.t)
            }
        }

        return clamp(progress: bestProgress)
    }

    func progress(fromRemainingPath remainingPath: [CLLocationCoordinate2D]) -> CLLocationDistance? {
        guard !remainingPath.isEmpty else { return nil }

        var remainingDistance: CLLocationDistance = 0
        if remainingPath.count > 1 {
            for index in 1..<remainingPath.count {
                remainingDistance += remainingPath[index - 1].distance(to: remainingPath[index])
            }
        }

        return clamp(progress: totalDistance - remainingDistance)
    }

    func coordinate(at progress: CLLocationDistance) -> CLLocationCoordinate2D {
        guard let first = route.first else {
            return .init()
        }

        guard route.count > 1 else {
            return first
        }

        let clamped = clamp(progress: progress)

        if clamped <= 0 {
            return route[0]
        }

        if clamped >= totalDistance {
            return route[route.count - 1]
        }

        for index in 0..<(cumulativeDistances.count - 1) {
            let startDistance = cumulativeDistances[index]
            let endDistance = cumulativeDistances[index + 1]

            if clamped > endDistance {
                continue
            }

            let segmentLength = endDistance - startDistance
            let t: Double
            if segmentLength > 0 {
                t = (clamped - startDistance) / segmentLength
            } else {
                t = 0
            }

            return route[index].interpolated(to: route[index + 1], t: t)
        }

        return route[route.count - 1]
    }

    func heading(at progress: CLLocationDistance, fallback: CLLocationDirection) -> CLLocationDirection {
        guard route.count > 1 else { return fallback }

        let clamped = clamp(progress: progress)
        let lead: CLLocationDistance = 1.0

        let fromProgress = max(0, clamped - lead)
        let toProgress = min(totalDistance, clamped + lead)

        let fromCoordinate = coordinate(at: fromProgress)
        let toCoordinate = coordinate(at: toProgress)

        return fromCoordinate.bearing(to: toCoordinate) ?? fallback
    }

    func remainingRoute(from progress: CLLocationDistance) -> [CLLocationCoordinate2D] {
        guard !route.isEmpty else { return [] }

        guard route.count > 1 else { return [route[0]] }

        let clamped = clamp(progress: progress)

        if clamped <= 0 {
            return route
        }

        if clamped >= totalDistance {
            return [route[route.count - 1]]
        }

        for index in 0..<(cumulativeDistances.count - 1) {
            let endDistance = cumulativeDistances[index + 1]
            if clamped > endDistance {
                continue
            }

            var output: [CLLocationCoordinate2D] = [coordinate(at: clamped)]
            output.append(contentsOf: route[(index + 1)...])
            return compactConsecutiveCoordinates(output)
        }

        return [route[route.count - 1]]
    }

    private func compactConsecutiveCoordinates(
        _ coordinates: [CLLocationCoordinate2D]
    ) -> [CLLocationCoordinate2D] {
        guard !coordinates.isEmpty else { return [] }

        var compacted: [CLLocationCoordinate2D] = []

        for coordinate in coordinates {
            guard let last = compacted.last else {
                compacted.append(coordinate)
                continue
            }

            if last.distance(to: coordinate) > 0.05 {
                compacted.append(coordinate)
            }
        }

        return compacted
    }

    private func project(
        point: MKMapPoint,
        start: MKMapPoint,
        end: MKMapPoint
    ) -> (distance: CLLocationDistance, t: Double) {
        let dx = end.x - start.x
        let dy = end.y - start.y

        if dx == 0 && dy == 0 {
            return (point.distance(to: start), 0)
        }

        let t = (
            ((point.x - start.x) * dx) + ((point.y - start.y) * dy)
        ) / ((dx * dx) + (dy * dy))

        let clampedT = max(0, min(1, t))
        let projected = MKMapPoint(
            x: start.x + (clampedT * dx),
            y: start.y + (clampedT * dy)
        )

        return (point.distance(to: projected), clampedT)
    }
}

private extension CLLocationCoordinate2D {
    func distance(to other: CLLocationCoordinate2D) -> CLLocationDistance {
        CLLocation(latitude: latitude, longitude: longitude).distance(
            from: CLLocation(latitude: other.latitude, longitude: other.longitude)
        )
    }

    func interpolated(to other: CLLocationCoordinate2D, t: Double) -> CLLocationCoordinate2D {
        .init(
            latitude: latitude + ((other.latitude - latitude) * t),
            longitude: longitude + ((other.longitude - longitude) * t)
        )
    }

    func bearing(to other: CLLocationCoordinate2D) -> CLLocationDirection? {
        let lat1 = latitude * .pi / 180
        let lon1 = longitude * .pi / 180
        let lat2 = other.latitude * .pi / 180
        let lon2 = other.longitude * .pi / 180

        let deltaLon = lon2 - lon1
        let y = sin(deltaLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(deltaLon)

        guard x != 0 || y != 0 else { return nil }

        var heading = atan2(y, x) * 180 / .pi
        heading = heading.truncatingRemainder(dividingBy: 360)
        if heading < 0 { heading += 360 }
        return heading
    }
}
