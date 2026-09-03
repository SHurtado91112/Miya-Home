//
//  NavigationBarButton.swift
//  Miya
//
//  Created by Steven Hurtado on 7/13/26.
//

import SwiftUI

extension Font {
    /// The font every navigation bar button uses. Apply it to a toolbar button's
    /// label with `.barButtonFont()`; the leading back button gets it via
    /// `.serifBackButton()`.
    static var barButton: Font { .custom(fontName, size: 17) }
}

extension View {
    /// Styles a toolbar button's label to match the app's bar typography.
    /// Use on any `ToolbarItem` content so every bar button reads the same.
    func barButtonFont() -> some View {
        font(.barButton)
    }

    /// Replaces the system back button with one that uses the app's serif font.
    /// SwiftUI's `NavigationStack` renders its own bar and ignores the
    /// `UINavigationBar.appearance()` / `UIBarButtonItem.appearance()` proxies,
    /// so the back button has to be supplied as SwiftUI toolbar content.
    func serifBackButton() -> some View {
        modifier(SerifBackButton())
    }
}

private struct SerifBackButton: ViewModifier {
    @Environment(\.dismiss) private var dismiss

    func body(content: Content) -> some View {
        content
            .navigationBarBackButtonHidden(true)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: { dismiss() }) {
                        HStack(spacing: 5) {
                            Image(systemName: "chevron.backward")
                                .font(.system(size: 17, weight: .semibold))
                            Text("Back").barButtonFont()
                        }
                    }
                    .tint(.primary)
                }
            }
    }
}
