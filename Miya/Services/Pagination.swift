//
//  Pagination.swift
//  Miya
//
//  A generic "one page of a Relay connection" value, shared by `HomeClient`,
//  the GraphQL DTO conversions, and the detail-grid reducers that append pages
//  as the user scrolls.
//

import ComposableArchitecture
import Foundation

/// One page of a paginated collection: the elements plus the cursor and
/// has-more flag needed to request the next page.
///
/// Backed by `IdentifiedArrayOf` so that appending a page de-duplicates by id
/// if a server cursor happens to overlap the previous page's tail.
struct Page<Element: Identifiable & Equatable & Sendable>: Equatable, Sendable {
    var elements: IdentifiedArrayOf<Element>
    var cursor: String?
    var hasMore: Bool

    static var empty: Page { Page(elements: [], cursor: nil, hasMore: false) }
}
