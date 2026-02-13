import CoreLocation
import UIKit

protocol RouteProgressAnimating: AnyObject {
    func animate(
        from startProgress: CLLocationDistance,
        to targetProgress: CLLocationDistance,
        duration: TimeInterval,
        onUpdate: @escaping (CLLocationDistance) -> Void,
        onCompletion: (() -> Void)?
    )

    func cancel()
}

final class RouteProgressAnimationService: NSObject, RouteProgressAnimating {
    private var displayLink: CADisplayLink?
    private var startedAt: CFTimeInterval = 0

    private var startProgress: CLLocationDistance = 0
    private var targetProgress: CLLocationDistance = 0
    private var duration: TimeInterval = 0

    private var onUpdate: ((CLLocationDistance) -> Void)?
    private var onCompletion: (() -> Void)?

    func animate(
        from startProgress: CLLocationDistance,
        to targetProgress: CLLocationDistance,
        duration: TimeInterval,
        onUpdate: @escaping (CLLocationDistance) -> Void,
        onCompletion: (() -> Void)?
    ) {
        cancel()

        if duration <= 0 || abs(targetProgress - startProgress) <= 0.001 {
            onUpdate(targetProgress)
            onCompletion?()
            return
        }

        self.startProgress = startProgress
        self.targetProgress = targetProgress
        self.duration = duration
        self.onUpdate = onUpdate
        self.onCompletion = onCompletion
        self.startedAt = CACurrentMediaTime()

        let link = CADisplayLink(target: self, selector: #selector(step))
        link.preferredFramesPerSecond = 30
        link.add(to: .main, forMode: .common)
        self.displayLink = link
    }

    func cancel() {
        displayLink?.invalidate()
        displayLink = nil
        onUpdate = nil
        onCompletion = nil
        duration = 0
    }

    @objc
    private func step() {
        guard let onUpdate else { return }

        let elapsed = CACurrentMediaTime() - startedAt
        let progress = min(1, max(0, elapsed / duration))

        let currentProgress = startProgress + ((targetProgress - startProgress) * progress)
        onUpdate(currentProgress)

        if progress >= 1 {
            let completion = onCompletion
            cancel()
            completion?()
        }
    }
}
