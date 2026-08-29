//
//  HomeView.swift
//  Miya
//
//  Created by Steven Hurtado on 7/13/26.
//

import ComposableArchitecture
import SwiftUI

@ViewAction(for: HomeFeature.self)
struct HomeView: View {
    let store: StoreOf<HomeFeature>

    var body: some View {
        List {
            // Header
            Text(store.title).font(.largeTitle).listRowSeparator(.hidden)

            // Sections
            ForEach(store.sections) { section in
                Section(section.title) {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: PreviewCard.cardSize))]) {
                        ForEach(section.items) { _ in
                            PreviewCard(text: "Hello")
                        }
                    }
                }.font(.headline).textCase(nil).listRowSeparator(.hidden)
            }
        }
        .listStyle(.grouped)
        .scrollContentBackground(.hidden)
        .listSectionSpacing(32)
        .padding(16)
        .scrollClipDisabled()
        .onAppear { send(.onAppear) }
    }
}

#Preview {
    HomeView(
        store: Store(initialState: HomeFeature.State(title: "Miya")) {
            HomeFeature()
        }
    )
}
