//
//  AudioPlayerClient.swift
//  Miya
//
//  The playback dependency. Mirrors `HomeClient`'s shape: a `@DependencyClient`
//  closure struct with a `liveValue` and a silent `previewValue`, registered on
//  `DependencyValues`.
//
//  The reducer, not this client, is the source of truth for transport state.
//  Everything the player learns on its own — a periodic time update, the end of
//  a track, an interruption, a lock-screen button — comes back through `events`
//  as a fact for `SongPreviewFeature` to act on, rather than being applied here.
//

import ComposableArchitecture
import Foundation

/// One item of playable audio, flattened out of `HomeSectionItem` so the audio
/// layer doesn't depend on the app's media model. `canGoPrevious` / `canGoNext`
/// drive the lock screen's transport buttons, so they're part of what a track
/// says about itself.
struct AudioTrack: Equatable, Sendable {
    var id: String
    var url: URL
    var title: String
    var artist: String?
    var artworkURL: URL?
    var duration: TimeInterval?
    var canGoPrevious: Bool
    var canGoNext: Bool
}

extension AudioTrack {
    /// Server audio when the item has it, else a bundled test track. `nil` only
    /// if the bundled resources are missing from the app.
    init?(item: HomeSectionItem, canGoPrevious: Bool, canGoNext: Bool) {
        guard let url = item.audioURL ?? TestAudio.url(for: item.id) else { return nil }
        self.init(
            id: item.id,
            url: url,
            title: item.title,
            artist: item.author?.name ?? item.subtitle,
            artworkURL: item.smallImageURL,
            duration: item.duration,
            canGoPrevious: canGoPrevious,
            canGoNext: canGoNext
        )
    }
}

enum AudioPlayerEvent: Equatable, Sendable {
    /// Reflects `AVPlayer.timeControlStatus` — the truth behind the play/pause
    /// glyph, including changes the app didn't ask for (interruptions, a route
    /// change, a stall).
    case statusChanged(isPlaying: Bool)
    case progress(time: TimeInterval, duration: TimeInterval?)
    case finished
    /// `Error` isn't `Equatable`, so failures travel as a message.
    case failed(String)
    case remote(RemoteCommand)

    enum RemoteCommand: Equatable, Sendable {
        case play, pause, toggle, next, previous
        case seek(TimeInterval)
    }
}

@DependencyClient
struct AudioPlayerClient: Sendable {
    /// Activate the audio session, hand `AVPlayer` the track, publish now-playing
    /// metadata, and start playing.
    var load: @Sendable (_ track: AudioTrack) async throws -> Void
    var play: @Sendable () async -> Void
    var pause: @Sendable () async -> Void
    var seek: @Sendable (_ time: TimeInterval) async -> Void
    /// Pause, clear now-playing, and deactivate the session.
    var stop: @Sendable () async -> Void
    /// Everything the player reports back. A new subscription replaces the old
    /// one and immediately replays the current status, so a reducer restarting
    /// its subscription (on every queue advance) never races past what it missed.
    var events: @Sendable () async -> AsyncStream<AudioPlayerEvent> = { .finished }
}

extension AudioPlayerClient: DependencyKey {
    static let liveValue = AudioPlayerClient(
        load: { track in try await AudioPlayerEngine.shared.load(track) },
        play: { await AudioPlayerEngine.shared.play() },
        pause: { await AudioPlayerEngine.shared.pause() },
        seek: { time in await AudioPlayerEngine.shared.seek(to: time) },
        stop: { await AudioPlayerEngine.shared.stop() },
        events: { await AudioPlayerEngine.shared.events() }
    )

    /// Silent: previews render the player chrome without making noise.
    static let previewValue = AudioPlayerClient(
        load: { _ in },
        play: {},
        pause: {},
        seek: { _ in },
        stop: {},
        events: { .never }
    )
}

extension DependencyValues {
    var audioPlayer: AudioPlayerClient {
        get { self[AudioPlayerClient.self] }
        set { self[AudioPlayerClient.self] = newValue }
    }
}
