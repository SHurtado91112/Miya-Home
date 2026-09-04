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
    @Bindable var store: StoreOf<HomeFeature>

    var body: some View {
        NavigationStack(path: $store.scope(state: \.path, action: \.path)) {
            List {
                // Header
                Text(store.title).font(.largeTitle).listRowSeparator(.hidden)

                // Sections
                ForEach(store.sections) { section in
                    Section(section.title) {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: PreviewCard.cardSize))]) {
                            ForEach(section.items.prefix(HomeFeature.previewLimit)) { item in
                                Button {
                                    send(.itemTapped(id: item.id))
                                } label: {
                                    PreviewCard(item: item)
                                }
                                .buttonStyle(.plain)
                            }

                            if section.items.count > HomeFeature.previewLimit {
                                Button {
                                    send(.moreTapped(sectionID: section.id))
                                } label: {
                                    MoreCard()
                                }
                                .buttonStyle(.plain)
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
        } destination: { store in
            switch store.case {
            case let .sectionDetail(store):
                SectionDetailView(store: store)
            }
        }
        .tint(.primary)
        .sheet(
            item: $store.scope(state: \.preview?.song, action: \.preview.song)
        ) { store in
            SongPreviewView(store: store)
        }
        .fullScreenCover(
            item: $store.scope(state: \.preview?.photo, action: \.preview.photo)
        ) { store in
            PhotoPreviewView(store: store)
        }
    }
}

#Preview {
    HomeView(
        store: Store(initialState: HomeFeature.State(title: "Miya")) {
            HomeFeature()
        } withDependencies: {
            $0.homeClient = .previewValue
        }
    )
}
