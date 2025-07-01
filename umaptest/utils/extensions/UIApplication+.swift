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
        windows.first?.safeAreaInsets ?? .zero
    }
}

extension UIScreen {
    static var screenSize: CGSize {
        return UIScreen.main.bounds.size
    }
    
    static var screenWidth: CGFloat {
        return UIScreen.main.bounds.width
    }
    
    static var screenHeight: CGFloat {
        return UIScreen.main.bounds.height
    }
}
