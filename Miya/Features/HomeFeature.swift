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
        case authorDetail(AuthorDetailFeature)
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
            case refreshed
            case moreTapped(sectionID: HomeSection.ID)
            case searchTapped(sectionID: HomeSection.ID)
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

    private enum CancelID { case sections }

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

            case .view(.refreshed):
                return .run { send in
                    let sections = try await homeClient.loadSections()
                    await send(.sectionsResponse(sections))
                } catch: { error, _ in
                    reportIssue(error, "HomeClient.loadSections failed on refresh")
                }
                .cancellable(id: CancelID.sections, cancelInFlight: true)

            case let .sectionsResponse(sections):
                state.sections = sections
                return .none

            case let .albumsResponse(page):
                state.albums = page.elements
                state.albumsCursor = page.cursor
                state.albumsHasMore = page.hasMore
                return .none

            case let .albumFetched(album):
                return showAlbumDetail(album, state: &state)

            case let .view(.moreTapped(sectionID)):
                return pushSectionDetail(sectionID, autoFocusSearch: false, state: &state)

            case let .view(.searchTapped(sectionID)):
                return pushSectionDetail(sectionID, autoFocusSearch: true, state: &state)

            case let .view(.itemTapped(id)):
                guard let section = state.sections.first(where: { $0.items[id: id] != nil }),
                      let item = section.items[id: id]
                else { return .none }
                // The whole section, not just the `previewLimit` cards on screen.
                return openItem(item, siblings: section.items, state: &state)

            case let .path(.element(id: elementID, action: .sectionDetail(.delegate(.itemTapped(item))))):
                return openItem(item, siblings: siblings(at: elementID, state: state), state: &state)

            case let .path(.element(id: _, action: .sectionDetail(.delegate(.authorTapped(ref))))):
                return showAuthorDetail(ref, state: &state)

            case let .path(.element(id: _, action: .albumDetail(.delegate(.authorTapped(ref))))):
                return showAuthorDetail(ref, state: &state)

            case let .path(.element(id: elementID, action: .albumDetail(.delegate(.itemTapped(item))))):
                return openItem(item, siblings: siblings(at: elementID, state: state), state: &state)

            case let .path(.element(id: elementID, action: .authorDetail(.delegate(.itemTapped(item))))):
                return openItem(item, siblings: siblings(at: elementID, state: state), state: &state)

            case let .path(.element(id: _, action: .authorDetail(.delegate(.albumTapped(album))))):
                return showAlbumDetail(album, state: &state)

            case .path(.element(id: _, action: .authorDetail(.delegate(.didPaginate)))):
                // No author cache on HomeFeature.State to keep in step (unlike
                // albumDetail). If one is added later, sync it here.
                return .none

            case let .path(.element(id: elementID, action: .albumDetail(.delegate(.didPaginate)))):
                // Keep the parent's album cache in step with the pages the user
                // has scrolled through, so a re-push / "view album" sees them.
                if case let .albumDetail(child) = state.path[id: elementID] {
                    state.albums[id: child.album.id] = child.album
                }
                return .none

            case let .preview(.presented(.song(.delegate(.viewAlbumTapped(albumID))))):
                state.preview?.minimize()
                return openAlbum(albumID, state: &state)

            case let .preview(.presented(.photo(.delegate(.viewAlbumTapped(albumID))))):
                state.preview?.minimize()
                return openAlbum(albumID, state: &state)

            case let .preview(.presented(.song(.delegate(.authorTapped(ref))))):
                state.preview?.minimize()
                return showAuthorDetail(ref, state: &state)

            case let .preview(.presented(.photo(.delegate(.authorTapped(ref))))):
                state.preview?.minimize()
                return showAuthorDetail(ref, state: &state)

            case .path, .preview:
                return .none
            }
        }
        .forEach(\.path, action: \.path)
        .ifLet(\.$preview, action: \.preview) { MediaPreview() }
    }

    private func pushSectionDetail(
        _ sectionID: HomeSection.ID,
        autoFocusSearch: Bool,
        state: inout State
    ) -> Effect<Action> {
        guard let section = state.sections[id: sectionID] else { return .none }
        state.path.append(
            .sectionDetail(
                SectionDetailFeature.State(section: section, autoFocusSearch: autoFocusSearch)
            )
        )
        return .none
    }

    /// Navigate to an author library screen. If that author is already on the
    /// stack, pop back to it rather than pushing a duplicate (or dead-ending);
    /// otherwise push a fresh screen. Shared by the section-search `AuthorRow`,
    /// the album-detail subheader, and the media-preview author line.
    private func showAuthorDetail(_ ref: AuthorRef, state: inout State) -> Effect<Action> {
        if let existingID = state.path.ids.first(where: { id in
            guard case let .authorDetail(authorState) = state.path[id: id] else { return false }
            return authorState.author.id == ref.id
        }) {
            state.path.pop(to: existingID)
        } else {
            state.path.append(.authorDetail(AuthorDetailFeature.State(author: ref)))
        }
        return .none
    }

    /// Navigate to an album detail screen from an already-resolved `Album`. If
    /// that album is already on the stack (e.g. it also turns up as a search
    /// result), pop back to it rather than pushing a duplicate; otherwise push a
    /// fresh screen. Also refreshes the album cache.
    private func showAlbumDetail(_ album: Album, state: inout State) -> Effect<Action> {
        state.albums[id: album.id] = album
        if let existingID = state.path.ids.first(where: { id in
            guard case let .albumDetail(albumState) = state.path[id: id] else { return false }
            return albumState.album.id == album.id
        }) {
            state.path.pop(to: existingID)
        } else {
            state.path.append(.albumDetail(AlbumDetailFeature.State(album: album)))
        }
        return .none
    }

    /// The list a tapped item came from, read back off the stack element that
    /// reported it — so the three detail features keep their one-item delegate
    /// payload and only this reducer knows about queues.
    private func siblings(
        at elementID: StackElementID,
        state: State
    ) -> IdentifiedArrayOf<HomeSectionItem> {
        switch state.path[id: elementID] {
        case let .albumDetail(child): return child.album.items
        case let .authorDetail(child): return child.items
        // Honours the active search: queue what the grid is actually showing.
        case let .sectionDetail(child): return child.displayedItems
        case .none: return []
        }
    }

    private func openItem(
        _ item: HomeSectionItem,
        siblings: IdentifiedArrayOf<HomeSectionItem> = [],
        state: inout State
    ) -> Effect<Action> {
        switch item.kind {
        case .album:
            if let album = state.albums[id: item.id] {
                return showAlbumDetail(album, state: &state)
            }
            // Not in the loaded `albums` page — resolve it by its Relay id.
            guard let nodeID = item.albumNodeID else { return .none }
            return .run { send in
                await send(.albumFetched(try await homeClient.loadAlbumNode(nodeID: nodeID)))
            } catch: { error, _ in
                reportIssue(error, "HomeClient.loadAlbumNode failed")
            }
        case .photo:
            // Fold into any existing preview so a pending song/photo of the
            // other kind stays alive.
            state.preview = MediaPreview.opening(item, into: state.preview)
            return .none
        case .song:
            state.preview = MediaPreview.opening(item, siblings: siblings, into: state.preview)
            // Present first, then start: the player effect belongs to the child
            // reducer, not to a view, so it survives collapsing the sheet back
            // to the mini bar (which tears `SongPreviewView` down).
            return .send(.preview(.presented(.song(.start))))
        }
    }

    private func openAlbum(_ albumID: Album.ID, state: inout State) -> Effect<Action> {
        guard let album = state.albums[id: albumID] else { return .none }
        return showAlbumDetail(album, state: &state)
    }
}

