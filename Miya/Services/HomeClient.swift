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
    /// One page of search results (media entries + matched authors), optionally
    /// scoped to a section's slug. Fuzzy/typo-tolerant server-side; a plain
    /// case/diacritic-insensitive substring match in the JSON-fixture fallback.
    var search: @Sendable (_ query: String, _ sectionID: HomeSection.ID?, _ after: String?) async throws -> SearchResults
    /// Next page of one author's items, keyed on the author's Relay global id
    /// (or slug in the fixture fallback).
    var loadAuthorItems: @Sendable (_ authorID: String, _ after: String?) async throws -> Page<HomeSectionItem>
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

    private static func fold(_ string: String) -> String {
        string.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }

    /// JSON-fixture fallback for `search`, mirroring the server: substring match
    /// on title / author name / parent-album title over section items, album
    /// cards, and album members — with the same folding rule (a media item whose
    /// parent album is itself a match is dropped; the album card stands in).
    private static func localSearch(query: String, sectionID: HomeSection.ID?) throws -> SearchResults {
        let needle = fold(query).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return .empty }
        func matches(_ value: String?) -> Bool {
            guard let value else { return false }
            return fold(value).contains(needle)
        }

        let albums = try bundledAlbums()
        let albumByID = Dictionary(albums.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let matchedAlbumIDs = Set(
            albums.filter { matches($0.title) || matches($0.subtitle) }.map(\.id)
        )

        let sections = try bundledSections()
        let scoped = sectionID.map { id in sections.filter { $0.id == id } } ?? sections
        let candidates = scoped.flatMap(\.items) + albums.flatMap(\.items)

        var seenEntry = Set<String>()
        var entries: [HomeSectionItem] = []
        var seenAuthor = Set<String>()
        var authors: [AuthorRef] = []
        for item in candidates {
            guard seenEntry.insert(item.id).inserted else { continue }
            if item.kind != .album, let aid = item.albumID, matchedAlbumIDs.contains(aid) {
                continue  // folded into the album card
            }
            let hit = matches(item.title)
                || matches(item.author?.name)
                || matches(item.albumID.flatMap { albumByID[$0]?.title })
                || (item.kind == .album && matchedAlbumIDs.contains(item.id))
            if hit { entries.append(item) }
            if let author = item.author, matches(author.name),
               seenAuthor.insert(author.id).inserted {
                authors.append(author)
            }
        }
        return SearchResults(
            entries: Page(
                elements: IdentifiedArray(uniqueElements: entries), cursor: nil, hasMore: false
            ),
            authors: authors
        )
    }

    private static func localAuthorItems(authorID: String) throws -> Page<HomeSectionItem> {
        let all = try bundledSections().flatMap(\.items) + bundledAlbums().flatMap(\.items)
        var seen = Set<String>()
        let matches = all.filter { item in
            (item.author?.id == authorID || item.author?.nodeID == authorID)
                && seen.insert(item.id).inserted
        }
        return Page(
            elements: IdentifiedArray(uniqueElements: matches), cursor: nil, hasMore: false
        )
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
    } search: { query, sectionID, after in
        if let serverURL {
            return try await MiyaGraphQLClient(baseURL: serverURL)
                .search(query: query, sectionSlug: sectionID, after: after)
        }
        return try localSearch(query: query, sectionID: sectionID)
    } loadAuthorItems: { authorID, after in
        if let serverURL {
            return try await MiyaGraphQLClient(baseURL: serverURL)
                .loadAuthorItems(authorNodeID: authorID, after: after)
        }
        return try localAuthorItems(authorID: authorID)
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
    } search: { query, sectionID, _ in
        let needle = fold(query).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return .empty }
        let sections = sectionID.map { id in HomeSection.mocks.filter { $0.id == id } } ?? HomeSection.mocks
        var seenEntry = Set<String>()
        var entries: [HomeSectionItem] = []
        var seenAuthor = Set<String>()
        var authors: [AuthorRef] = []
        for item in sections.flatMap(\.items) {
            let hay = fold(item.title + " " + (item.author?.name ?? ""))
            if hay.contains(needle), seenEntry.insert(item.id).inserted { entries.append(item) }
            if let author = item.author, fold(author.name).contains(needle),
               seenAuthor.insert(author.id).inserted {
                authors.append(author)
            }
        }
        return SearchResults(
            elements: entries, authors: authors
        )
    } loadAuthorItems: { authorID, after in
        Album.mockAuthorItemPage(authorID: authorID, after: after)
    }
}

