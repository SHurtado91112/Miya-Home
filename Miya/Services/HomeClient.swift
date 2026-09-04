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
    var loadAlbums: @Sendable () async throws -> IdentifiedArrayOf<Album>
}

extension HomeClient: DependencyKey {
    static let liveValue = HomeClient {
        guard let url = Bundle.main.url(forResource: "home_sections", withExtension: "json") else {
            throw HomeClientError.resourceMissing
        }
        let data = try Data(contentsOf: url)
        let sections = try JSONDecoder().decode([HomeSection].self, from: data)
        return IdentifiedArray(uniqueElements: sections)
    } loadAlbums: {
        guard let url = Bundle.main.url(forResource: "albums", withExtension: "json") else {
            throw HomeClientError.resourceMissing
        }
        let data = try Data(contentsOf: url)
        let albums = try JSONDecoder().decode([Album].self, from: data)
        return IdentifiedArray(uniqueElements: albums)
    }

    static let previewValue = HomeClient {
        IdentifiedArray(uniqueElements: HomeSection.mocks)
    } loadAlbums: {
        IdentifiedArray(uniqueElements: Album.mocks)
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
            })
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
            })
        ),
    ]
}