extension HomeFeature.Path.State: Equatable {}

enum MediaKind: String, Codable, Equatable {
    case song
    case photo
    case album
}

/// A person credited on a media item -- the artist for a song, the photographer
/// for a photo. `id` is the stable slug the app keys on; `nodeID` is the Relay
/// global id used to page `AuthorDetailFeature` via `node(id:)` and is
/// server-only (omitted from `CodingKeys`, empty in the JSON-fixture path).
struct AuthorRef: Identifiable, Equatable, Hashable, Codable, Sendable {
    var id: String
    var name: String
    var nodeID: String = ""

    private enum CodingKeys: String, CodingKey {
        case id, name
    }
}

struct HomeSectionItem: Identifiable, Equatable, Codable, Sendable {
    var id: String
    var kind: MediaKind
    var title: String
    var subtitle: String
    var systemImage: String
    var detail: String
    var imageURL: URL?
    /// A small (longest edge ~512) derivative of `imageURL`, served from
    /// `/media/{id}/thumb`. Server-only; `nil` in the JSON fixtures. Use it for
    /// grid cards, cover fans, and mini bars; `imageURL` for full-screen art.
    var thumbnailURL: URL? = nil
    var albumID: Album.ID?
    /// The item's credited author (song artist / photographer). Populated from
    /// the server's `author { id slug name }`; may be present in the JSON
    /// fixtures as `{ "id", "name" }`.
    var author: AuthorRef?
    /// Relay global id of the album this item *is*, when `kind == .album`. Lets a
    /// tap resolve an album that isn't in the loaded `albums` page via `node(id:)`.
    /// Server-only; absent from the bundled JSON fixtures (see `CodingKeys`).
    var albumNodeID: String? = nil
    /// For `kind == .album`: a few member cover URLs (`items(first: 3)`) so the
    /// grid can render the fanned `StackedCoverCard` without loading the full
    /// album. Server-provided thumbnails when available; server-only.
    var coverPreviewURLs: [URL] = []
    /// For `kind == .song`: an absolute, Range-capable stream URL (`/media/{id}`),
    /// which is what lets `AVPlayer` seek without downloading the whole file.
    /// Server-only, and `nil` even there for a song with no ingested audio file —
    /// `AudioTrack.init(item:…)` falls back to a bundled test track.
    var audioURL: URL? = nil
    /// Track length in seconds when the server knows it. `nil` ⇒ read it off the
    /// `AVPlayerItem` once it's ready to play.
    var duration: TimeInterval? = nil

