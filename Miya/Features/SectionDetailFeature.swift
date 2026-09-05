//
//  SectionDetailFeature.swift
//  Miya
//
//  Created by Steven Hurtado on 7/13/26.
//

import ComposableArchitecture
import SwiftUI

@Reducer
struct SectionDetailFeature {
    /// Debounce before a keystroke turns into a `search` request.
    static let searchDebounce: Duration = .milliseconds(300)

    @ObservableState
    struct State: Equatable, Identifiable {
        var section: HomeSection

        var query: String = ""
        /// Set when this screen was reached by tapping the section's search bar,
        /// so the view focuses the field once (then clears it via `focusConsumed`).
        var autoFocusSearch: Bool = false

        var searchEntries: IdentifiedArrayOf<HomeSectionItem> = []
        var searchAuthors: [AuthorRef] = []
        var searchCursor: String?
        var searchHasMore = false
        var isLoadingSearch = false

        var id: HomeSection.ID { section.id }

        var isSearching: Bool {
            !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }

        /// What the grid renders: server search results while searching, else the
        /// section's items (already album-folded by the server).
        var displayedItems: IdentifiedArrayOf<HomeSectionItem> {
            isSearching ? searchEntries : section.items
        }

        var showsEmptyState: Bool {
            isSearching && !isLoadingSearch && searchEntries.isEmpty && searchAuthors.isEmpty
        }
    }

    enum Action: ViewAction, BindableAction {
        enum View {
            case itemTapped(HomeSectionItem.ID)
            case authorTapped(AuthorRef)
            case reachedEnd
            case focusConsumed
        }
        enum Delegate: Equatable {
            case itemTapped(HomeSectionItem)
            case authorTapped(AuthorRef)
        }
        case view(View)
        case binding(BindingAction<State>)
        case delegate(Delegate)
        case searchResponse(SearchResults, reset: Bool)
        case searchFailed
    }

    private enum CancelID { case search }

    @Dependency(\.homeClient) var homeClient
    @Dependency(\.continuousClock) var clock

    var body: some ReducerOf<Self> {
        BindingReducer()
        Reduce { state, action in
            switch action {
            case .binding(\.query):
                guard state.isSearching else {
                    state.searchEntries = []
                    state.searchAuthors = []
                    state.searchCursor = nil
                    state.searchHasMore = false
                    state.isLoadingSearch = false
                    return .cancel(id: CancelID.search)
                }
                state.isLoadingSearch = true
                return .run { [query = state.query, sectionID = state.section.id] send in
                    try await clock.sleep(for: Self.searchDebounce)
                    let results = try await homeClient.search(query, sectionID, nil)
                    await send(.searchResponse(results, reset: true))
                } catch: { error, send in
                    if !(error is CancellationError) {
                        reportIssue(error, "HomeClient.search failed")
                        await send(.searchFailed)
                    }
                }
                .cancellable(id: CancelID.search, cancelInFlight: true)

            case .view(.reachedEnd):
                guard state.isSearching,
                      !state.isLoadingSearch,
                      state.searchHasMore,
                      let cursor = state.searchCursor
                else { return .none }
                state.isLoadingSearch = true
                return .run { [query = state.query, sectionID = state.section.id] send in
                    let results = try await homeClient.search(query, sectionID, cursor)
                    await send(.searchResponse(results, reset: false))
                } catch: { error, send in
                    reportIssue(error, "HomeClient.search (page) failed")
                    await send(.searchFailed)
                }
                .cancellable(id: CancelID.search, cancelInFlight: true)

            case let .searchResponse(results, reset):
                state.isLoadingSearch = false
                if reset {
                    state.searchEntries = results.entries.elements
                } else {
                    let fresh = results.entries.elements.filter { state.searchEntries[id: $0.id] == nil }
                    state.searchEntries.append(contentsOf: fresh)
                }
                state.searchAuthors = results.authors
                state.searchCursor = results.entries.cursor
                state.searchHasMore = results.entries.hasMore
                return .none

            case .searchFailed:
                state.isLoadingSearch = false
                state.searchHasMore = false
                return .none

            case let .view(.itemTapped(id)):
                let source = state.isSearching ? state.searchEntries : state.section.items
                guard let item = source[id: id] else { return .none }
                return .send(.delegate(.itemTapped(item)))

            case let .view(.authorTapped(ref)):
                return .send(.delegate(.authorTapped(ref)))

            case .view(.focusConsumed):
                state.autoFocusSearch = false
                return .none

            case .binding, .delegate:
                return .none
            }
        }
    }
}

@ViewAction(for: SectionDetailFeature.self)
struct SectionDetailView: View {
    @Bindable var store: StoreOf<SectionDetailFeature>

    /// Space to reserve at the bottom for a collapsed media preview floating over this
    /// screen, so its last row is never hidden behind the mini bar. `nil` when no preview
    /// is collapsed.
    var collapsedPreviewHeight: CGFloat?

    @FocusState private var searchFocused: Bool

    private static let detailCardSize = 116.0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Header — matches HomeView's in-list large title
                Text(store.section.title).font(.largeTitle)

                SearchField(
                    text: $store.query,
                    placeholder: "Search \(store.section.title)",
                    isFocused: $searchFocused
                )

                if !store.searchAuthors.isEmpty {
                    VStack(spacing: 8) {
                        ForEach(store.searchAuthors) { author in
                            AuthorRow(name: author.name) {
                                send(.authorTapped(author))
                            }
                        }
                    }
                }

                if store.showsEmptyState {
                    Text("No results")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 24)
                }

                LazyVGrid(columns: .justifiedTriple, spacing: 16) {
                    ForEach(Array(store.displayedItems.enumerated()), id: \.element.id) { index, item in
                        Button {
                            send(.itemTapped(item.id))
                        } label: {
                            if item.kind == .album {
                                StackedCoverCard(item: item, size: Self.detailCardSize)
                            } else {
                                PreviewCard(item: item, size: Self.detailCardSize)
                            }
                        }
                        .buttonStyle(.plain)
                        .onAppear {
                            if store.isSearching, index >= store.displayedItems.count - 4 {
                                send(.reachedEnd)
                            }
                        }
                    }
                }

                if store.isSearching, store.searchHasMore {
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
        .task {
            guard store.autoFocusSearch else { return }
            try? await Task.sleep(for: .milliseconds(300))
            searchFocused = true
            send(.focusConsumed)
        }
    }
}

#Preview {
    NavigationStack {
        SectionDetailView(
            store: Store(
                initialState: SectionDetailFeature.State(section: HomeSection.mocks[0])
            ) {
                SectionDetailFeature()
            } withDependencies: {
                $0.homeClient = .previewValue
            }
        )
    }
}
