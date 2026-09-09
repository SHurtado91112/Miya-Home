//
//  SongPreviewFeature.swift
//  Miya
//
//  Created by Steven Hurtado on 7/13/26.
//

import ComposableArchitecture
import SwiftUI

@Reducer
struct SongPreviewFeature {
    /// Height of the collapsed "mini player" — tall enough for artwork, title, and transport controls.
    static let miniPlayerHeight: CGFloat = 88
    /// The collapsed "mini player" detent.
    static let miniDetent: PresentationDetent = .height(miniPlayerHeight)
    /// How far into a track ⏮ restarts it instead of stepping back a track —
    /// the convention every music player uses.
    static let restartThreshold: TimeInterval = 3

    @ObservableState
    struct State: Equatable, Identifiable {
        var item: HomeSectionItem
        /// The songs `item` was opened alongside, in display order — the play
        /// queue. Always contains `item`; `[item]` when opened without siblings.
        var queue: IdentifiedArrayOf<HomeSectionItem>
        var isPlaying = false
        var currentTime: TimeInterval = 0
        /// The server's `durationSeconds` until the `AVPlayerItem` reports its own.
        var duration: TimeInterval?
        /// True while the user drags the scrubber, so incoming progress ticks
        /// don't fight the thumb back to where playback actually is.
        var isScrubbing = false
        var detent: PresentationDetent = .large

        var id: HomeSectionItem.ID { item.id }

        init(
            item: HomeSectionItem,
            queue: IdentifiedArrayOf<HomeSectionItem>? = nil,
            detent: PresentationDetent = .large
        ) {
            self.item = item
            self.queue = queue ?? [item]
            self.duration = item.duration
            self.detent = detent
        }

        var nextItem: HomeSectionItem? {
            guard let index = queue.index(id: item.id), index + 1 < queue.count else { return nil }
            return queue[index + 1]
        }

        var previousItem: HomeSectionItem? {
            guard let index = queue.index(id: item.id), index > 0 else { return nil }
            return queue[index - 1]
        }

        /// ⏮ stays enabled at the head of the queue once you're a few seconds in,
        /// because there it restarts the track rather than stepping back.
        var canGoBack: Bool { previousItem != nil || currentTime > SongPreviewFeature.restartThreshold }
    }

    enum Action: ViewAction, BindableAction {
        enum View {
            case playPauseTapped
            case previousTapped
            case nextTapped
            case scrubbingChanged(Bool)
            case expandTapped
            case closeTapped
            case viewAlbumTapped
            case authorTapped(AuthorRef)
        }
        enum Delegate: Equatable {
            case viewAlbumTapped(albumID: Album.ID)
            case authorTapped(AuthorRef)
            /// The user dismissed this preview from its mini bar.
            case closed
        }
        /// Hand `item` to the player and start it. Sent by `HomeFeature` when a
        /// song is opened, and by this reducer on every queue advance.
        case start
        case player(AudioPlayerEvent)
        case view(View)
        case binding(BindingAction<State>)
        case delegate(Delegate)
    }

    @Dependency(\.audioPlayer) var audioPlayer

    private enum CancelID { case player }

