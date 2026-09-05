//
//  MiyaGraphQLClient.swift
//  Miya
//
//  Minimal URLSession-based GraphQL client used for on-device testing against
//  a local MiyaServer instance over the LAN. See HomeClient.liveValue, which
//  only routes through here when MIYA_SERVER_URL is set in the run environment.
//
//  Local HTTPS trust: the dev server is expected to serve a mkcert-issued
//  certificate whose root CA has been trusted on the test device, so no
//  custom URLSessionDelegate/pinning is needed here — standard chain
//  validation succeeds once that one-time device trust step is done.
//
//  Pagination: MiyaServer exposes `albums` and `Album.items` as Relay cursor
//  connections (`first`/`after`). `sections` and `Section.items` are plain
//  unpaginated lists. An open album detail grid fetches its next page of items
//  through the Relay `node(id:)` interface keyed on the album's opaque global id.
//

import ComposableArchitecture
import Foundation

struct MiyaGraphQLClient {
    let baseURL: URL

    /// Page size requested from every connection. Must stay `>=`
    /// `HomeFeature.previewLimit` so the Home grid's "More" affordance still has
    /// a full first page to work with.
    static let pageSize = 20

    // MARK: - Queries

    /// Scalar fields shared by every Song / Photo selection. `author` / `album`
    /// are the sub-objects the search filter and the "view album" affordance
    /// need; `GQLSectionEntry` decodes them as optionals.
    private static let mediaFields =
        "id slug title subtitle systemImage detail imageUrl author { id slug name } album { slug }"
    private static let albumEntryFields = "id slug title subtitle systemImage imageUrl"

    /// A `SectionEntry` selection that includes album cards (sections, search).
    private static let sectionEntryNodes = """
              __typename
              ... on Song  { \(mediaFields) }
              ... on Photo { \(mediaFields) }
              ... on Album { \(albumEntryFields) }
    """

    /// A media-only selection (an album's / author's items are songs & photos).
    private static let mediaEntryNodes = """
              __typename
              ... on Song  { \(mediaFields) }
              ... on Photo { \(mediaFields) }
    """

    private static let sectionsQuery = """
    query Sections {
      sections {
        id
        slug
        title
        items {
    \(sectionEntryNodes)
        }
      }
    }
    """

    private static let albumsQuery = """
    query Albums($first: Int!, $after: String) {
      albums(first: $first, after: $after) {
        edges {
          node {
            id
            slug
            title
            subtitle
            systemImage
            imageUrl
            items(first: $first) {
              edges {
                node {
    \(mediaEntryNodes)
                }
                cursor
              }
              pageInfo { hasNextPage endCursor }
            }
          }
          cursor
        }
        pageInfo { hasNextPage endCursor }
      }
    }
    """

    private static let albumItemsQuery = """
    query AlbumItems($id: ID!, $first: Int!, $after: String) {
      node(id: $id) {
        __typename
        ... on Album {
          items(first: $first, after: $after) {
            edges {
              node {
    \(mediaEntryNodes)
              }
              cursor
            }
            pageInfo { hasNextPage endCursor }
          }
        }
      }
    }
    """

    private static let albumNodeQuery = """
    query AlbumNode($id: ID!, $first: Int!) {
      node(id: $id) {
        __typename
        ... on Album {
          id
          slug
          title
          subtitle
          systemImage
          imageUrl
          items(first: $first) {
            edges {
              node {
    \(mediaEntryNodes)
              }
              cursor
            }
            pageInfo { hasNextPage endCursor }
          }
        }
      }
    }
    """

    private static let albumBySlugQuery = """
    query Album($slug: String!, $first: Int!) {
      album(slug: $slug) {
        id
        slug
        title
        subtitle
        systemImage
        imageUrl
        items(first: $first) {
          edges {
            node {
    \(mediaEntryNodes)
            }
            cursor
          }
          pageInfo { hasNextPage endCursor }
        }
      }
    }
    """

    private static let searchQuery = """
    query Search($query: String!, $sectionSlug: String, $first: Int!, $after: String) {
      search(query: $query, sectionSlug: $sectionSlug, first: $first, after: $after) {
        entries {
          edges {
            node {
    \(sectionEntryNodes)
            }
            cursor
          }
          pageInfo { hasNextPage endCursor }
        }
        authors { id slug name }
      }
    }
    """

    private static let authorItemsQuery = """
    query AuthorItems($id: ID!, $first: Int!, $after: String) {
      node(id: $id) {
        __typename
        ... on Author {
          items(first: $first, after: $after) {
            edges {
              node {
    \(mediaEntryNodes)
              }
              cursor
            }
            pageInfo { hasNextPage endCursor }
          }
        }
      }
    }
    """

