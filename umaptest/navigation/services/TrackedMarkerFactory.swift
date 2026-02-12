import UIKit
import MapPack
import CoreLocation

protocol TrackedMarkerFactoryProviding {
    func makeMarker(id: String, reuseIdentifier: String, coordinate: CLLocationCoordinate2D) -> UniversalMarker
}

struct TrackedMarkerFactory: TrackedMarkerFactoryProviding {
    private let markerSize: CGFloat
    private let carIconName: String

    init(markerSize: CGFloat, carIconName: String) {
        self.markerSize = markerSize
        self.carIconName = carIconName
    }

    func makeMarker(id: String, reuseIdentifier: String, coordinate: CLLocationCoordinate2D) -> UniversalMarker {
        let marker = UniversalMarker(
            id: id,
            coordinate: coordinate,
            view: makeMarkerView(),
            reuseIdentifier: reuseIdentifier,
            tintColor: .blue
        )
        marker.set(compensatesForMapBearing: true)
        marker.setGroundAnchor(CGPoint(x: 0.5, y: 0.5))
        return marker
    }

    private func makeMarkerView() -> UIView {
        let frame = CGRect(x: 0, y: 0, width: markerSize, height: markerSize)
        let container = UIView(frame: frame)

        let imageView = UIImageView(frame: frame)
        imageView.image = UIImage(named: carIconName) ?? UIImage(systemName: "car.fill")
        imageView.contentMode = .scaleAspectFit

        container.layer.shadowColor = UIColor.black.cgColor
        container.layer.shadowOffset = CGSize(width: 0, height: 1)
        container.layer.shadowOpacity = 0.3
        container.layer.shadowRadius = 2
        container.addSubview(imageView)

        return container
    }
}
