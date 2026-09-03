//
//  BarButtonAppearance.swift
//  Miya
//
//  Created by Steven Hurtado on 7/13/26.
//

import SwiftUI
import UIKit

extension UIFont {
    /// The font every navigation bar button uses. The back button and any other
    /// `UIBarButtonItem` (title-based) inherit this, so bar typography matches the
    /// rest of the app's custom serif styling.
    static var barButton: UIFont {
        UIFont(name: Font.fontName, size: 17) ?? .preferredFont(forTextStyle: .body)
    }
}

enum BarButtonAppearance {
    /// Applies ``UIFont/barButton`` to the back button and all bar button items.
    /// Call once, before any navigation bar is shown (e.g. from `MiyaApp.init`).
    /// Only touches button typography — nav bar backgrounds stay under SwiftUI's
    /// per-screen control (`.toolbarBackground`).
    static func configure() {
        let attributes: [NSAttributedString.Key: Any] = [.font: UIFont.barButton]

        let items = UIBarButtonItem.appearance()
        items.setTitleTextAttributes(attributes, for: .normal)
        items.setTitleTextAttributes(attributes, for: .highlighted)
        items.setTitleTextAttributes(attributes, for: .disabled)
        items.setTitleTextAttributes(attributes, for: .focused)

        // The back button title is resolved through UINavigationBarAppearance on
        // current iOS, so mirror the font there too — without replacing the
        // background configuration.
        let buttons = UIBarButtonItemAppearance(style: .plain)
        buttons.normal.titleTextAttributes = attributes
        buttons.highlighted.titleTextAttributes = attributes
        buttons.disabled.titleTextAttributes = attributes
        buttons.focused.titleTextAttributes = attributes

        for appearance in [
            UINavigationBar.appearance().standardAppearance,
            UINavigationBar.appearance().compactAppearance,
            UINavigationBar.appearance().scrollEdgeAppearance,
            UINavigationBar.appearance().compactScrollEdgeAppearance,
        ] {
            appearance?.buttonAppearance = buttons
            appearance?.backButtonAppearance = buttons
            appearance?.doneButtonAppearance = buttons
        }
    }
}
