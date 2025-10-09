//
//  ContentViewModel.swift
//  umaptest
//
//  Created by applebro on 23/05/25.
//

import SwiftUI
import MapPack
import CoreLocation
import Combine

final class ContentViewModel: NSObject, ObservableObject {
    let mapModel = UniversalMapViewModel(
        mapProvider: .mapLibre,
        input: GoogleMapInput()
    )
    
    // Location manager for tracking
    private let locationManager = CLLocationManager()
    
    // Marker tracking properties
    @Published var isTrackingMarker = false
    private var trackedMarker: UniversalMarker?
    private let trackedMarkerReuseId = "tracked-location-marker"
    
    override init() {
        super.init()
        setupLocationManager()
    }
    
    private func setupLocationManager() {
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.distanceFilter = 1.0 // Update every 1 meter
    }
    
    func onAppear() {
        let insets = UIApplication.shared.safeAreaInsets
        self.mapModel.setEdgeInsets(.init(
            top: insets.top,
            left: 0,
            bottom: 0,
            right: 0,
            animated: true,
            onEnd: nil
        ))
        mapModel.setInteractionDelegate(self)
        mapModel.pinModel.set(state: .waiting(time: "1", unit: "MIN"))
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            self.mapModel.pinModel.set(state: .steady)
        }
        locationManager.requestWhenInUseAuthorization()
    }
    
    @MainActor
    func focusToCurrentLocation() {
//        self.mapModel.focusToCurrentLocation()
        guard let loc = locationManager.location?.coordinate else { return }
        
        self.mapModel.mapProviderInstance.updateCamera(to: .init(
            center: loc,
            zoom: 18,
            bearing: 0,
            pitch: 30,
            animate: true
        ))
    }
    
    @MainActor
    func startTrackingMarker() {
        guard !isTrackingMarker else { return }
        
        guard let currentLocation = locationManager.location else {
            print("No current location available")
            return
        }
        
        // Create the marker at current location
        let markerView = createMarkerView()
        let marker = UniversalMarker(
            id: "tracked-marker",
            coordinate: currentLocation.coordinate,
            view: markerView,
            reuseIdentifier: trackedMarkerReuseId,
            tintColor: .blue
        )
        
        marker.setGroundAnchor(CGPoint(x: 0.5, y: 0.5))
        
        // Store reference to the marker
        trackedMarker = marker
        
        // Add marker to map
        mapModel.addMarker(marker)
        
        // Start location updates
        locationManager.startUpdatingLocation()
        isTrackingMarker = true
        
        print("Started tracking marker")
        mapModel.trackMarker("tracked-marker")
    }
    
    @MainActor
    func stopTrackingMarker() {
        guard isTrackingMarker else { return }
        
        // Stop location updates
        locationManager.stopUpdatingLocation()
        
        // Remove the marker from map
        if let marker = trackedMarker {
            mapModel.removeMarker(withId: marker.id)
        }
        
        // Reset tracking state
        isTrackingMarker = false
        trackedMarker = nil
        mapModel.stopTracking()
        print("Stopped tracking marker")
    }
    
    @MainActor
    private func updateMarkerLocation(_ location: CLLocation) {
        guard isTrackingMarker,
              let marker = trackedMarker?.copy() as? UniversalMarker else {
            return
        }
        
        marker.updatePosition(coordinate: location.coordinate, heading: location.course)
        mapModel.updateMarkerWithTracking(marker)
        
        print("Updated marker position to: \(location.coordinate)")
    }
    
    @MainActor
    func startTrackingMarkerWithFocus() {
        startTrackingMarker()
        
        if let currentLocation = locationManager.location {
            mapModel.focusMap(on: currentLocation.coordinate, zoom: 18, animated: true)
        }
        
    }
    
    private func createMarkerView() -> UIView {
        let containerView = UIView(frame: CGRect(x: 0, y: 0, width: 40, height: 40))
        
        // Create a blue circle background with pulse effect
        let circleView = UIView(frame: CGRect(x: 0, y: 0, width: 40, height: 40))
        circleView.backgroundColor = UIColor.systemBlue
        circleView.layer.cornerRadius = 20
        circleView.layer.borderWidth = 3
        circleView.layer.borderColor = UIColor.white.cgColor
        
        // Add subtle shadow
        circleView.layer.shadowColor = UIColor.black.cgColor
        circleView.layer.shadowOffset = CGSize(width: 0, height: 2)
        circleView.layer.shadowOpacity = 0.3
        circleView.layer.shadowRadius = 4
        
        // Add a car icon in the center
        let imageView = UIImageView(frame: CGRect(x: 8, y: 8, width: 24, height: 24))
        imageView.image = UIImage(systemName: "car.fill")
        imageView.tintColor = .white
        imageView.contentMode = .scaleAspectFit
        
        containerView.addSubview(circleView)
        containerView.addSubview(imageView)
        
        return containerView
    }
    
    // MARK: - Advanced marker tracking methods
    
    @MainActor
    func startSmoothTracking() {
        guard !isTrackingMarker else { return }
        
        // Use higher accuracy for smooth tracking
        locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        locationManager.distanceFilter = 0.5 // Update every 0.5 meters
        
        startTrackingMarker()
    }
    
    @MainActor
    func updateTrackingAccuracy(_ accuracy: CLLocationAccuracy) {
        locationManager.desiredAccuracy = accuracy
    }
    
    @MainActor
    func updateDistanceFilter(_ distance: CLLocationDistance) {
        locationManager.distanceFilter = distance
    }
}

// MARK: - CLLocationManagerDelegate
extension ContentViewModel: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        
        // Filter out old or inaccurate locations
        let age = abs(location.timestamp.timeIntervalSinceNow)
        if age > 5.0 { // Ignore locations older than 5 seconds
            return
        }
        
        if location.horizontalAccuracy > 50.0 { // Ignore inaccurate locations
            return
        }
        
        Task { @MainActor in
            updateMarkerLocation(location)
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Location manager failed with error: \(error)")
    }
    
    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        switch status {
        case .authorizedWhenInUse, .authorizedAlways:
            print("Location access authorized")
        case .denied, .restricted:
            print("Location access denied")
            Task { @MainActor in
                if isTrackingMarker {
                    stopTrackingMarker()
                }
            }
        case .notDetermined:
            print("Location access not determined")
        @unknown default:
            break
        }
    }
}

extension ContentViewModel: UniversalMapViewModelDelegate {
    func mapDidEndDragging(map: any MapProviderProtocol, at location: CLLocation) {
        debugPrint("EndDragging", location)
    }
}