    /// Thumbnail if the server sent one, else the full image — the URL to use
    /// wherever the item renders small (grid card, cover fan, mini bar).
    var smallImageURL: URL? { thumbnailURL ?? imageURL }

    private enum CodingKeys: String, CodingKey {
        case id, kind, title, subtitle, systemImage, detail, imageURL, albumID, author
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
    /// The album's credited author (album artist / photographer). Populated from
    /// the server's `author { id slug name }`; present in the JSON fixtures as
    /// `{ "id", "name" }`. Drives the tappable author subheader on album detail.
    var author: AuthorRef? = nil
    var systemImage: String
    var imageURL: URL?
    /// A small derivative of `imageURL` (see `HomeSectionItem.thumbnailURL`).
    /// Server-only; `nil` in the JSON fixtures.
    var thumbnailURL: URL? = nil
    var items: IdentifiedArrayOf<HomeSectionItem>
    /// Relay global id, used to page this album's items via `node(id:)`. These
    /// three are server-only; the `CodingKeys` below omit them so the bundled
    /// JSON fixtures still decode and every `.mocks` literal compiles.
    var nodeID: String = ""
    var itemsCursor: String? = nil
    var itemsHasMore: Bool = false

    /// Thumbnail if the server sent one, else the full cover.
    var smallImageURL: URL? { thumbnailURL ?? imageURL }

    private enum CodingKeys: String, CodingKey {
        case id, title, subtitle, author, systemImage, imageURL, items
    }
}
