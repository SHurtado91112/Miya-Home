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
        var albumsCursor: String? = nil
        var albumsHasMore: Bool = false
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
    }

    enum Action: ViewAction {
        enum View {
            case onAppear
            case moreTapped(sectionID: HomeSection.ID)
            case itemTapped(id: HomeSectionItem.ID)
        }
        case view(View)
        case sectionsResponse(IdentifiedArrayOf<HomeSection>)
        case albumsResponse(Page<Album>)
        case albumFetched(Album)
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
                    async let albums = homeClient.loadAlbums(nil)
                    let (loadedSections, loadedAlbums) = try await (sections, albums)
                    await send(.sectionsResponse(loadedSections))
                    await send(.albumsResponse(loadedAlbums))
                } catch: { error, _ in
                    reportIssue(error, "HomeClient.loadSections/loadAlbums failed")
                }

            case let .sectionsResponse(sections):
                state.sections = sections
                return .none

            case let .albumsResponse(page):
                state.albums = page.elements
                state.albumsCursor = page.cursor
                state.albumsHasMore = page.hasMore
                return .none

            case let .albumFetched(album):
                state.albums[id: album.id] = album
                let alreadyOnPath = state.path.contains { pathState in
                    guard case let .albumDetail(albumDetailState) = pathState else { return false }
                    return albumDetailState.album.id == album.id
                }
                if !alreadyOnPath {
                    state.path.append(.albumDetail(AlbumDetailFeature.State(album: album)))
                }
                return .none

            case let .view(.moreTapped(sectionID)):
                guard let section = state.sections[id: sectionID] else { return .none }
                state.path.append(.sectionDetail(SectionDetailFeature.State(section: section)))
                return .none

            case let .view(.itemTapped(id)):
                guard let item = state.sections.lazy.compactMap({ $0.items[id: id] }).first
                else { return .none }
                return openItem(item, state: &state)

            case let .path(.element(id: _, action: .sectionDetail(.delegate(.itemTapped(item))))):
                return openItem(item, state: &state)

            case let .path(.element(id: _, action: .albumDetail(.delegate(.itemTapped(item))))):
                return openItem(item, state: &state)

            case let .path(.element(id: elementID, action: .albumDetail(.delegate(.didPaginate)))):
                // Keep the parent's album cache in step with the pages the user
                // has scrolled through, so a re-push / "view album" sees them.
                if case let .albumDetail(child) = state.path[id: elementID] {
                    state.albums[id: child.album.id] = child.album
                }
                return .none

            case let .preview(.presented(.song(.delegate(.viewAlbumTapped(albumID))))):
                if var songState = state.preview?.song {
                    songState.detent = SongPreviewFeature.miniDetent
                    state.preview = .song(songState)
                }
                return openAlbum(albumID, state: &state)

            case let .preview(.presented(.photo(.delegate(.viewAlbumTapped(albumID))))):
                if var photoState = state.preview?.photo {
                    photoState.detent = PhotoPreviewFeature.miniDetent
                    state.preview = .photo(photoState)
                }
                return openAlbum(albumID, state: &state)

            case .path, .preview:
                return .none
            }
        }
        .forEach(\.path, action: \.path)
        .ifLet(\.$preview, action: \.preview)
    }

    private func openItem(_ item: HomeSectionItem, state: inout State) -> Effect<Action> {
        switch item.kind {
        case .album:
            if let album = state.albums[id: item.id] {
                state.path.append(.albumDetail(AlbumDetailFeature.State(album: album)))
                return .none
            }
            // Not in the loaded `albums` page — resolve it by its Relay id.
            guard let nodeID = item.albumNodeID else { return .none }
            return .run { send in
                await send(.albumFetched(try await homeClient.loadAlbumNode(nodeID: nodeID)))
            } catch: { error, _ in
                reportIssue(error, "HomeClient.loadAlbumNode failed")
            }
        case .song, .photo:
            state.preview = MediaPreview.state(for: item)
            return .none
        }
    }

    private func openAlbum(_ albumID: Album.ID, state: inout State) -> Effect<Action> {
        let albumAlreadyOnPath = state.path.contains { pathState in
            guard case let .albumDetail(albumDetailState) = pathState else { return false }
            return albumDetailState.album.id == albumID
        }
        guard !albumAlreadyOnPath, let album = state.albums[id: albumID] else { return .none }
        state.path.append(.albumDetail(AlbumDetailFeature.State(album: album)))
        return .none
    }
}

extension HomeFeature.Path.State: Equatable {}

enum MediaKind: String, Codable, Equatable {
    case song
    case photo
    case album
}

struct HomeSectionItem: Identifiable, Equatable, Codable, Sendable {
    var id: String
    var kind: MediaKind
    var title: String
    var subtitle: String
    var systemImage: String
    var detail: String
    var imageURL: URL?
    var albumID: Album.ID?
    /// Relay global id of the album this item *is*, when `kind == .album`. Lets a
    /// tap resolve an album that isn't in the loaded `albums` page via `node(id:)`.
    /// Server-only; absent from the bundled JSON fixtures (see `CodingKeys`).
    var albumNodeID: String? = nil

    private enum CodingKeys: String, CodingKey {
        case id, kind, title, subtitle, systemImage, detail, imageURL, albumID
    }
}

struct HomeSection: Identifiable, Equatable, Codable, Sendable {
    var id: String
    var title: String
    var items: IdentifiedArrayOf<HomeSectionItem>
}

struct Album: Identifiable, Equatable, Codable, Sendable {
    var id: String
    var title: String
    var subtitle: String
    var systemImage: String
    var imageURL: URL?
    var items: IdentifiedArrayOf<HomeSectionItem>
    /// Relay global id, used to page this album's items via `node(id:)`. See the
    /// note on `HomeSection` re: the omitted `CodingKeys`.
    var nodeID: String = ""
    var itemsCursor: String? = nil
    var itemsHasMore: Bool = false

    private enum CodingKeys: String, CodingKey {
        case id, title, subtitle, systemImage, imageURL, items
    }
}
