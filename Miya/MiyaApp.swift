//
//  MiyaApp.swift
//  Miya
//
//  Created by Steven Hurtado on 7/13/26.
//

import SwiftUI

@main
struct MiyaApp: App {
    init() {
        BarButtonAppearance.configure()
    }

    var body: some Scene {
        WindowGroup {
            ContentView().environment(\.font, .body)
        }
    }
}
