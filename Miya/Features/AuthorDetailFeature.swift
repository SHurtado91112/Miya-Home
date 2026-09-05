//
//  AuthorDetailFeature.swift
//  Miya
//
//  A list of every item credited to one author, reached from an `AuthorRow` on
//  a section's search results. Server-backed and paginated (an author's items
//  span albums that were never loaded), modelled on `AlbumDetailFeature`.
//

import ComposableArchitecture
import SwiftUI

@Reducer
struct AuthorDetailFeature {
    @ObservableState
    struct State: Equatable, Identifiable {
        var author: AuthorRef
        var items: IdentifiedArrayOf<HomeSectionItem> = []
        var itemsCursor: String?
        var itemsHasMore = true          // until the first page proves otherwise
        var isLoadingMore = false
        var hasLoadedFirstPage = false
        var id: AuthorRef.ID { author.id }
    }

    enum Action: ViewAction {
        enum View {
            case onAppear
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
            case .view(.onAppear):
                guard !state.hasLoadedFirstPage, !state.isLoadingMore else { return .none }
                state.isLoadingMore = true
                return load(state, after: nil)

            case let .view(.itemTapped(id)):
                guard let item = state.items[id: id] else { return .none }
                return .send(.delegate(.itemTapped(item)))

            case .view(.reachedEnd):
                guard state.hasLoadedFirstPage,
                      !state.isLoadingMore,
                      state.itemsHasMore,
                      let cursor = state.itemsCursor
                else { return .none }
                state.isLoadingMore = true
                return load(state, after: cursor)

            case let .pageLoaded(page):
                state.isLoadingMore = false
                state.hasLoadedFirstPage = true
                // An author's items recur across albums / overlapping pages —
                // append only ids not already present.
                let fresh = page.elements.filter { state.items[id: $0.id] == nil }
                state.items.append(contentsOf: fresh)
                state.itemsCursor = page.cursor
                state.itemsHasMore = page.hasMore
                return .send(.delegate(.didPaginate))

            case .pageLoadFailed:
                state.isLoadingMore = false
                state.hasLoadedFirstPage = true
                state.itemsHasMore = false
                return .none

            case .delegate:
                return .none
            }
        }
    }

    private func load(_ state: State, after cursor: String?) -> Effect<Action> {
        let authorID = state.author.nodeID.isEmpty ? state.author.id : state.author.nodeID
        return .run { send in
            let page = try await homeClient.loadAuthorItems(authorID, cursor)
            await send(.pageLoaded(page))
        } catch: { error, send in
            reportIssue(error, "HomeClient.loadAuthorItems failed")
            await send(.pageLoadFailed)
        }
        .cancellable(id: CancelID.paginate, cancelInFlight: true)
    }
}

@ViewAction(for: AuthorDetailFeature.self)
struct AuthorDetailView: View {
    @Bindable var store: StoreOf<AuthorDetailFeature>

    /// Space to reserve at the bottom for a collapsed media preview floating over
    /// this screen. `nil` when no preview is collapsed.
    var collapsedPreviewHeight: CGFloat?

    private static let detailCardSize = 116.0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(store.author.name).font(.largeTitle)

                LazyVGrid(columns: .justifiedTriple, spacing: 16) {
                    ForEach(Array(store.items.enumerated()), id: \.element.id) { index, item in
                        Button {
                            send(.itemTapped(item.id))
                        } label: {
                            PreviewCard(item: item, size: Self.detailCardSize)
                        }
                        .buttonStyle(.plain)
                        .onAppear {
                            if index >= store.items.count - 4 { send(.reachedEnd) }
                        }
                    }
                }

                if store.itemsHasMore {
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
        .onAppear { send(.onAppear) }
    }
}

#Preview {
    NavigationStack {
        AuthorDetailView(
            store: Store(
                initialState: AuthorDetailFeature.State(
                    author: AuthorRef(id: "radiohead", name: "Radiohead", nodeID: "node-radiohead")
                )
            ) {
                AuthorDetailFeature()
            } withDependencies: {
                $0.homeClient = .previewValue
            }
        )
    }
}
