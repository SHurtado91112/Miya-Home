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
                ForEach(store.visibleSections) { section in
                    Section(section.title) {
                        LazyVGrid(columns: .justifiedTriple, spacing: 16) {
                            ForEach(section.items.prefix(HomeFeature.previewLimit)) { item in
                                Button {
                                    send(.itemTapped(id: item.id))
                                } label: {
                                    if item.kind == .album, let album = store.albums[id: item.id] {
                                        StackedCoverCard(album: album)
                                    } else {
                                        PreviewCard(item: item)
                                    }
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
            .refreshable {
                await send(.refreshed).finish()
            }
            .safeAreaInset(edge: .bottom) {
                if let height = store.preview?.collapsedHeight {
                    Color.clear.frame(height: height)
                }
            }
            .onAppear { send(.onAppear) }
        } destination: { pathStore in
            switch pathStore.case {
            case let .sectionDetail(sectionStore):
                SectionDetailView(store: sectionStore, collapsedPreviewHeight: store.preview?.collapsedHeight)
            case let .albumDetail(albumStore):
                AlbumDetailView(store: albumStore, collapsedPreviewHeight: store.preview?.collapsedHeight)
            }
        }
        .tint(.primary)
        .sheet(
            item: $store.scope(state: \.preview, action: \.preview)
        ) { store in
            switch store.case {
            case let .song(store):
                SongPreviewView(store: store)
            case let .photo(store):
                PhotoPreviewView(store: store)
            }
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
