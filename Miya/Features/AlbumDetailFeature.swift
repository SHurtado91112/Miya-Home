//
//  AlbumDetailFeature.swift
//  Miya
//
//  Created by Steven Hurtado on 7/13/26.
//

import ComposableArchitecture
import SwiftUI

@Reducer
struct AlbumDetailFeature {
    @ObservableState
    struct State: Equatable, Identifiable {
        var album: Album
        var isLoadingMore = false
        var id: Album.ID { album.id }
    }

    enum Action: ViewAction {
        enum View {
            case itemTapped(HomeSectionItem.ID)
            case reachedEnd
        }
        enum Delegate: Equatable {
            case itemTapped(HomeSectionItem)
            case didPaginate
        }
        case view(View)
        case delegate(Delegate)
        case pageLoaded(Page<HomeSectionItem>)
        case pageLoadFailed
    }

    private enum CancelID { case paginate }

    @Dependency(\.homeClient) var homeClient

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case let .view(.itemTapped(id)):
                guard let item = state.album.items[id: id] else { return .none }
                return .send(.delegate(.itemTapped(item)))

            case .view(.reachedEnd):
                guard !state.isLoadingMore,
                      state.album.itemsHasMore,
                      let cursor = state.album.itemsCursor
                else { return .none }
                state.isLoadingMore = true
                return .run { [nodeID = state.album.nodeID] send in
                    let page = try await homeClient.loadAlbumItems(albumNodeID: nodeID, after: cursor)
                    await send(.pageLoaded(page))
                } catch: { error, send in
                    reportIssue(error, "HomeClient.loadAlbumItems failed")
                    await send(.pageLoadFailed)
                }
                .cancellable(id: CancelID.paginate, cancelInFlight: true)

            case let .pageLoaded(page):
                state.isLoadingMore = false
                state.album.items.append(contentsOf: page.elements)
                state.album.itemsCursor = page.cursor
                state.album.itemsHasMore = page.hasMore
                return .send(.delegate(.didPaginate))

            case .pageLoadFailed:
                state.isLoadingMore = false
                return .none

            case .delegate:
                return .none
            }
        }
    }
}

@ViewAction(for: AlbumDetailFeature.self)
struct AlbumDetailView: View {
    @Bindable var store: StoreOf<AlbumDetailFeature>

    /// Space to reserve at the bottom for a collapsed media preview floating over this
    /// screen, so its last row is never hidden behind the mini bar. `nil` when no preview
    /// is collapsed.
    var collapsedPreviewHeight: CGFloat?

    private static let detailCardSize = 116.0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Header — matches HomeView's in-list large title
                Text(store.album.title).font(.largeTitle)

                LazyVGrid(columns: .justifiedTriple, spacing: 16) {
                    ForEach(Array(store.album.items.enumerated()), id: \.element.id) { index, item in
                        Button {
                            send(.itemTapped(item.id))
                        } label: {
                            PreviewCard(item: item, size: Self.detailCardSize)
                        }
                        .buttonStyle(.plain)
                        .onAppear {
                            if index >= store.album.items.count - 4 { send(.reachedEnd) }
                        }
                    }
                }

                if store.album.itemsHasMore {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                        .onAppear { send(.reachedEnd) }
                }
            }
            .padding(16)
        }
        .scrollClipDisabled()
        .safeAreaInset(edge: .bottom) {
            if let collapsedPreviewHeight {
                Color.clear.frame(height: collapsedPreviewHeight)
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .serifBackButton()
    }
}

#Preview {
    NavigationStack {
        AlbumDetailView(
            store: Store(
                initialState: AlbumDetailFeature.State(album: Album.mocks[0])
            ) {
                AlbumDetailFeature()
            } withDependencies: {
                $0.homeClient = .previewValue
            }
        )
    }
}
