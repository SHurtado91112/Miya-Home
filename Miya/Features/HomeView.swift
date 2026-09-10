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
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Sign Out", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) {
                            send(.signOutTapped)
                        }
                    } label: {
                        Image(systemName: "person.crop.circle")
                    }
                    .barButtonFont()
                    .accessibilityLabel("Account")
                }
            }
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
        .overlay(alignment: .bottom) {
            if let previewStore = store.scope(state: \.preview, action: \.preview.presented),
               previewStore.expandedKind == nil {
                MediaPreviewBarsView(store: previewStore)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.snappy, value: store.preview?.dockedKinds)
        .sheet(item: expandedPreview) { previewStore in
            MediaPreviewView(store: previewStore)
        }
    }

    /// The preview store, but only while a preview is expanded full screen — so
    /// the sheet presents for the expanded view only and the mini bars stay a
    /// plain overlay.
    private var expandedPreview: Binding<StoreOf<MediaPreview>?> {
        Binding(
            get: {
                guard let previewStore = store.scope(state: \.preview, action: \.preview.presented),
                      previewStore.expandedKind != nil
                else { return nil }
                return previewStore
            },
            // No-op: the sheet is a pure projection of `expandedKind`. Dragging
            // the sheet down to its mini detent flips `expandedKind` to nil,
            // which dismisses the sheet on its own while the preview lives on as
            // a docked bar. Tearing down `state.preview` here would wrongly kill
            // the minimized preview on every collapse. A genuine close runs
            // through the mini bar's `.closed` delegate instead.
            set: { _ in }
        )
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
