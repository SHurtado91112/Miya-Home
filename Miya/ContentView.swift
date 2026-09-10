//
//  ContentView.swift
//  Miya
//
//  Created by Steven Hurtado on 7/13/26.
//

import ComposableArchitecture
import SwiftUI

struct ContentView: View {
    @State var store = Store(initialState: AppFeature.State()) {
        AppFeature()
    }

    var body: some View {
        AppView(store: store)
    }
}

#Preview {
    AppView(
        store: Store(initialState: AppFeature.State()) {
            AppFeature()
        } withDependencies: {
            $0.authClient = .previewValue
            $0.homeClient = .previewValue
        }
    )
}
