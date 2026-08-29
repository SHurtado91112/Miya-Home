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
    @ObservableState
    struct State: Equatable {
        var title: String
        var sections: IdentifiedArrayOf<HomeSection>

        init(
            title: String,
            sections: IdentifiedArrayOf<HomeSection> = HomeFeature.placeholderSections
        ) {
            self.title = title
            self.sections = sections
        }
    }

    enum Action: ViewAction {
        enum View {
            case onAppear
        }
        case view(View)
    }

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .view(.onAppear):
                // Placeholder content is seeded in `State.init`. When real data
                // arrives, load it here through an `@Dependency` client and
                // assign `state.sections`.
                return .none
            }
        }
    }
}

extension HomeFeature {
    static let placeholderSections: IdentifiedArrayOf<HomeSection> = [
        HomeSection(
            id: 0,
            title: "Music",
            items: IdentifiedArray(uniqueElements: (0..<5).map {
                HomeSectionItem(id: $0, data: Data(), metaData: [:])
            })
        ),
        HomeSection(
            id: 1,
            title: "Photos",
            items: IdentifiedArray(uniqueElements: (0..<5).map {
                HomeSectionItem(id: $0, data: Data(), metaData: [:])
            })
        ),
    ]
}

struct HomeSectionItem: Identifiable, Equatable {
    var id: Int
    var data: Data
    var metaData: [String: String]
}

struct HomeSection: Identifiable, Equatable {
    var id: Int
    var title: String
    var items: IdentifiedArrayOf<HomeSectionItem>
}