    var body: some ReducerOf<Self> {
        BindingReducer()
        Reduce { state, action in
            switch action {
            case .start:
                guard let track = AudioTrack(
                    item: state.item,
                    canGoPrevious: state.previousItem != nil,
                    canGoNext: state.nextItem != nil
                ) else {
                    reportIssue("No audio source for \(state.item.id)")
                    state.isPlaying = false
                    return .none
                }
                // Optimistic — `.player(.statusChanged)` is the correction.
                state.isPlaying = true
                state.currentTime = 0
                state.duration = state.item.duration
                return .merge(
                    .run { send in
                        for await event in await audioPlayer.events() {
                            await send(.player(event))
                        }
                    },
                    .run { _ in
                        try await audioPlayer.load(track)
                    } catch: { error, _ in
                        reportIssue(error, "AudioPlayerClient.load failed")
                    }
                )
                .cancellable(id: CancelID.player, cancelInFlight: true)

            case .view(.playPauseTapped):
                let wasPlaying = state.isPlaying
                state.isPlaying.toggle()
                return .run { _ in
                    if wasPlaying {
                        await audioPlayer.pause()
                    } else {
                        await audioPlayer.play()
                    }
                }

            case .view(.nextTapped):
                guard let next = state.nextItem else { return .none }
                state.item = next
                return .send(.start)

            case .view(.previousTapped):
                guard state.currentTime <= Self.restartThreshold, let previous = state.previousItem
                else {
                    state.currentTime = 0
                    return .run { _ in await audioPlayer.seek(0) }
                }
                state.item = previous
                return .send(.start)

            case let .view(.scrubbingChanged(isScrubbing)):
                state.isScrubbing = isScrubbing
                guard !isScrubbing else { return .none }
                return .run { [time = state.currentTime] _ in await audioPlayer.seek(time) }

            case .view(.expandTapped):
                state.detent = .large
                return .none

            case .view(.closeTapped):
                // Stop before closing: `.closed` makes the parent nil this state,
                // which cancels every effect below — including, if it were merged
                // here, the one doing the stopping.
                return .run { send in
                    await audioPlayer.stop()
                    await send(.delegate(.closed))
                }

            case .view(.viewAlbumTapped):
                guard let albumID = state.item.albumID else { return .none }
                return .send(.delegate(.viewAlbumTapped(albumID: albumID)))

            case let .view(.authorTapped(ref)):
                return .send(.delegate(.authorTapped(ref)))

            case let .player(.statusChanged(isPlaying)):
                state.isPlaying = isPlaying
                return .none

            case let .player(.progress(time, duration)):
                if let duration { state.duration = duration }
                guard !state.isScrubbing else { return .none }
                state.currentTime = time
                return .none

            case .player(.finished):
                guard let next = state.nextItem else {
                    state.isPlaying = false
                    state.currentTime = 0
                    return .run { _ in await audioPlayer.seek(0) }
                }
                state.item = next
                return .send(.start)

            case let .player(.failed(message)):
                reportIssue("Audio playback failed: \(message)")
                state.isPlaying = false
                return .none

            case let .player(.remote(command)):
                switch command {
                case .toggle:
                    return .send(.view(.playPauseTapped))
                case .play:
                    guard !state.isPlaying else { return .none }
                    return .send(.view(.playPauseTapped))
                case .pause:
                    guard state.isPlaying else { return .none }
                    return .send(.view(.playPauseTapped))
                case .next:
                    return .send(.view(.nextTapped))
                case .previous:
                    return .send(.view(.previousTapped))
                case let .seek(time):
                    state.currentTime = time
                    return .run { _ in await audioPlayer.seek(time) }
                }

            case .binding, .delegate:
                return .none
            }
        }
    }
}

@ViewAction(for: SongPreviewFeature.self)
struct SongPreviewView: View {
    @Bindable var store: StoreOf<SongPreviewFeature>

    var body: some View {
        Group {
            if store.detent == .large {
                fullPlayer
            } else {
                miniPlayer
            }
        }
        .presentationDetents([SongPreviewFeature.miniDetent, .large], selection: $store.detent)
        .presentationBackgroundInteraction(.enabled(upThrough: SongPreviewFeature.miniDetent))
        .presentationDragIndicator(.hidden)
    }

    private var fullPlayer: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(.secondary)
                .frame(width: 36, height: 5)
                .padding(.top, 8)
                .padding(.bottom, 24)

            artwork(url: store.item.imageURL, size: 320, cornerRadius: 16)
                .shadow(color: .black.opacity(0.25), radius: 24, y: 12)
                .padding(.horizontal, 32)

