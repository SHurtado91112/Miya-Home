//
//  MiyaApp.swift
//  Miya
//
//  Created by Steven Hurtado on 7/13/26.
//

import SwiftUI

@main
struct MiyaApp: App {
    func names() {
        print(UIFont.familyNames.sorted())
    }

    var body: some Scene {
        WindowGroup {
            ContentView().environment(\.font, .body).onAppear {
                names()
            }
        }
    }
}
