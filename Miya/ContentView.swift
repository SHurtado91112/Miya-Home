//
//  ContentView.swift
//  Miya
//
//  Created by Steven Hurtado on 7/13/26.
//

import ComposableArchitecture
import SwiftUI

struct ContentView: View {
    @State var store = Store(initialState: HomeFeature.State(title: "Miya")) {
        HomeFeature()
    }

    var body: some View {
        HomeView(store: store)
    }
}

#Preview {
    ContentView()
}
