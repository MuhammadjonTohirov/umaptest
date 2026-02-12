//
//  TestView.swift
//  umaptest
//
//  Created by applebro on 27/05/25.
//

import Foundation
import SwiftUI
import YallaKit

struct TestView: View {
    @State private var coords: [Coord] = []
    var body: some View {
        ZStack {
            VStack {
                Text("Coord count \(coords.count)")
                ScrollView {
                    VStack(spacing: 10) {
                        ForEach(coords.indices, id: \.self) { index in
                            Text(verbatim: "\(coords[index])")
                        }
                    }
                }
            }
        }
        .onAppear {
            onAppear()
        }
    }
    
    private func onAppear() {
        Task {
            let route = try? await RoutingUseCase().execute(req: [
                (lat: 40.383362, lng: 71.779100),
                (lat: 40.394022, lng: 71.800740)
            ])
            
            await MainActor.run {
                self.coords = route?.routing ?? []
            }
        }
    }
}


private struct _TestView: View {
    var body: some View {
        TestView()
    }
}

#Preview(body: {
    _TestView()
})
