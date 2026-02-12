//
//  umaptestApp.swift
//  umaptest
//
//  Created by applebro on 22/05/25.
//

import SwiftUI

@main
struct UmaptestApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .onAppear {
                    AppSetup.setup()
                }
        }
    }
}
