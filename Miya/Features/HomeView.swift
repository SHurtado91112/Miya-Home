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
                Text(store.title).font(.largeTitle)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))

                // Sections (album members are folded server-side)
                ForEach(store.sections) { section in
                    Section {
                        SearchBarButton(placeholder: "Search \(section.title)") {
                            send(.searchTapped(sectionID: section.id))
                        }
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 8, trailing: 0))

                        SectionCardGrid(naturalCardSize: PreviewCard.cardSize) { cardSize in
                            ForEach(section.items.prefix(HomeFeature.previewLimit)) { item in
                                Button {
                                    send(.itemTapped(id: item.id))
                                } label: {
                                    if item.kind == .album {
                                        StackedCoverCard(item: item, size: cardSize)
                                    } else {
                                        PreviewCard(item: item, size: cardSize)
                                    }
                                }
                                .buttonStyle(.plain)
                            }

                            if section.items.count > HomeFeature.previewLimit {
                                Button {
                                    send(.moreTapped(sectionID: section.id))
                                } label: {
                                    MoreCard(size: cardSize)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 8, trailing: 0))
                    } header: {
                        Text(section.title)
                            .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 8, trailing: 0))
                    }
                    .font(.headline).textCase(nil).listRowSeparator(.hidden)
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
            case let .authorDetail(authorStore):
                AuthorDetailView(store: authorStore, collapsedPreviewHeight: store.preview?.collapsedHeight)
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
