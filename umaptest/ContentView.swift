//
//  ContentView.swift
//  umaptest
//
//  Created by applebro on 22/05/25.
//

import SwiftUI
import MapPack

struct ContentView: View {
    @ObservedObject
    var viewModel = ContentViewModel()
    
    private var safeArea: UIEdgeInsets {
        UIApplication.shared.safeAreaInsets
    }
    
    private var screenSize: CGSize {
        UIScreen.main.bounds.size
    }
    
    var body: some View {
        UniversalMapView(
            viewModel: viewModel.mapModel
        )
        .onAppear {
            viewModel.onAppear()
        }
        .overlay {
            VStack {
                Spacer()
                
                // Marker tracking controls
                markerTrackingControls
                    .padding(.bottom, 10)
                
                // Bottom action buttons
                bottomActions
                    .padding(.bottom, safeArea.bottom + 10)
            }
        }
    }
    
    private var markerTrackingControls: some View {
        HStack(spacing: 12) {
            Button {
                if viewModel.isTrackingMarker {
                    viewModel.stopTrackingMarker()
                } else {
                    viewModel.startTrackingMarker()
                }
            } label: {
                HStack {
                    Image(systemName: viewModel.isTrackingMarker ? "stop.fill" : "car.fill")
                    Text(viewModel.isTrackingMarker ? "Stop Tracking" : "Track Marker")
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .tint(viewModel.isTrackingMarker ? .red : .blue)
            
            Button {
                viewModel.startTrackingMarkerWithFocus()
            } label: {
                HStack {
                    Image(systemName: "location.viewfinder")
                    Text("Track & Focus")
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
            .buttonStyle(.bordered)
            .disabled(viewModel.isTrackingMarker)
        }
        .padding(.horizontal, 20)
    }
    
    private var bottomActions: some View {
        HStack {
            // Status indicator
            statusIndicator
            
            Spacer()
            
            // Focus button
            focusButton
                .onTapGesture {
                    viewModel.focusToCurrentLocation()
                }
        }
        .padding(.horizontal, 20)
        .frame(height: 60)
    }
    
    private var statusIndicator: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(viewModel.isTrackingMarker ? Color.green : Color.gray)
                .frame(width: 8, height: 8)
                .animation(.easeInOut, value: viewModel.isTrackingMarker)
            
            Text(viewModel.isTrackingMarker ? "Tracking" : "Idle")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(.background)
                .shadow(color: .black.opacity(0.1), radius: 2)
        )
    }
    
    private var focusButton: some View {
        Image(systemName: "scope")
            .font(.system(size: 18, weight: .medium))
            .foregroundColor(.primary)
            .padding(12)
            .background(
                Circle()
                    .foregroundStyle(.background)
                    .shadow(
                        color: .black.opacity(0.2),
                        radius: 4
                    )
            )
    }
}

#Preview {
    ContentView()
}
