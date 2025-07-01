//
//  CarOverlayTest.swift
//  umaptest
//
//  Created by applebro on 23/05/25.
//

import Foundation
import SwiftUI
import MapPack
import CoreLocation
import MapLibre

// MARK: - Simple Car Overlay (Replace your marker approach with this)

final class SimpleCarOverlay {
    private weak var mapView: MLNMapView?
    private var carView: UIView?
    private var currentCoordinate: CLLocationCoordinate2D?
    
    init(mapView: MLNMapView) {
        self.mapView = mapView
        setupCarView()
    }
    
    private func setupCarView() {
        guard let mapView = mapView else { return }
        
        // Create car view
        let carContainer = UIView(frame: CGRect(x: 0, y: 0, width: 40, height: 40))
        carContainer.backgroundColor = .clear
        
        // Car circle
        let circle = UIView(frame: CGRect(x: 0, y: 0, width: 40, height: 40))
        circle.backgroundColor = .systemBlue
        circle.layer.cornerRadius = 20
        circle.layer.borderWidth = 3
        circle.layer.borderColor = UIColor.white.cgColor
        
        // Car icon
        let imageView = UIImageView(frame: CGRect(x: 8, y: 8, width: 24, height: 24))
        imageView.image = UIImage(systemName: "car.fill")
        imageView.tintColor = .white
        
        carContainer.addSubview(circle)
        carContainer.addSubview(imageView)
        
        // Add to map
        mapView.addSubview(carContainer)
        carContainer.isHidden = true
        
        self.carView = carContainer
    }
    
    func updatePosition(_ coordinate: CLLocationCoordinate2D, heading: CLLocationDirection = 0) {
        guard let mapView = mapView, let carView = carView else { return }
        
        currentCoordinate = coordinate
        
        // Convert coordinate to screen point
        let point = mapView.convert(coordinate, toPointTo: mapView)
        
        // Smooth animation to new position
        UIView.animate(withDuration: 1, delay: 0, options: [.curveLinear]) {
            carView.center = point
            carView.transform = CGAffineTransform(rotationAngle: heading * .pi / 180)
            carView.isHidden = false
        }
    }
    
    func hide() {
        carView?.isHidden = true
    }
    
    func remove() {
        carView?.removeFromSuperview()
        carView = nil
    }
}


final class GoogleMapInput: GoogleMapsKeyProvider {
    let accessKey: String = "AIzaSyC_dHd88uaz8yUlmxKbvXo7n-a7mPhgaWI"
}

final class ImprovedContentViewModel: NSObject, ObservableObject {
    let mapModel = UniversalMapViewModel(mapProvider: .mapLibre, input: nil)
    
    private let locationManager = CLLocationManager()
    @Published var isTrackingCar = false
    
    private var carOverlay: SimpleCarOverlay?
    
    override init() {
        super.init()
        setupLocationManager()
    }
    
    private func setupLocationManager() {
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.distanceFilter = 1.0
    }
    
    func onAppear() {
        let insets = UIApplication.shared.safeAreaInsets
        self.mapModel.setEdgeInsets(.init(
            top: insets.top,
            left: 0,
            bottom: insets.bottom,
            right: 0,
            animated: true,
            onEnd: nil
        ))
        
        locationManager.requestWhenInUseAuthorization()
        
        // Setup car overlay after map is ready
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.setupCarOverlay()
        }
    }
    
    private func setupCarOverlay() {
        // Get the MLNMapView from MapLibre provider
        if let mapLibreProvider = mapModel.mapProviderInstance as? MapLibreProvider,
           let mapView = mapLibreProvider.viewModel.mapView {
            carOverlay = SimpleCarOverlay(mapView: mapView)
        }
    }
    
    @MainActor
    func startCarTracking() {
        guard !isTrackingCar else { return }
        
        locationManager.startUpdatingLocation()
        isTrackingCar = true
        
        print("Started car tracking with overlay")
    }
    
    @MainActor
    func stopCarTracking() {
        guard isTrackingCar else { return }
        
        locationManager.stopUpdatingLocation()
        carOverlay?.hide()
        isTrackingCar = false
        
        print("Stopped car tracking")
    }
    
    @MainActor
    private func updateCarPosition(_ location: CLLocation) {
        guard isTrackingCar else { return }
        
        // Update car position with smooth animation - NO FLICKERING!
        carOverlay?.updatePosition(
            location.coordinate,
            heading: location.course >= 0 ? location.course : 0
        )
        
        print("Car moved to: \(location.coordinate)")
    }
    
    @MainActor
    func focusToCurrentLocation() {
        mapModel.focusToCurrentLocation()
    }
    
    deinit {
        carOverlay?.remove()
    }
}

// MARK: - Location Manager Delegate
extension ImprovedContentViewModel: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        
        // Filter bad locations
        let age = abs(location.timestamp.timeIntervalSinceNow)
        if age > 5.0 || location.horizontalAccuracy > 50.0 {
            return
        }
        
        Task { @MainActor in
            updateCarPosition(location)
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Location error: \(error)")
    }
    
    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        switch status {
        case .authorizedWhenInUse, .authorizedAlways:
            print("Location authorized")
        case .denied, .restricted:
            Task { @MainActor in
                if isTrackingCar {
                    stopCarTracking()
                }
            }
        default:
            break
        }
    }
}
