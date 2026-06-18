//
//  UIKitMapDemoScreen.swift
//  umaptest
//
//  Bridges the pure-UIKit `UIKitMapDemoViewController` into SwiftUI so it can be
//  presented from `ContentView` (the app is otherwise SwiftUI-based).
//

import SwiftUI

struct UIKitMapDemoScreen: UIViewControllerRepresentable {
    var onClose: () -> Void

    func makeUIViewController(context: Context) -> UINavigationController {
        let demo = UIKitMapDemoViewController()
        demo.onClose = onClose
        return UINavigationController(rootViewController: demo)
    }

    func updateUIViewController(_ uiViewController: UINavigationController, context: Context) {}
}
