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

import ComposableArchitecture
import Foundation

struct MiyaGraphQLClient {
    let baseURL: URL

    private static let sectionsQuery = """
    query Sections {
      sections {
        id
        slug
        title
        items {
          __typename
          ... on Song  { id slug title subtitle systemImage detail imageUrl }
          ... on Photo { id slug title subtitle systemImage detail imageUrl }
          ... on Album { id slug title subtitle systemImage imageUrl }
        }
      }
    }
    """

    private static let albumsQuery = """
    query Albums {
      albums {
        id
        slug
        title
        subtitle
        systemImage
        imageUrl
        items {
          __typename
          ... on Song  { id slug title subtitle systemImage detail imageUrl }
          ... on Photo { id slug title subtitle systemImage detail imageUrl }
        }
      }
    }
    """

    func loadSections() async throws -> IdentifiedArrayOf<HomeSection> {
        let data: SectionsQueryData = try await execute(query: Self.sectionsQuery)
        return IdentifiedArray(uniqueElements: data.sections.map { $0.toHomeSection() })
    }

    func loadAlbums() async throws -> IdentifiedArrayOf<Album> {
        let data: AlbumsQueryData = try await execute(query: Self.albumsQuery)
        return IdentifiedArray(uniqueElements: data.albums.map { $0.toAlbum() })
    }

    private func execute<T: Decodable>(query: String) async throws -> T {
        var request = URLRequest(url: baseURL.appendingPathComponent("graphql"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(["query": query])

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
}
