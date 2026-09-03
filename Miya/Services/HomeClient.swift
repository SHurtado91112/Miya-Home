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
}

extension HomeClient: DependencyKey {
    static let liveValue = HomeClient {
        guard let url = Bundle.main.url(forResource: "home_sections", withExtension: "json") else {
            throw HomeClientError.resourceMissing
        }
        let data = try Data(contentsOf: url)
        let sections = try JSONDecoder().decode([HomeSection].self, from: data)
        return IdentifiedArray(uniqueElements: sections)
    }

    static let previewValue = HomeClient {
        IdentifiedArray(uniqueElements: HomeSection.mocks)
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
                    title: "Track \(index)",
                    subtitle: "Artist \(index)",
                    systemImage: "music.note",
                    detail: "Preview fixture track number \(index).",
                    imageURL: index == 7
                        ? nil
                        : URL(string: "https://picsum.photos/seed/miya-track-\(index)/600")
                )
            })
        ),
        HomeSection(
            id: "photos",
            title: "Photos",
            items: IdentifiedArray(uniqueElements: (1...7).map { index in
                HomeSectionItem(
                    id: "photo-\(index)",
                    title: "Photo \(index)",
                    subtitle: "Yesterday",
                    systemImage: "photo",
                    detail: "Preview fixture photo number \(index).",
                    imageURL: index == 6
                        ? nil
                        : URL(string: "https://picsum.photos/seed/miya-photo-\(index)/800/600")
                )
            })
        ),
    ]
}
