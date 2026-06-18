//
//  UIKitMapDemoViewController.swift
//  umaptest
//
//  Pure-UIKit demo of the Universal Map's UIKit entry point
//  (`UniversalMapViewController`). It exercises the shared view-model API
//  (markers, polylines, camera) and the native pin / address overlay — proving
//  the map works in UIKit without any SwiftUI hosting.
//

import UIKit
import MapPack
import CoreLocation

@MainActor
final class UIKitMapDemoViewController: UIViewController {

    /// Invoked when the user taps the close button.
    var onClose: (() -> Void)?

    private let mapController = UniversalMapViewController(
        provider: .mapLibre,
        config: MapConfig(config: MapLibreConfig())
    )

    private let pinStateLabel = UILabel()

    /// A short demo route around Fergana.
    private let routeCoordinates: [CLLocationCoordinate2D] = [
        .init(latitude: 40.38942, longitude: 71.78280),
        .init(latitude: 40.38610, longitude: 71.79100),
        .init(latitude: 40.38120, longitude: 71.79760),
        .init(latitude: 40.37640, longitude: 71.80520)
    ]

    private let pinStates: [PinState] = [
        .initial, .loading, .pinning,
        .waiting(time: "2", unit: "MIN"), .steady, .searching
    ]
    private var pinStateIndex = 0

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        title = "UIKit Map Demo"

        embedMap()
        setupControls()
        configureMap()
    }

    // MARK: - Map

    private func embedMap() {
        addChild(mapController)
        mapController.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(mapController.view)
        NSLayoutConstraint.activate([
            mapController.view.topAnchor.constraint(equalTo: view.topAnchor),
            mapController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            mapController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            mapController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
        mapController.didMove(toParent: self)
    }

    private func configureMap() {
        // Chainable API mirrors the SwiftUI UniversalMapView modifiers.
        mapController.showsUserLocation(false)

        addDemoMarker()
        drawDemoRoute()
        mapController.viewModel.focusTo(coordinates: routeCoordinates, padding: 64, animated: true)

        // The view model clears the address while the camera moves (address-picker
        // behaviour), so apply the pin state + address once the focus animation settles.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.applyPinState()
        }
    }

    private func addDemoMarker() {
        let imageView = UIImageView(image: UIImage(systemName: "car.fill"))
        imageView.tintColor = .systemBlue
        imageView.contentMode = .scaleAspectFit
        imageView.frame = CGRect(x: 0, y: 0, width: 36, height: 36)

        let marker = UniversalMarker(
            id: "demo-car",
            coordinate: routeCoordinates[0],
            view: imageView
        )
        mapController.viewModel.addMarker(marker)
    }

    private func drawDemoRoute() {
        let polyline = UniversalMapPolyline(
            id: "demo-route",
            coordinates: routeCoordinates,
            color: .systemBlue,
            width: 6,
            geodesic: true,
            title: "demo"
        )
        mapController.viewModel.addPolyline(polyline, animated: true)
    }

    // MARK: - Controls

    private func setupControls() {
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .close,
            target: self,
            action: #selector(closeTapped)
        )

        pinStateLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        pinStateLabel.textColor = .label
        pinStateLabel.textAlignment = .center

        let cyclePinButton = makeButton(title: "Cycle Pin State", action: #selector(cyclePinTapped))
        let focusButton = makeButton(title: "Focus Route", action: #selector(focusTapped))

        let stack = UIStackView(arrangedSubviews: [pinStateLabel, cyclePinButton, focusButton])
        stack.axis = .vertical
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false

        let panel = UIView()
        panel.backgroundColor = UIColor.systemBackground.withAlphaComponent(0.92)
        panel.layer.cornerRadius = 14
        panel.translatesAutoresizingMaskIntoConstraints = false
        panel.addSubview(stack)
        view.addSubview(panel)

        NSLayoutConstraint.activate([
            panel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            panel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            panel.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: panel.topAnchor, constant: 12),
            stack.bottomAnchor.constraint(equalTo: panel.bottomAnchor, constant: -12),
            stack.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: panel.trailingAnchor, constant: -12)
        ])
    }

    private func makeButton(title: String, action: Selector) -> UIButton {
        var configuration = UIButton.Configuration.borderedProminent()
        configuration.title = title
        let button = UIButton(configuration: configuration)
        button.addTarget(self, action: action, for: .touchUpInside)
        return button
    }

    @objc private func closeTapped() {
        onClose?()
    }

    @objc private func focusTapped() {
        mapController.viewModel.focusTo(coordinates: routeCoordinates, padding: 64, animated: true)
    }

    @objc private func cyclePinTapped() {
        pinStateIndex = (pinStateIndex + 1) % pinStates.count
        applyPinState()
    }

    private func applyPinState() {
        let state = pinStates[pinStateIndex]
        let name = pinStateName(state)
        mapController.viewModel.pinModel.set(state: state)
        mapController.viewModel.set(addressViewInfo: AddressInfo(name: "Demo • \(name)"))
        pinStateLabel.text = "Pin state: \(name)"
    }

    private func pinStateName(_ state: PinState) -> String {
        switch state {
        case .initial: return "initial"
        case .loading: return "loading"
        case .pinning: return "pinning"
        case .waiting: return "waiting"
        case .steady: return "steady"
        case .searching: return "searching"
        }
    }
}
