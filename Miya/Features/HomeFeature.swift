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
    /// Number of section items rendered on the Home screen before the grid
    /// switches its final cell to a "More" affordance.
    static let previewLimit = 5

    @Reducer
    enum Path {
        case sectionDetail(SectionDetailFeature)
    }

    @ObservableState
    struct State: Equatable {
        var title: String
        var sections: IdentifiedArrayOf<HomeSection>
        var path = StackState<Path.State>()

        init(
            title: String,
            sections: IdentifiedArrayOf<HomeSection> = []
        ) {
            self.title = title
            self.sections = sections
        }
    }

    enum Action: ViewAction {
        enum View {
            case onAppear
            case moreTapped(sectionID: HomeSection.ID)
        }
        case view(View)
        case sectionsResponse(IdentifiedArrayOf<HomeSection>)
        case path(StackActionOf<Path>)
    }

    @Dependency(\.homeClient) var homeClient

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .view(.onAppear):
                guard state.sections.isEmpty else { return .none }
                return .run { send in
                    await send(.sectionsResponse(try await homeClient.loadSections()))
                } catch: { error, _ in
                    reportIssue(error, "HomeClient.loadSections failed")
                }

            case let .sectionsResponse(sections):
                state.sections = sections
                return .none

            case let .view(.moreTapped(sectionID)):
                guard let section = state.sections[id: sectionID] else { return .none }
                state.path.append(.sectionDetail(SectionDetailFeature.State(section: section)))
                return .none

            case .path:
                return .none
            }
        }
        .forEach(\.path, action: \.path)
    }
}

extension HomeFeature.Path.State: Equatable {}

struct HomeSectionItem: Identifiable, Equatable, Codable {
    var id: String
    var title: String
    var subtitle: String
    var systemImage: String
    var detail: String
    var imageURL: URL?
}

struct HomeSection: Identifiable, Equatable, Codable {
    var id: String
    var title: String
    var items: IdentifiedArrayOf<HomeSectionItem>
}
