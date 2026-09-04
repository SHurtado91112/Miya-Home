//
//  MediaPreview.swift
//  Miya
//
//  Created by Steven Hurtado on 7/13/26.
//

import ComposableArchitecture

/// The preview presented when a section item is tapped, shared by the Home grid
/// and the section detail grid. Songs open a Now-Playing sheet; photos open a
/// full-screen viewer.
@Reducer
enum MediaPreview {
    case song(SongPreviewFeature)
    case photo(PhotoPreviewFeature)
}

extension MediaPreview.State: Equatable {}

extension MediaPreview {
    static func state(for item: HomeSectionItem) -> MediaPreview.State {
        switch item.kind {
        case .song: .song(SongPreviewFeature.State(item: item))
        case .photo: .photo(PhotoPreviewFeature.State(item: item))
        }
    }
}
