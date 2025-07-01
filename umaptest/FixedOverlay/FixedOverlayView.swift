//
//  FixedOverlayView.swift
//  umaptest
//
//  Created by applebro on 23/05/25.
//

import Foundation
import SwiftUI
import MapPack
import CoreLocation
import MapLibre

// MARK: - Fixed Car Overlay that stays at coordinate during map dragging

final class FixedCarOverlay: NSObject {
    private weak var mapView: MLNMapView?
    private var carView: UIView?
    private var currentCoordinate: CLLocationCoordinate2D?
    private var currentHeading: CLLocationDirection = 0
    
    init(mapView: MLNMapView) {
        self.mapView = mapView
        super.init()
        setupCarView()
        setupMapObserver()
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
        
        // Add shadow for better visibility
        circle.layer.shadowColor = UIColor.black.cgColor
        circle.layer.shadowOffset = CGSize(width: 0, height: 2)
        circle.layer.shadowOpacity = 0.3
        circle.layer.shadowRadius = 4
        
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
    
    private func setupMapObserver() {
        guard let mapView = mapView else { return }
        
        // Set delegate to listen for map region changes
        if mapView.delegate == nil {
            mapView.delegate = self
        }
    }
    
    func updatePosition(_ coordinate: CLLocationCoordinate2D, heading: CLLocationDirection = 0) {
        currentCoordinate = coordinate
        currentHeading = heading
        
        // Update position immediately
        updateCarViewPosition(animated: true)
    }
    
    private func updateCarViewPosition(animated: Bool = false) {
        guard let mapView = mapView,
              let carView = carView,
              let coordinate = currentCoordinate else { return }
        
        // Convert coordinate to screen point
        let point = mapView.convert(coordinate, toPointTo: mapView)
        
        if animated {
            UIView.animate(withDuration: 0.3, delay: 0, options: [.curveEaseInOut]) {
                carView.center = point
                carView.transform = CGAffineTransform(rotationAngle: self.currentHeading * .pi / 180)
                carView.isHidden = false
            }
        } else {
            // Update position without animation during map movement
            carView.center = point
            carView.transform = CGAffineTransform(rotationAngle: currentHeading * .pi / 180)
            carView.isHidden = false
        }
    }
    
    func hide() {
        carView?.isHidden = true
    }
    
    func remove() {
        carView?.removeFromSuperview()
        carView = nil
        mapView?.delegate = nil
    }
}

// MARK: - MLNMapViewDelegate to handle map region changes
extension FixedCarOverlay: MLNMapViewDelegate {
    
    // Called when map region is changing (during drag, zoom, etc.)
    func mapViewRegionIsChanging(_ mapView: MLNMapView) {
        // Update car position continuously during map movement
        updateCarViewPosition(animated: false)
    }
    
    // Called when map region change is complete
    func mapView(_ mapView: MLNMapView, regionDidChangeAnimated animated: Bool) {
        // Final position update when map movement stops
        updateCarViewPosition(animated: false)
    }
}

// MARK: - Updated ViewModel with Fixed Overlay

final class FixedOverlayViewModel: NSObject, ObservableObject {
    let mapModel = UniversalMapViewModel(mapProvider: .mapLibre, input: nil)
    
    private let locationManager = CLLocationManager()
    @Published var isTrackingCar = false
    
    private var carOverlay: FixedCarOverlay?
    
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
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            self.setupCarOverlay()
        }
    }
    
    private func setupCarOverlay() {
        // Get the MLNMapView from MapLibre provider
        if let mapLibreProvider = mapModel.mapProviderInstance as? MapLibreProvider,
           let mapView = mapLibreProvider.viewModel.mapView {
            carOverlay = FixedCarOverlay(mapView: mapView)
            print("Car overlay setup complete")
        } else {
            print("Failed to setup car overlay - map view not available")
        }
    }
    
    @MainActor
    func startCarTracking() {
        guard !isTrackingCar else { return }
        
        // Ensure overlay is setup
        if carOverlay == nil {
            setupCarOverlay()
        }
        
        locationManager.startUpdatingLocation()
        isTrackingCar = true
        
        print("Started car tracking with fixed overlay")
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
        
        // Update car position - now it will stay at coordinate during map dragging!
        carOverlay?.updatePosition(
            location.coordinate,
            heading: location.course >= 0 ? location.course : 0
        )
        
        print("Car position updated: \(location.coordinate)")
    }
    
    @MainActor
    func focusToCurrentLocation() {
        mapModel.focusToCurrentLocation()
    }
    
    @MainActor
    func addTestCar() {
        // Add a test car at current map center for testing
        if let mapLibreProvider = mapModel.mapProviderInstance as? MapLibreProvider,
           let mapView = mapLibreProvider.viewModel.mapView {
            let centerCoordinate = mapView.centerCoordinate
            carOverlay?.updatePosition(centerCoordinate, heading: 45)
            print("Test car added at: \(centerCoordinate)")
        }
    }
    
    deinit {
        carOverlay?.remove()
    }
}

// MARK: - Location Manager Delegate
extension FixedOverlayViewModel: CLLocationManagerDelegate {
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

// MARK: - Updated ContentView with Test Button
struct FixedOverlayContentView: View {
    @ObservedObject var viewModel = FixedOverlayViewModel()
    
    private var safeArea: UIEdgeInsets {
        UIApplication.shared.safeAreaInsets
    }
    
    var body: some View {
        UniversalMapView(viewModel: viewModel.mapModel)
            .onAppear {
                viewModel.onAppear()
            }
            .overlay {
                VStack {
                    Spacer()
                    
                    // Car tracking controls
                    VStack(spacing: 12) {
                        // Main tracking controls
                        HStack(spacing: 16) {
                            Button {
                                if viewModel.isTrackingCar {
                                    viewModel.stopCarTracking()
                                } else {
                                    viewModel.startCarTracking()
                                }
                            } label: {
                                HStack {
                                    Image(systemName: viewModel.isTrackingCar ? "stop.fill" : "car.fill")
                                    Text(viewModel.isTrackingCar ? "Stop Car" : "Track Car")
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(viewModel.isTrackingCar ? .red : .blue)
                            
                            Button {
                                viewModel.focusToCurrentLocation()
                            } label: {
                                Image(systemName: "scope")
                                    .padding(12)
                            }
                            .buttonStyle(.bordered)
                        }
                        
                        // Test button
                        Button {
                            viewModel.addTestCar()
                        } label: {
                            Text("Add Test Car")
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(.bottom, safeArea.bottom + 20)
                }
            }
    }
}

#Preview {
    FixedOverlayContentView()
}
