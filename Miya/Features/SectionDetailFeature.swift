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
        @Presents var preview: MediaPreview.State?
        var id: HomeSection.ID { section.id }
    }

    enum Action: ViewAction {
        enum View {
            case itemTapped(HomeSectionItem.ID)
        }
        case view(View)
        case preview(PresentationAction<MediaPreview.Action>)
    }

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case let .view(.itemTapped(id)):
                guard let item = state.section.items[id: id] else { return .none }
                state.preview = MediaPreview.state(for: item)
                return .none

            case .preview:
                return .none
            }
        }
        .ifLet(\.$preview, action: \.preview)
    }
}

@ViewAction(for: SectionDetailFeature.self)
struct SectionDetailView: View {
    @Bindable var store: StoreOf<SectionDetailFeature>

    private static let detailCardSize = 116.0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Header — matches HomeView's in-list large title
                Text(store.section.title).font(.largeTitle)

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: Self.detailCardSize), spacing: 16)],
                    spacing: 16
                ) {
                    ForEach(store.section.items) { item in
                        Button {
                            send(.itemTapped(item.id))
                        } label: {
                            PreviewCard(item: item, size: Self.detailCardSize)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(16)
        }
        .scrollClipDisabled()
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .serifBackButton()
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
    NavigationStack {
        SectionDetailView(
            store: Store(
                initialState: SectionDetailFeature.State(section: HomeSection.mocks[0])
            ) {
                SectionDetailFeature()
            }
        )
    }
}