    // MARK: - Public API

    func loadSections() async throws -> IdentifiedArrayOf<HomeSection> {
        let data: SectionsQueryData = try await execute(Self.sectionsQuery)
        return IdentifiedArray(uniqueElements: data.sections.map { $0.toHomeSection() })
    }

    func loadAlbums(after: String?) async throws -> Page<Album> {
        let data: AlbumsQueryData = try await execute(
            Self.albumsQuery,
            variables: AlbumsVariables(first: Self.pageSize, after: after)
        )
        return data.albums.toAlbumPage()
    }

    /// Next page of an album's items, addressed by the album's Relay global id.
    func loadAlbumItems(albumNodeID: String, after: String?) async throws -> Page<HomeSectionItem> {
        let data: AlbumItemsQueryData = try await execute(
            Self.albumItemsQuery,
            variables: NodeItemsVariables(id: albumNodeID, first: Self.pageSize, after: after)
        )
        guard let items = data.node?.items else {
            throw GraphQLRequestError(messages: ["node(id:) had no Album items for \(albumNodeID)"])
        }
        return items.toItemPage()
    }

    /// Full album + its first page of items, for a tapped album that wasn't in
    /// the loaded `albums` page.
    func loadAlbumNode(nodeID: String) async throws -> Album {
        let data: AlbumNodeQueryData = try await execute(
            Self.albumNodeQuery,
            variables: NodeVariables(id: nodeID, first: Self.pageSize)
        )
        guard let album = data.node else {
            throw GraphQLRequestError(messages: ["node(id:) returned no Album for \(nodeID)"])
        }
        return album.toAlbum()
    }

    /// A single album + its first page of items, addressed by slug. Used to
    /// backfill the albums a section's items reference so `collapsingAlbumMembers`
    /// can hide them (Home only eagerly loads the first `albums` page).
    func loadAlbum(slug: String) async throws -> Album? {
        let data: AlbumBySlugQueryData = try await execute(
            Self.albumBySlugQuery,
            variables: AlbumSlugVariables(slug: slug, first: Self.pageSize)
        )
        return data.album?.toAlbum()
    }

    /// One page of search results (media entries + matched authors), optionally
    /// scoped to a section slug.
    func search(query: String, sectionSlug: String?, after: String?) async throws -> SearchResults {
        let data: SearchQueryData = try await execute(
            Self.searchQuery,
            variables: SearchVariables(
                query: query, sectionSlug: sectionSlug, first: Self.pageSize, after: after
            )
        )
        return data.search.toSearchResults()
    }

    /// Next page of one author's items, addressed by the author's Relay global id.
    func loadAuthorItems(authorNodeID: String, after: String?) async throws -> Page<HomeSectionItem> {
        let data: AuthorItemsQueryData = try await execute(
            Self.authorItemsQuery,
            variables: NodeItemsVariables(id: authorNodeID, first: Self.pageSize, after: after)
        )
        guard let items = data.node?.items else {
            throw GraphQLRequestError(messages: ["node(id:) had no Author items for \(authorNodeID)"])
        }
        return items.toItemPage()
    }

    // MARK: - Transport

    private struct GraphQLRequest<V: Encodable>: Encodable {
        let query: String
        let variables: V
    }

    private struct EmptyVariables: Encodable {}

    private struct AlbumsVariables: Encodable {
        let first: Int
        let after: String?
    }

    private struct NodeItemsVariables: Encodable {
        let id: String
        let first: Int
        let after: String?
    }

    private struct NodeVariables: Encodable {
        let id: String
        let first: Int
    }

    private struct SearchVariables: Encodable {
        let query: String
        let sectionSlug: String?
        let first: Int
        let after: String?
    }

    private struct AlbumSlugVariables: Encodable {
        let slug: String
        let first: Int
    }

    private func execute<V: Encodable, T: Decodable>(
        _ query: String,
        variables: V
    ) async throws -> T {
        var request = URLRequest(url: baseURL.appendingPathComponent("graphql"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(GraphQLRequest(query: query, variables: variables))

        let (responseData, _) = try await URLSession.shared.data(for: request)
        let decoded = try JSONDecoder().decode(GraphQLResponse<T>.self, from: responseData)

        if let errors = decoded.errors, !errors.isEmpty {
            throw GraphQLRequestError(messages: errors.map(\.message))
        }
        guard let data = decoded.data else {
            throw GraphQLRequestError(messages: ["GraphQL response had no data"])
        }
        return data
    }

    private func execute<T: Decodable>(_ query: String) async throws -> T {
        try await execute(query, variables: EmptyVariables())
    }
}
