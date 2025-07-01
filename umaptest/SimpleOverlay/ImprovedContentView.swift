//
//  ImprovedContentView.swift
//  umaptest
//
//  Created by applebro on 23/05/25.
//

import Foundation
import SwiftUI
import MapPack


// MARK: - Updated ContentView
struct ImprovedContentView: View {
    @ObservedObject var viewModel = ImprovedContentViewModel()
    
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
                    .padding(.bottom, safeArea.bottom + 20)
                }
            }
    }
}

#Preview {
    ImprovedContentView()
}
