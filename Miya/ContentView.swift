//
//  ContentView.swift
//  Miya
//
//  Created by Steven Hurtado on 7/13/26.
//

import SwiftUI

struct ContentView: View {
    let model = HomeModel(title: "Miya")
    var body: some View {
        HomeView(model: model)
    }
}

#Preview {
    ContentView()
}
