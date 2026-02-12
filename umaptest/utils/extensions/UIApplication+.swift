//
//  UIApplication+.swift
//  umaptest
//
//  Created by applebro on 23/05/25.
//

import Foundation
import UIKit

extension UIApplication {
    var safeAreaInsets: UIEdgeInsets {
        connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?
            .safeAreaInsets ?? .zero
    }
}
