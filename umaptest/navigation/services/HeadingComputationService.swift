import CoreLocation

enum RouteHeadingStrategy {
    case lookAhead
    case threePointWeighted
}

struct HeadingComputationInput {
    let snappedCoordinate: CLLocationCoordinate2D
    let remainingPath: [CLLocationCoordinate2D]
    let location: CLLocation
    let lastDisplayCoordinate: CLLocationCoordinate2D?
    let currentDisplayHeading: CLLocationDirection
    let routeHeadingStrategy: RouteHeadingStrategy
    let lookAheadDistance: CLLocationDistance
    let minReliableCourseSpeed: CLLocationSpeed
    let serverHeading: (value: CLLocationDirection, timestamp: Date)?
    let serverHeadingMaxAge: TimeInterval
}

protocol HeadingComputing {
    func computeTargetHeading(input: HeadingComputationInput) -> CLLocationDirection
    func smoothHeading(
        from current: CLLocationDirection,
        to target: CLLocationDirection,
        factor: Double,
        deltaTime: TimeInterval,
        maxTurnRatePerSecond: CLLocationDirection
    ) -> CLLocationDirection
    func bearing(from source: CLLocationCoordinate2D, to destination: CLLocationCoordinate2D) -> CLLocationDirection
    func distance(from source: CLLocationCoordinate2D, to destination: CLLocationCoordinate2D) -> CLLocationDistance
}

struct HeadingComputationService: HeadingComputing {
    func computeTargetHeading(input: HeadingComputationInput) -> CLLocationDirection {
        if let freshServerHeading = latestFreshServerHeading(
            serverHeading: input.serverHeading,
            eventTime: input.location.timestamp,
            maxAge: input.serverHeadingMaxAge
        ) {
            return freshServerHeading
        }

        if let routeHeading = routeHeading(
            from: input.remainingPath,
            strategy: input.routeHeadingStrategy,
            lookAheadDistance: input.lookAheadDistance
        ) {
            return routeHeading
        }

        if let lastCoordinate = input.lastDisplayCoordinate {
            let movementDistance = distance(from: lastCoordinate, to: input.snappedCoordinate)
            if movementDistance > 0.8 {
                return bearing(from: lastCoordinate, to: input.snappedCoordinate)
            }
        }

        if input.location.course >= 0, input.location.speed >= input.minReliableCourseSpeed {
            return input.location.course
        }

        return input.currentDisplayHeading
    }

    func smoothHeading(
        from current: CLLocationDirection,
        to target: CLLocationDirection,
        factor: Double,
        deltaTime: TimeInterval,
        maxTurnRatePerSecond: CLLocationDirection
    ) -> CLLocationDirection {
        let blendedDelta = shortestHeadingDelta(from: current, to: target) * factor
        let maxDelta = maxTurnRatePerSecond * max(1.0 / 60.0, min(deltaTime, 1.0))
        let clampedDelta = max(-maxDelta, min(maxDelta, blendedDelta))
        return (current + clampedDelta).normalizedHeading
    }

    func bearing(from source: CLLocationCoordinate2D, to destination: CLLocationCoordinate2D) -> CLLocationDirection {
        let lat1 = source.latitude.radians
        let lon1 = source.longitude.radians
        let lat2 = destination.latitude.radians
        let lon2 = destination.longitude.radians

        let dLon = lon2 - lon1
        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        let radiansBearing = atan2(y, x)

        return radiansBearing.degrees.normalizedHeading
    }

    func distance(from source: CLLocationCoordinate2D, to destination: CLLocationCoordinate2D) -> CLLocationDistance {
        CLLocation(latitude: source.latitude, longitude: source.longitude).distance(
            from: CLLocation(latitude: destination.latitude, longitude: destination.longitude)
        )
    }

    private func shortestHeadingDelta(
        from source: CLLocationDirection,
        to destination: CLLocationDirection
    ) -> CLLocationDirection {
        var delta = destination - source
        while delta > 180 { delta -= 360 }
        while delta < -180 { delta += 360 }
        return delta
    }

    private func latestFreshServerHeading(
        serverHeading: (value: CLLocationDirection, timestamp: Date)?,
        eventTime: Date,
        maxAge: TimeInterval
    ) -> CLLocationDirection? {
        guard let serverHeading else { return nil }

        let age = abs(eventTime.timeIntervalSince(serverHeading.timestamp))
        guard age <= maxAge else {
            return nil
        }

        return serverHeading.value
    }

    private func routeHeading(
        from path: [CLLocationCoordinate2D],
        strategy: RouteHeadingStrategy,
        lookAheadDistance: CLLocationDistance
    ) -> CLLocationDirection? {
        switch strategy {
        case .lookAhead:
            return routeTangentHeading(from: path, lookAheadDistance: lookAheadDistance)
        case .threePointWeighted:
            return routeThreePointWeightedHeading(from: path)
        }
    }

    private func routeTangentHeading(
        from path: [CLLocationCoordinate2D],
        lookAheadDistance: CLLocationDistance
    ) -> CLLocationDirection? {
        guard path.count > 1 else { return nil }

        let start = path[0]
        var traversed: CLLocationDistance = 0

        for index in 0..<(path.count - 1) {
            let segmentStart = path[index]
            let segmentEnd = path[index + 1]
            let segmentDistance = distance(from: segmentStart, to: segmentEnd)
            guard segmentDistance > 0 else { continue }

            if traversed + segmentDistance >= lookAheadDistance {
                let remainingDistance = max(0, lookAheadDistance - traversed)
                let progress = min(1, remainingDistance / segmentDistance)
                let target = CLLocationCoordinate2D(
                    latitude: segmentStart.latitude + (segmentEnd.latitude - segmentStart.latitude) * progress,
                    longitude: segmentStart.longitude + (segmentEnd.longitude - segmentStart.longitude) * progress
                )
                return bearing(from: start, to: target)
            }

            traversed += segmentDistance
        }

        guard let last = path.last else { return nil }
        return bearing(from: start, to: last)
    }

    private func routeThreePointWeightedHeading(from path: [CLLocationCoordinate2D]) -> CLLocationDirection? {
        guard path.count > 1 else { return nil }
        if path.count == 2 {
            return bearing(from: path[0], to: path[1])
        }

        let p0 = path[0]
        let p1 = path[1]
        let p2 = path[2]

        let v1 = routeSegmentVector(from: p0, to: p1)
        let v2 = routeSegmentVector(from: p1, to: p2)

        let weightedX = (v1.dx * 0.65) + (v2.dx * 0.35)
        let weightedY = (v1.dy * 0.65) + (v2.dy * 0.35)

        if abs(weightedX) < 0.001, abs(weightedY) < 0.001 {
            return bearing(from: p0, to: p1)
        }

        return atan2(weightedX, weightedY).degrees.normalizedHeading
    }

    private func routeSegmentVector(
        from start: CLLocationCoordinate2D,
        to end: CLLocationCoordinate2D
    ) -> (dx: Double, dy: Double) {
        let meanLat = ((start.latitude + end.latitude) * 0.5).radians
        let dx = (end.longitude - start.longitude) * cos(meanLat) * 111_320.0
        let dy = (end.latitude - start.latitude) * 110_540.0
        return (dx, dy)
    }
}

private extension Double {
    var radians: Double {
        self * .pi / 180
    }

    var degrees: Double {
        self * 180 / .pi
    }

    var normalizedHeading: Double {
        var value = self.truncatingRemainder(dividingBy: 360)
        if value < 0 { value += 360 }
        return value
    }
}
