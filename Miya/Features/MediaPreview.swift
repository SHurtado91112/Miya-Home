//
//  MediaPreview.swift
//  Miya
//
//  Created by Steven Hurtado on 7/13/26.
//

import ComposableArchitecture
import SwiftUI

/// The preview presented when a section item is tapped, shared by the Home grid
/// and the section detail grid. Both songs and photos open as a sheet that can be
/// collapsed to a mini bar (rather than dismissed) while the rest of the app stays reachable.
@Reducer
enum MediaPreview {
    case song(SongPreviewFeature)
    case photo(PhotoPreviewFeature)
}

extension MediaPreview.State: Equatable {}

extension MediaPreview.State: Identifiable {
    var id: HomeSectionItem.ID {
        switch self {
        case let .song(state): state.id
        case let .photo(state): state.id
        }
    }
}

extension MediaPreview {
    static func state(for item: HomeSectionItem) -> MediaPreview.State? {
        switch item.kind {
        case .song: .song(SongPreviewFeature.State(item: item))
        case .photo: .photo(PhotoPreviewFeature.State(item: item))
        case .album: nil
        }
    }
}

extension MediaPreview.State {
    /// The space the collapsed mini bar occupies, or `nil` when the preview is fully expanded.
    var collapsedHeight: CGFloat? {
        switch self {
        case let .song(state):
            state.detent == .large ? nil : SongPreviewFeature.miniPlayerHeight
        case let .photo(state):
            state.detent == .large ? nil : PhotoPreviewFeature.miniPlayerHeight
        }
    }
}
