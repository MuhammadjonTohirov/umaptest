//
//  TestView.swift
//  umaptest
//
//  Created by applebro on 27/05/25.
//

import Foundation
import SwiftUI

struct SwitchView<Label: View>: View {
    @Binding var isOn: Bool
    @ViewBuilder var label: () -> Label
    var body: some View {
        Toggle(isOn: $isOn, label: label)
            .tint(Color.iPrimary)
    }
}


struct TestView: View {
    var body: some View {
        SwitchView(isOn: .constant(true), label: {})
    }
}

#Preview(body: {
    TestView()
})
