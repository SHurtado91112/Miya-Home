//
//  HomeClient.swift
//  Miya
//
//  Created by Steven Hurtado on 7/13/26.
//

import ComposableArchitecture
import Foundation

/// Loads the Home screen's sections. Backed by a bundled JSON mock today; swap
/// `liveValue` for a network/persistence implementation when real data exists.
@DependencyClient
struct HomeClient: Sendable {
    var loadSections: @Sendable () async throws -> IdentifiedArrayOf<HomeSection>
    var loadAlbums: @Sendable (_ after: String?) async throws -> Page<Album>
    /// Next page of an album's items, keyed on the album's Relay global id.
    var loadAlbumItems: @Sendable (_ albumNodeID: String, _ after: String?) async throws -> Page<HomeSectionItem>
    /// Full album + its first page of items, for tapping an album that wasn't in
    /// the loaded `albums` page.
    var loadAlbumNode: @Sendable (_ nodeID: String) async throws -> Album
}

extension HomeClient: DependencyKey {
    /// When `MIYA_SERVER_URL` is set in the run environment (see the Debug scheme's
    /// LaunchAction), fetch live data from a local MiyaServer over the LAN instead
    /// of the bundled JSON fixtures. Used for on-device testing.
    private static var serverURL: URL? {
        ProcessInfo.processInfo.environment["MIYA_SERVER_URL"].flatMap(URL.init)
    }

    private static func bundledSections() throws -> [HomeSection] {
        guard let url = Bundle.main.url(forResource: "home_sections", withExtension: "json") else {
            throw HomeClientError.resourceMissing
        }
        return try JSONDecoder().decode([HomeSection].self, from: Data(contentsOf: url))
    }

    private static func bundledAlbums() throws -> [Album] {
        guard let url = Bundle.main.url(forResource: "albums", withExtension: "json") else {
            throw HomeClientError.resourceMissing
        }
        return try JSONDecoder().decode([Album].self, from: Data(contentsOf: url))
    }

    static let liveValue = HomeClient {
        if let serverURL {
            return try await MiyaGraphQLClient(baseURL: serverURL).loadSections()
        }
        return IdentifiedArray(uniqueElements: try bundledSections())
    } loadAlbums: { after in
        if let serverURL {
            return try await MiyaGraphQLClient(baseURL: serverURL).loadAlbums(after: after)
        }
        // Bundled fixtures aren't paginated — return everything as a single page.
        return Page(
            elements: IdentifiedArray(uniqueElements: try bundledAlbums()),
            cursor: nil,
            hasMore: false
        )
    } loadAlbumItems: { albumNodeID, after in
        if let serverURL {
            return try await MiyaGraphQLClient(baseURL: serverURL)
                .loadAlbumItems(albumNodeID: albumNodeID, after: after)
        }
        // The bundled fixtures aren't paginated (an album's `itemsHasMore` is
        // never set), so this is unreachable in practice.
        return .empty
    } loadAlbumNode: { nodeID in
        if let serverURL {
            return try await MiyaGraphQLClient(baseURL: serverURL).loadAlbumNode(nodeID: nodeID)
        }
        throw HomeClientError.resourceMissing
    }

    static let previewValue = HomeClient {
        IdentifiedArray(uniqueElements: HomeSection.mocks)
    } loadAlbums: { _ in
        Page(elements: IdentifiedArray(uniqueElements: Album.mocks), cursor: nil, hasMore: false)
    } loadAlbumItems: { albumNodeID, after in
        Album.mockItemPage(albumNodeID: albumNodeID, after: after)
    } loadAlbumNode: { nodeID in
        Album.mocks.first { $0.nodeID == nodeID }
            ?? Album(
                id: nodeID,
                title: "Album",
                subtitle: "Preview",
                systemImage: "square.stack",
                imageURL: nil,
                items: []
            )
    }
}

enum HomeClientError: Error {
    case resourceMissing
}

extension DependencyValues {
    var homeClient: HomeClient {
        get { self[HomeClient.self] }
        set { self[HomeClient.self] = newValue }
    }
}

