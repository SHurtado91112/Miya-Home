//
//  HomeSectionItem+Collapsing.swift
//  Miya
//
//  Created by Steven Hurtado on 9/5/26.
//

import ComposableArchitecture

extension IdentifiedArray
where Element == HomeSectionItem, ID == HomeSectionItem.ID {
    /// Drops song/photo tiles whose `albumID` resolves to an album in `albums`;
    /// the album's own `.album` tile is kept and stands in for them. Order is
    /// otherwise preserved. An `.album` tile is never dropped (its `albumID` is nil).
    func collapsingAlbumMembers(against albums: IdentifiedArrayOf<Album>) -> Self {
        IdentifiedArray(
            uniqueElements: filter { item in
                guard let albumID = item.albumID else { return true }
                return albums[id: albumID] == nil
            }
        )
    }
}
