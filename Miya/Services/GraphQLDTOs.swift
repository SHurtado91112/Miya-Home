//
//  GraphQLDTOs.swift
//  Miya
//
//  Decode-only types for the MiyaServer GraphQL API, kept separate from the
//  domain `Codable` models in HomeFeature.swift so the bundled-JSON fallback
//  path is unaffected by the server's field naming/shape.
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

/// A `SectionEntry` union member (Song | Photo | Album) flattened into one
/// decode target, discriminated by `__typename`.
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
    let items: [GQLSectionEntry]
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
    let albums: [GQLAlbum]
}

extension GQLSectionEntry {
    /// `detail` is absent on GraphQL `Album`; `albumID` isn't requested by
    /// this minimal query (would need a nested `album { slug }` selection).
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
            albumID: nil
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
            items: IdentifiedArray(uniqueElements: items.map { $0.toHomeSectionItem() })
        )
    }
}
