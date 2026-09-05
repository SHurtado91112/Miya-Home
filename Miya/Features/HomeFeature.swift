//
//  HomeFeature.swift
//  Miya
//
//  Created by Steven Hurtado on 7/13/26.
//

import ComposableArchitecture
import Foundation

@Reducer
struct HomeFeature {
    /// Number of section items rendered on the Home screen before the grid
    /// switches its final cell to a "More" affordance.
    static let previewLimit = 5

    @Reducer
    enum Path {
        case sectionDetail(SectionDetailFeature)
        case albumDetail(AlbumDetailFeature)
    }

    @ObservableState
    struct State: Equatable {
        var title: String
        var sections: IdentifiedArrayOf<HomeSection>
        var albums: IdentifiedArrayOf<Album>
        var path = StackState<Path.State>()
        @Presents var preview: MediaPreview.State?

        init(
            title: String,
            sections: IdentifiedArrayOf<HomeSection> = [],
            albums: IdentifiedArrayOf<Album> = []
        ) {
            self.title = title
            self.sections = sections
            self.albums = albums
        }

        /// `sections` with album-member tiles hidden in each section; the album's
        /// own tile stands in for its members. Observes both `sections` and `albums`.
        var visibleSections: IdentifiedArrayOf<HomeSection> {
            sections.reduce(into: []) { result, section in
                var copy = section
                copy.items = section.items.collapsingAlbumMembers(against: albums)
                result.append(copy)
            }
        }
    }

    enum Action: ViewAction {
        enum View {
            case onAppear
            case moreTapped(sectionID: HomeSection.ID)
            case itemTapped(id: HomeSectionItem.ID)
        }
        case view(View)
        case sectionsResponse(IdentifiedArrayOf<HomeSection>)
        case albumsResponse(IdentifiedArrayOf<Album>)
        case path(StackActionOf<Path>)
        case preview(PresentationAction<MediaPreview.Action>)
    }

    @Dependency(\.homeClient) var homeClient

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .view(.onAppear):
                guard state.sections.isEmpty else { return .none }
                return .run { send in
                    async let sections = homeClient.loadSections()
                    async let albums = homeClient.loadAlbums()
                    let (loadedSections, loadedAlbums) = try await (sections, albums)
                    await send(.sectionsResponse(loadedSections))
                    await send(.albumsResponse(loadedAlbums))
                } catch: { error, _ in
                    reportIssue(error, "HomeClient.loadSections/loadAlbums failed")
                }

            case let .sectionsResponse(sections):
                state.sections = sections
                return .none

            case let .albumsResponse(albums):
                state.albums = albums
                return .none

            case let .view(.moreTapped(sectionID)):
                guard let section = state.sections[id: sectionID] else { return .none }
                state.path.append(
                    .sectionDetail(
                        SectionDetailFeature.State(section: section, albums: state.albums)
                    )
                )
                return .none

            case let .view(.itemTapped(id)):
                guard let item = state.sections.lazy.compactMap({ $0.items[id: id] }).first
                else { return .none }
                openItem(item, state: &state)
                return .none

            case let .path(.element(id: _, action: .sectionDetail(.delegate(.itemTapped(item))))):
                openItem(item, state: &state)
                return .none

            case let .path(.element(id: _, action: .albumDetail(.delegate(.itemTapped(item))))):
                openItem(item, state: &state)
                return .none

            case let .preview(.presented(.song(.delegate(.viewAlbumTapped(albumID))))):
                if var songState = state.preview?.song {
                    songState.detent = SongPreviewFeature.miniDetent
                    state.preview = .song(songState)
                }
                openAlbum(albumID, state: &state)
                return .none

            case let .preview(.presented(.photo(.delegate(.viewAlbumTapped(albumID))))):
                if var photoState = state.preview?.photo {
                    photoState.detent = PhotoPreviewFeature.miniDetent
                    state.preview = .photo(photoState)
                }
                openAlbum(albumID, state: &state)
                return .none

            case .path, .preview:
                return .none
            }
        }
        .forEach(\.path, action: \.path)
        .ifLet(\.$preview, action: \.preview)
    }

    private func openItem(_ item: HomeSectionItem, state: inout State) {
        switch item.kind {
        case .album:
            guard let album = state.albums[id: item.id] else { return }
            state.path.append(.albumDetail(AlbumDetailFeature.State(album: album)))
        case .song, .photo:
            state.preview = MediaPreview.state(for: item)
        }
    }

    private func openAlbum(_ albumID: Album.ID, state: inout State) {
        let albumAlreadyOnPath = state.path.contains { pathState in
            guard case let .albumDetail(albumDetailState) = pathState else { return false }
            return albumDetailState.album.id == albumID
        }
        guard !albumAlreadyOnPath, let album = state.albums[id: albumID] else { return }
        state.path.append(.albumDetail(AlbumDetailFeature.State(album: album)))
    }
}

extension HomeFeature.Path.State: Equatable {}

enum MediaKind: String, Codable, Equatable {
    case song
    case photo
    case album
}

struct HomeSectionItem: Identifiable, Equatable, Codable {
    var id: String
    var kind: MediaKind
    var title: String
    var subtitle: String
    var systemImage: String
    var detail: String
    var imageURL: URL?
    var albumID: Album.ID?
}

struct HomeSection: Identifiable, Equatable, Codable {
    var id: String
    var title: String
    var items: IdentifiedArrayOf<HomeSectionItem>
}

struct Album: Identifiable, Equatable, Codable {
    var id: String
    var title: String
    var subtitle: String
    var systemImage: String
    var imageURL: URL?
    var items: IdentifiedArrayOf<HomeSectionItem>
}