            VStack(spacing: 4) {
                Text(store.item.title)
                    .font(.title)
                    .multilineTextAlignment(.center)

                if let author = store.item.author {
                    Button {
                        send(.authorTapped(author))
                    } label: {
                        HStack(spacing: 4) {
                            Text(author.name)
                            Image(systemName: "chevron.forward").font(.caption)
                        }
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(.isButton)
                    .accessibilityHint("Shows all items by \(author.name)")
                } else {
                    Text(store.item.subtitle)
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }

                if store.item.albumID != nil {
                    Button("View Album") { send(.viewAlbumTapped) }
                        .font(.body)
                        .padding(.top, 4)
                }
            }
            .padding(.top, 32)
            .padding(.horizontal, 32)

            scrubber
                .padding(.top, 28)
                .padding(.horizontal, 32)

            transport
                .padding(.top, 20)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var miniPlayer: some View { SongMiniBar(store: store) }

    private func artwork(url: URL?, size: CGFloat, cornerRadius: CGFloat) -> some View {
        ZStack {
            Color(.systemGray5)
            if let url {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .empty:
                        ProgressView()
                    case let .success(image):
                        image.resizable().scaledToFill()
                    case .failure:
                        artworkGlyph(size: size)
                    @unknown default:
                        artworkGlyph(size: size)
                    }
                }
            } else {
                artworkGlyph(size: size)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }

    private func artworkGlyph(size: CGFloat) -> some View {
        Image(systemName: store.item.systemImage)
            .font(.system(size: size * 0.2))
            .foregroundStyle(.secondary)
    }

    private var scrubber: some View {
        VStack(spacing: 4) {
            Slider(
                value: $store.currentTime,
                in: 0 ... (store.duration ?? 1),
                onEditingChanged: { send(.scrubbingChanged($0)) }
            )
            .tint(.primary)
            // Nothing to scrub to until the track reports a length.
            .disabled(store.duration == nil)
            .accessibilityLabel("Playback position")
            .accessibilityValue(store.currentTime.playbackLabel)

            HStack {
                Text(store.currentTime.playbackLabel)
                Spacer()
                Text(store.currentTime.remainingLabel(of: store.duration))
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            // Keeps the ticking digits from nudging the row on every update.
            .monospacedDigit()
        }
    }

    private var transport: some View {
        HStack(spacing: 48) {
            Button { send(.previousTapped) } label: {
                Image(systemName: "backward.fill")
                    .font(.title)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .disabled(!store.canGoBack)
            .accessibilityLabel("Previous track")

            Button { send(.playPauseTapped) } label: {
                Image(systemName: store.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(.primary)
                    .frame(width: 64, height: 64)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(store.isPlaying ? "Pause" : "Play")

            Button { send(.nextTapped) } label: {
                Image(systemName: "forward.fill")
                    .font(.title)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .disabled(store.nextItem == nil)
            .accessibilityLabel("Next track")
        }
    }
}

/// The collapsed song bar — artwork, title, play/pause, close. Used inside the
/// preview sheet and, when a photo preview is also open, as a docked bar in
/// `MediaPreviewView`.
@ViewAction(for: SongPreviewFeature.self)
struct SongMiniBar: View {
    let store: StoreOf<SongPreviewFeature>

    var body: some View {
        HStack(spacing: 12) {
            CoverTile(
                systemImage: store.item.systemImage,
                imageURL: store.item.smallImageURL,
                size: 44,
                cornerRadius: 6
            )

            Text(store.item.title)
                .font(.body)
                .lineLimit(1)

            Spacer(minLength: 8)

            Button { send(.playPauseTapped) } label: {
                Image(systemName: store.isPlaying ? "pause.fill" : "play.fill")
                    .font(.title3)
                    .foregroundStyle(.primary)
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(store.isPlaying ? "Pause" : "Play")

            Button { send(.closeTapped) } label: {
                Image(systemName: "xmark")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close song preview")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: 56)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .contentShape(Rectangle())
        .onTapGesture { send(.expandTapped) }
    }
}

#Preview {
    Color.clear
        .sheet(isPresented: .constant(true)) {
            SongPreviewView(
                store: Store(
                    initialState: SongPreviewFeature.State(item: HomeSection.mocks[0].items[0])
                ) {
                    SongPreviewFeature()
                }
            )
        }
}