extension HomeSection {
    /// Lightweight fixtures for previews and tests. The shipped mock data lives in
    /// `Miya/Resources/home_sections.json` and is exercised through `HomeClient.liveValue`.
    static let mocks: [HomeSection] = [
        HomeSection(
            id: "music",
            title: "Music",
            items: IdentifiedArray(uniqueElements: (1...8).map { index in
                HomeSectionItem(
                    id: "track-\(index)",
                    kind: .song,
                    title: "Track \(index)",
                    subtitle: "Artist \(index)",
                    systemImage: "music.note",
                    detail: "Preview fixture track number \(index).",
                    imageURL: index == 7
                        ? nil
                        : URL(string: "https://picsum.photos/seed/miya-track-\(index)/600"),
                    albumID: (index == 3 || index == 4) ? Album.mockAlbumID : nil
                )
            } + [
                HomeSectionItem(
                    id: Album.mockAlbumID,
                    kind: .album,
                    title: "In Rainbows",
                    subtitle: "Radiohead",
                    systemImage: "square.stack",
                    detail: "A preview fixture album.",
                    imageURL: URL(string: "https://picsum.photos/seed/miya-in-rainbows/600")
                ),
            ])
        ),
        HomeSection(
            id: "photos",
            title: "Photos",
            items: IdentifiedArray(uniqueElements: (1...7).map { index in
                HomeSectionItem(
                    id: "photo-\(index)",
                    kind: .photo,
                    title: "Photo \(index)",
                    subtitle: "Yesterday",
                    systemImage: "photo",
                    detail: "Preview fixture photo number \(index).",
                    imageURL: index == 6
                        ? nil
                        : URL(string: "https://picsum.photos/seed/miya-photo-\(index)/800/600"),
                    albumID: (index == 2 || index == 3) ? Album.mockPhotoAlbumID : nil
                )
            } + [
                HomeSectionItem(
                    id: Album.mockPhotoAlbumID,
                    kind: .album,
                    title: "Yesterday",
                    subtitle: "2 photos",
                    systemImage: "square.stack",
                    detail: "A preview fixture photo album.",
                    imageURL: URL(string: "https://picsum.photos/seed/miya-yesterday-album/600")
                ),
            ])
        ),
    ]
}

extension Album {
    static let mockAlbumID = "in-rainbows-album"
    static let mockPhotoAlbumID = "yesterday-album"

    /// Synthetic paged tail for previews: 3 pages of 6 songs, then `hasMore: false`.
    /// `after` is the next-page index encoded as a string (`nil`/`"0"` = first tail page).
    static func mockItemPage(albumNodeID: String, after: String?) -> Page<HomeSectionItem> {
        let pageIndex = Int(after ?? "0") ?? 0
        let base = 100 + pageIndex * 6
        let items = (base ..< base + 6).map { n in
            HomeSectionItem(
                id: "\(albumNodeID)-more-\(n)",
                kind: .song,
                title: "More \(n)",
                subtitle: "Preview",
                systemImage: "music.note",
                detail: "Synthetic page item \(n).",
                imageURL: URL(string: "https://picsum.photos/seed/miya-more-\(n)/600"),
                albumID: nil
            )
        }
        let next = pageIndex + 1
        return Page(
            elements: IdentifiedArray(uniqueElements: items),
            cursor: next < 3 ? "\(next)" : nil,
            hasMore: next < 3
        )
    }

    /// Lightweight fixtures for previews and tests. The shipped mock data lives in
    /// `Miya/Resources/albums.json` and is exercised through `HomeClient.liveValue`.
    static let mocks: [Album] = [
        Album(
            id: mockAlbumID,
            title: "In Rainbows",
            subtitle: "Radiohead",
            systemImage: "square.stack",
            imageURL: URL(string: "https://picsum.photos/seed/miya-in-rainbows/600"),
            items: IdentifiedArray(uniqueElements: [3, 4].map { index in
                HomeSectionItem(
                    id: "track-\(index)",
                    kind: .song,
                    title: "Track \(index)",
                    subtitle: "Artist \(index)",
                    systemImage: "music.note",
                    detail: "Preview fixture track number \(index).",
                    imageURL: URL(string: "https://picsum.photos/seed/miya-track-\(index)/600"),
                    albumID: mockAlbumID
                )
            }),
            nodeID: "node-\(mockAlbumID)",
            itemsCursor: "0",
            itemsHasMore: true
        ),
        Album(
            id: mockPhotoAlbumID,
            title: "Yesterday",
            subtitle: "2 photos",
            systemImage: "square.stack",
            imageURL: URL(string: "https://picsum.photos/seed/miya-yesterday-album/600"),
            items: IdentifiedArray(uniqueElements: [2, 3].map { index in
                HomeSectionItem(
                    id: "photo-\(index)",
                    kind: .photo,
                    title: "Photo \(index)",
                    subtitle: "Yesterday",
                    systemImage: "photo",
                    detail: "Preview fixture photo number \(index).",
                    imageURL: URL(string: "https://picsum.photos/seed/miya-photo-\(index)/800/600"),
                    albumID: mockPhotoAlbumID
                )
            }),
            nodeID: "node-\(mockPhotoAlbumID)",
            itemsCursor: "0",
            itemsHasMore: true
        ),
    ]
}
