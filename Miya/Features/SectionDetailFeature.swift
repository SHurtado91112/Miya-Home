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
    @ObservableState
    struct State: Equatable, Identifiable {
        var section: HomeSection
        var albums: IdentifiedArrayOf<Album> = []
        var id: HomeSection.ID { section.id }

        /// `section.items` with album-member tiles hidden; the album's own tile stands in.
        var visibleItems: IdentifiedArrayOf<HomeSectionItem> {
            section.items.collapsingAlbumMembers(against: albums)
        }
    }

    enum Action: ViewAction {
        enum View {
            case itemTapped(HomeSectionItem.ID)
        }
        enum Delegate: Equatable {
            case itemTapped(HomeSectionItem)
        }
        case view(View)
        case delegate(Delegate)
    }

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case let .view(.itemTapped(id)):
                guard let item = state.section.items[id: id] else { return .none }
                return .send(.delegate(.itemTapped(item)))

            case .delegate:
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

    private static let detailCardSize = 116.0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Header — matches HomeView's in-list large title
                Text(store.section.title).font(.largeTitle)

                LazyVGrid(
                    columns: [GridItem(
                        .adaptive(minimum: Self.detailCardSize, maximum: Self.detailCardSize),
                        spacing: 16
                    )],
                    alignment: .leading,
                    spacing: 16
                ) {
                    ForEach(store.visibleItems) { item in
                        Button {
                            send(.itemTapped(item.id))
                        } label: {
                            if item.kind == .album, let album = store.albums[id: item.id] {
                                StackedCoverCard(album: album, size: Self.detailCardSize)
                            } else {
                                PreviewCard(item: item, size: Self.detailCardSize)
                            }
                        }
                        .buttonStyle(.plain)
                    }
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
        SectionDetailView(
            store: Store(
                initialState: SectionDetailFeature.State(
                section: HomeSection.mocks[0],
                albums: IdentifiedArray(uniqueElements: Album.mocks)
            )
            ) {
                SectionDetailFeature()
            }
        )
    }
}