extension SearchResults {
    /// Convenience for building an unpaginated preview/fixture result.
    init(elements: [HomeSectionItem], authors: [AuthorRef]) {
        self.init(
            entries: Page(
                elements: IdentifiedArray(uniqueElements: elements), cursor: nil, hasMore: false
            ),
            authors: authors
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
            // The server folds an album's members away, so the mock has none —
            // just standalone tracks plus the album card.
            items: IdentifiedArray(uniqueElements: [1, 2, 5, 6, 7, 8].map { index in
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
                    author: AuthorRef(id: "artist-\(index)", name: "Artist \(index)", nodeID: "node-artist-\(index)")
                )
            } + [
                HomeSectionItem(
                    id: Album.mockAlbumID,
                    kind: .album,
                    title: "In Rainbows",
                    subtitle: "Radiohead",
                    systemImage: "square.stack",
                    detail: "A preview fixture album.",
                    imageURL: URL(string: "https://picsum.photos/seed/miya-in-rainbows/600"),
                    coverPreviewURLs: [3, 4].compactMap {
                        URL(string: "https://picsum.photos/seed/miya-track-\($0)/600")
                    }
                ),
            ])
        ),
        HomeSection(
            id: "photos",
            title: "Photos",
            items: IdentifiedArray(uniqueElements: [1, 4, 5, 6, 7].map { index in
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
                    author: AuthorRef(id: "steven-hurtado", name: "Steven Hurtado", nodeID: "node-steven-hurtado")
                )
            } + [
                HomeSectionItem(
                    id: Album.mockPhotoAlbumID,
                    kind: .album,
                    title: "Yesterday",
                    subtitle: "2 photos",
                    systemImage: "square.stack",
                    detail: "A preview fixture photo album.",
                    imageURL: URL(string: "https://picsum.photos/seed/miya-yesterday-album/600"),
                    coverPreviewURLs: [2, 3].compactMap {
                        URL(string: "https://picsum.photos/seed/miya-photo-\($0)/800/600")
                    }
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

    /// Synthetic paged author library for previews: 3 pages of 6, then `hasMore: false`.
    static func mockAuthorItemPage(authorID: String, after: String?) -> Page<HomeSectionItem> {
        let pageIndex = Int(after ?? "0") ?? 0
        let base = 1 + pageIndex * 6
        let items = (base ..< base + 6).map { n in
            HomeSectionItem(
                id: "\(authorID)-item-\(n)",
                kind: .song,
                title: "By \(authorID) \(n)",
                subtitle: authorID,
                systemImage: "music.note",
                detail: "Synthetic author-library item \(n).",
                imageURL: URL(string: "https://picsum.photos/seed/miya-\(authorID)-\(n)/600"),
                albumID: nil,
                author: AuthorRef(id: authorID, name: authorID, nodeID: authorID)
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
                    albumID: mockAlbumID,
                    author: AuthorRef(id: "radiohead", name: "Radiohead", nodeID: "node-radiohead")
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
                    albumID: mockPhotoAlbumID,
                    author: AuthorRef(id: "steven-hurtado", name: "Steven Hurtado", nodeID: "node-steven-hurtado")
                )
            }),
            nodeID: "node-\(mockPhotoAlbumID)",
            itemsCursor: "0",
            itemsHasMore: true
        ),
    ]
}
