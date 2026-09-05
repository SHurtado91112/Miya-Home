//
//  GraphQLDTOs.swift
//  Miya
//
//  Decode-only types for the MiyaServer GraphQL API, kept separate from the
//  domain `Codable` models in HomeFeature.swift so the bundled-JSON fallback
//  path is unaffected by the server's field naming/shape.
//
//  Pagination: the server exposes `albums` and `Album.items` as Relay cursor
//  connections. `sections` and `Section.items` are plain unpaginated lists, so
//  only the album-side DTOs carry connection wrappers.
//

import ComposableArchitecture
import Foundation

struct GraphQLResponse<T: Decodable>: Decodable {
    let data: T?
    let errors: [GraphQLErrorDTO]?
}

struct GraphQLErrorDTO: Decodable {
    let message: String
}

struct GraphQLRequestError: LocalizedError {
    let messages: [String]
    var errorDescription: String? { messages.joined(separator: "; ") }
}

// MARK: - Relay connection DTOs

struct GQLConnection<Node: Decodable>: Decodable {
    let edges: [GQLEdge<Node>]
    let pageInfo: GQLPageInfo
    var nodes: [Node] { edges.map(\.node) }
}

struct GQLEdge<Node: Decodable>: Decodable {
    let node: Node
    let cursor: String
}

struct GQLPageInfo: Decodable {
    let hasNextPage: Bool
    let endCursor: String?
}

// MARK: - Entity DTOs

/// A `SectionEntry` union member (Song | Photo | Album) flattened into one
/// decode target, discriminated by `__typename`. `id` is the Relay global id,
/// `slug` the human id the app uses as its domain `id`.
struct GQLSectionEntry: Decodable {
    let __typename: String
    let id: String
    let slug: String
    let title: String
    let subtitle: String
    let systemImage: String
    let detail: String?
    let imageUrl: String?
}

struct GQLAlbum: Decodable {
    let id: String
    let slug: String
    let title: String
    let subtitle: String
    let systemImage: String
    let imageUrl: String?
    let items: GQLConnection<GQLSectionEntry>
}

struct GQLSection: Decodable {
    let id: String
    let slug: String
    let title: String
    let items: [GQLSectionEntry]
}

struct SectionsQueryData: Decodable {
    let sections: [GQLSection]
}

struct AlbumsQueryData: Decodable {
    let albums: GQLConnection<GQLAlbum>
}

/// `node(id:)` narrowed to an Album's items connection — used to append a page
/// of items to an open album detail grid.
struct GQLAlbumItemsNode: Decodable {
    let items: GQLConnection<GQLSectionEntry>?
}

struct AlbumItemsQueryData: Decodable {
    let node: GQLAlbumItemsNode?
}

/// `node(id:)` narrowed to a full Album — the cache-miss fallback for tapping an
/// album that wasn't in the loaded `albums` page.
struct GQLAlbumNode: Decodable {
    let __typename: String
    let id: String
    let slug: String
    let title: String
    let subtitle: String
    let systemImage: String
    let imageUrl: String?
    let items: GQLConnection<GQLSectionEntry>
}

struct AlbumNodeQueryData: Decodable {
    let node: GQLAlbumNode?
}

// MARK: - DTO -> domain

extension GQLSectionEntry {
    /// `detail` is absent on `Album`. `albumID` (the parent album of a song/photo)
    /// still isn't requested here — a separate gap. `albumNodeID` carries the Relay
    /// global id for album entries so a tap can resolve an album that isn't in the
    /// loaded `albums` page via `node(id:)`.
    func toHomeSectionItem() -> HomeSectionItem {
        let kind: MediaKind
        switch __typename {
        case "Song": kind = .song
        case "Photo": kind = .photo
        case "Album": kind = .album
        default: kind = .song
        }
        return HomeSectionItem(
            id: slug,
            kind: kind,
            title: title,
            subtitle: subtitle,
            systemImage: systemImage,
            detail: detail ?? "",
            imageURL: imageUrl.flatMap(URL.init),
            albumID: nil,
            albumNodeID: kind == .album ? id : nil
        )
    }
}

extension GQLConnection where Node == GQLSectionEntry {
    func toItemPage() -> Page<HomeSectionItem> {
        Page(
            elements: IdentifiedArray(uniqueElements: nodes.map { $0.toHomeSectionItem() }),
            cursor: pageInfo.endCursor,
            hasMore: pageInfo.hasNextPage
        )
    }
}

extension GQLConnection where Node == GQLAlbum {
    func toAlbumPage() -> Page<Album> {
        Page(
            elements: IdentifiedArray(uniqueElements: nodes.map { $0.toAlbum() }),
            cursor: pageInfo.endCursor,
            hasMore: pageInfo.hasNextPage
        )
    }
}

extension GQLSection {
    func toHomeSection() -> HomeSection {
        HomeSection(
            id: slug,
            title: title,
            items: IdentifiedArray(uniqueElements: items.map { $0.toHomeSectionItem() })
        )
    }
}

extension GQLAlbum {
    func toAlbum() -> Album {
        Album(
            id: slug,
            title: title,
            subtitle: subtitle,
            systemImage: systemImage,
            imageURL: imageUrl.flatMap(URL.init),
            items: IdentifiedArray(uniqueElements: items.nodes.map { $0.toHomeSectionItem() }),
            nodeID: id,
            itemsCursor: items.pageInfo.endCursor,
            itemsHasMore: items.pageInfo.hasNextPage
        )
    }
}

extension GQLAlbumNode {
    func toAlbum() -> Album {
        Album(
            id: slug,
            title: title,
            subtitle: subtitle,
            systemImage: systemImage,
            imageURL: imageUrl.flatMap(URL.init),
            items: IdentifiedArray(uniqueElements: items.nodes.map { $0.toHomeSectionItem() }),
            nodeID: id,
            itemsCursor: items.pageInfo.endCursor,
            itemsHasMore: items.pageInfo.hasNextPage
        )
    }
}
