//
//  MediaPreview.swift
//  Miya
//
//  Created by Steven Hurtado on 7/13/26.
//

import ComposableArchitecture
import SwiftUI

/// The floating preview presented when a section item is tapped. Holds up to one
/// song and one photo at once — opening a photo never dismisses a pending song
/// preview (and vice versa). At most one may be expanded; the rest render as
/// stacked mini bars, and tapping a bar expands that one.
@Reducer
struct MediaPreview {
    /// Room one docked mini bar takes — a little over its rendered height, used
    /// to reserve bottom space in scrolling content behind the bars.
    static let barHeight: CGFloat = 76
    static let barSpacing: CGFloat = 8

    @ObservableState
    struct State: Equatable, Identifiable {
        var song: SongPreviewFeature.State?
        var photo: PhotoPreviewFeature.State?

        enum Kind: Equatable { case song, photo }

        // A single container ⇒ a constant id: present while non-nil, dismiss when nil.
        var id: String { "media-preview" }

        var isEmpty: Bool { song == nil && photo == nil }

        /// The preview currently expanded to `.large`, if any. Driven purely by
        /// the children's `detent`, so dragging a sheet down to its mini detent
        /// drops straight back to the docked bar stack.
        var expandedKind: Kind? {
            if song?.detent == .large { return .song }
            if photo?.detent == .large { return .photo }
            return nil
        }

        /// The mini bars docked at the bottom right now, top-to-bottom.
        var dockedKinds: [Kind] {
            guard expandedKind == nil else { return [] }
            var kinds: [Kind] = []
            if photo != nil { kinds.append(.photo) }
            if song != nil { kinds.append(.song) }
            return kinds
        }

        /// Height the stacked mini bars occupy — the space scrolling content must
        /// reserve at the bottom so nothing hides behind them. `nil` while a
        /// preview is expanded (its sheet covers the screen).
        var collapsedHeight: CGFloat? {
            let n = dockedKinds.count
            guard n > 0 else { return nil }
            return CGFloat(n) * MediaPreview.barHeight
                + CGFloat(n - 1) * MediaPreview.barSpacing
        }

        /// Collapse every present preview to its mini bar — used when navigating
        /// away (to an album or author) so the sheet doesn't cover the pushed screen.
        mutating func minimize() {
            song?.detent = SongPreviewFeature.miniDetent
            photo?.detent = PhotoPreviewFeature.miniDetent
        }
    }

    enum Action {
        case song(SongPreviewFeature.Action)
        case photo(PhotoPreviewFeature.Action)
    }

    @Dependency(\.dismiss) var dismiss

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .song(.view(.expandTapped)):
                state.photo?.detent = PhotoPreviewFeature.miniDetent
                return .none

            case .photo(.view(.expandTapped)):
                state.song?.detent = SongPreviewFeature.miniDetent
                return .none

            case .song(.delegate(.closed)):
                state.song = nil
                return state.isEmpty ? .run { _ in await dismiss() } : .none

            case .photo(.delegate(.closed)):
                state.photo = nil
                return state.isEmpty ? .run { _ in await dismiss() } : .none

            case .song, .photo:
                return .none
            }
        }
        .ifLet(\.song, action: \.song) { SongPreviewFeature() }
        .ifLet(\.photo, action: \.photo) { PhotoPreviewFeature() }
    }
}

extension MediaPreview {
    /// Fold a freshly tapped item into the preview state, keeping any preview of
    /// the *other* kind alive. Returns `existing` unchanged for a `.album` item.
    ///
    /// `siblings` is the list the item was tapped in (an album's tracks, a
    /// section's items, a set of search results); its songs become the play
    /// queue, so ⏮ / ⏭ and auto-advance walk exactly what the user was looking at.
    static func opening(
        _ item: HomeSectionItem,
        siblings: IdentifiedArrayOf<HomeSectionItem> = [],
        into existing: State?
    ) -> State? {
        var state = existing ?? State()
        switch item.kind {
        case .song:
            state.song = SongPreviewFeature.State(   // detent == .large
                item: item,
                queue: queue(for: item, in: siblings)
            )
            state.photo?.detent = PhotoPreviewFeature.miniDetent
        case .photo:
            state.photo = PhotoPreviewFeature.State(item: item)
            state.song?.detent = SongPreviewFeature.miniDetent
        case .album:
            return existing
        }
        return state
    }

    /// The songs of `siblings`, in display order. Falls back to the item alone
    /// when it isn't in that list — a stale grid, or a tap with no list context.
    private static func queue(
        for item: HomeSectionItem,
        in siblings: IdentifiedArrayOf<HomeSectionItem>
    ) -> IdentifiedArrayOf<HomeSectionItem> {
        let songs = IdentifiedArray(uniqueElements: siblings.filter { $0.kind == .song })
        return songs[id: item.id] == nil ? [item] : songs
    }
}

/// The expanded (full-screen) preview — presented as a sheet by `HomeView` only
/// while `expandedKind != nil`. The mini bars are a plain overlay
/// (`MediaPreviewBarsView`), so they carry no sheet chrome or drop shadow.
struct MediaPreviewView: View {
    let store: StoreOf<MediaPreview>

    var body: some View {
        switch store.expandedKind {
        case .song:
            if let songStore = store.scope(state: \.song, action: \.song) {
                // With a photo also open, swiping down minimizes to the bar stack
                // (via the mini detent) rather than discarding both previews.
                SongPreviewView(store: songStore)
                    .interactiveDismissDisabled(store.photo != nil)
            }
        case .photo:
            if let photoStore = store.scope(state: \.photo, action: \.photo) {
                PhotoPreviewView(store: photoStore)
                    .interactiveDismissDisabled(store.song != nil)
            }
        case .none:
            EmptyView()
        }
    }
}

/// The stacked mini bars, docked at the bottom over the app content. A plain
/// overlay — no sheet, so no grouped shadow / border around the pair.
struct MediaPreviewBarsView: View {
    let store: StoreOf<MediaPreview>

    var body: some View {
        VStack(spacing: MediaPreview.barSpacing) {
            if let photoStore = store.scope(state: \.photo, action: \.photo) {
                PhotoMiniBar(store: photoStore)
            }
            if let songStore = store.scope(state: \.song, action: \.song) {
                SongMiniBar(store: songStore)
            }
        }
    }
}

#Preview("Docked song + photo bars") {
    MediaPreviewBarsView(
        store: Store(
            initialState: MediaPreview.State(
                song: SongPreviewFeature.State(
                    item: HomeSection.mocks[0].items[0],
                    detent: SongPreviewFeature.miniDetent
                ),
                photo: PhotoPreviewFeature.State(
                    item: HomeSection.mocks[1].items[0],
                    detent: PhotoPreviewFeature.miniDetent
                )
            )
        ) { MediaPreview() }
    )
    .padding()
    .frame(maxHeight: .infinity, alignment: .bottom)
}
