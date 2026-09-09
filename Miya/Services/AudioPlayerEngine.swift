//
//  AudioPlayerEngine.swift
//  Miya
//
//  The AVFoundation / MediaPlayer machinery behind `AudioPlayerClient.liveValue`.
//  `@MainActor` because `AVPlayer`, `MPNowPlayingInfoCenter`, and
//  `MPRemoteCommandCenter` all want the main thread anyway — isolating the whole
//  engine avoids a maze of hops for what is a handful of property writes.
//
//  Background playback rests on two things together: the `.playback` audio
//  session activated on the first `load`, and `INFOPLIST_KEY_UIBackgroundModes =
//  audio` in the target's build settings. Either one alone is not enough.
//

import AVFoundation
import Foundation
import MediaPlayer
import UIKit

@MainActor
final class AudioPlayerEngine {
    static let shared = AudioPlayerEngine()

    private let player = AVPlayer()
    private var continuation: AsyncStream<AudioPlayerEvent>.Continuation?

    private var track: AudioTrack?
    private var isPlaying = false
    private var nowPlayingArtwork: MPMediaItemArtwork?

    private var timeObserver: Any?
    private var statusObservation: NSKeyValueObservation?
    private var itemStatusObservation: NSKeyValueObservation?
    private var artworkTask: Task<Void, Never>?
    private var artworkCache: [URL: MPMediaItemArtwork] = [:]

    private var hasActivatedSession = false
    private var hasRegisteredCommands = false

    private init() {
        player.actionAtItemEnd = .pause
        observePlayer()
        observeSession()
    }

    // MARK: - Events

    // `events` / `play` / `pause` / `stop` are `async` with nothing to await
    // inside them on purpose: Swift 5 language mode doesn't diagnose a
    // synchronous call to a `@MainActor` member from a nonisolated async
    // context, so without the suspension point these would run on whatever
    // thread the effect happens to be on — and `AVPlayer`,
    // `MPNowPlayingInfoCenter`, and `MPRemoteCommandCenter` are all main-thread
    // API. `async` makes the hop real.

    /// One subscriber at a time: `SongPreviewFeature` restarts its subscription
    /// on every queue advance, so the previous stream is finished rather than
    /// left to accumulate. The current status is replayed immediately so a fresh
    /// subscriber isn't blind until the next half-second tick.
    func events() async -> AsyncStream<AudioPlayerEvent> {
        continuation?.finish()
        let (stream, continuation) = AsyncStream<AudioPlayerEvent>.makeStream(
            bufferingPolicy: .bufferingNewest(32)
        )
        self.continuation = continuation
        continuation.yield(.statusChanged(isPlaying: isPlaying))
        return stream
    }

    private func emit(_ event: AudioPlayerEvent) {
        continuation?.yield(event)
    }

    // MARK: - Transport

    func load(_ track: AudioTrack) async throws {
        try activateSessionIfNeeded()
        registerCommandsIfNeeded()

        self.track = track
        updateCommandAvailability()

        let item = AVPlayerItem(url: track.url)
        player.replaceCurrentItem(with: item)
        observeItemStatus(item)
        installTimeObserver()
        player.play()

        loadArtwork(for: track)
        updateNowPlaying()
    }

    func play() async {
        guard player.currentItem != nil else { return }
        try? activateSessionIfNeeded()
        player.play()
        updateNowPlaying()
    }

    func pause() async {
        player.pause()
        updateNowPlaying()
    }

    func seek(to time: TimeInterval) async {
        // Zero tolerance so the scrubber lands where the user dropped it.
        await player.seek(
            to: CMTime(seconds: max(0, time), preferredTimescale: 600),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        )
        updateNowPlaying()
    }

    func stop() async {
        artworkTask?.cancel()
        player.pause()
        player.replaceCurrentItem(with: nil)
        itemStatusObservation = nil
        track = nil
        nowPlayingArtwork = nil
        isPlaying = false

        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        MPRemoteCommandCenter.shared().nextTrackCommand.isEnabled = false
        MPRemoteCommandCenter.shared().previousTrackCommand.isEnabled = false

        emit(.statusChanged(isPlaying: false))

        // Hand the session back so other apps' audio can resume.
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        hasActivatedSession = false
    }

    // MARK: - Session

    /// Activated on the first `load` rather than at launch, so merely opening
    /// Miya never interrupts whatever the user was already listening to.
    private func activateSessionIfNeeded() throws {
        guard !hasActivatedSession else { return }
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default)
        try session.setActive(true)
        hasActivatedSession = true
    }

    private func observeSession() {
        let center = NotificationCenter.default
        center.addObserver(
            forName: AVAudioSession.interruptionNotification, object: nil, queue: .main
        ) { [weak self] notification in
            MainActor.assumeIsolated { self?.handleInterruption(notification) }
        }
        center.addObserver(
            forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main
        ) { [weak self] notification in
            MainActor.assumeIsolated { self?.handleRouteChange(notification) }
        }
    }

    private func handleInterruption(_ notification: Notification) {
        guard
            let raw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
            let type = AVAudioSession.InterruptionType(rawValue: raw)
        else { return }

        switch type {
        case .began:
            // The system has already paused us; just tell the reducer.
            isPlaying = false
            emit(.statusChanged(isPlaying: false))
            updateNowPlaying()
        case .ended:
            let raw = notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            guard AVAudioSession.InterruptionOptions(rawValue: raw).contains(.shouldResume) else { return }
            // Resuming is the reducer's call, not ours — it owns `isPlaying`.
            emit(.remote(.play))
        @unknown default:
            return
        }
    }

    private func handleRouteChange(_ notification: Notification) {
        guard
            let raw = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
            AVAudioSession.RouteChangeReason(rawValue: raw) == .oldDeviceUnavailable
        else { return }
        // Headphones pulled out — pause rather than switching to the speaker.
        player.pause()
        updateNowPlaying()
    }

    // MARK: - Player observation

    private func observePlayer() {
        statusObservation = player.observe(\.timeControlStatus, options: [.new]) { player, _ in
            let status = player.timeControlStatus
            Task { @MainActor [weak self] in self?.handleTimeControlStatus(status) }
        }

        NotificationCenter.default.addObserver(
            forName: AVPlayerItem.didPlayToEndTimeNotification, object: nil, queue: .main
        ) { [weak self] notification in
            MainActor.assumeIsolated {
                guard let self, (notification.object as? AVPlayerItem) === self.player.currentItem
                else { return }
                self.emit(.finished)
            }
        }
    }

    private func handleTimeControlStatus(_ status: AVPlayer.TimeControlStatus) {
        // `.waitingToPlayAtSpecifiedRate` is buffering, not a pause — reporting it
        // as stopped would flip the button back to ▶ every time the stream stalls.
        let playing = status != .paused
        guard playing != isPlaying else { return }
        isPlaying = playing
        emit(.statusChanged(isPlaying: playing))
        updateNowPlaying()
    }

    private func observeItemStatus(_ item: AVPlayerItem) {
        itemStatusObservation = item.observe(\.status, options: [.new]) { item, _ in
            switch item.status {
            case .readyToPlay:
                // The asset's real length only exists now, and it's the one
                // now-playing field the periodic observer no longer refreshes.
                Task { @MainActor [weak self] in self?.updateNowPlaying() }
            case .failed:
                let message = item.error?.localizedDescription ?? "The track could not be played."
                Task { @MainActor [weak self] in self?.emit(.failed(message)) }
            case .unknown:
                break
            @unknown default:
                break
            }
        }
    }

    private func installTimeObserver() {
        guard timeObserver == nil else { return }
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.5, preferredTimescale: 600), queue: .main
        ) { [weak self] time in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.emit(.progress(time: time.seconds, duration: self.currentDuration))
                // Deliberately *not* refreshing now-playing here: MediaRemote
                // extrapolates the elapsed time from the rate and timestamp we
                // already gave it, so pushing it twice a second would just be
                // constant XPC traffic for the whole time we're backgrounded.
                // It's refreshed on the state changes that actually invalidate
                // it — load, play, pause, seek, artwork.
            }
        }
    }

    /// The item's real length once it's ready; the server's `durationSeconds`
    /// until then, and forever if the server didn't send one and the asset
    /// doesn't report one either.
    private var currentDuration: TimeInterval? {
        guard let item = player.currentItem, item.status == .readyToPlay else { return track?.duration }
        let duration = item.duration
        guard duration.isNumeric, duration.seconds > 0 else { return track?.duration }
        return duration.seconds
    }

    // MARK: - Now playing

    private func updateNowPlaying() {
        guard let track else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: track.title,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: player.currentTime().seconds,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue,
        ]
        info[MPMediaItemPropertyArtist] = track.artist
        info[MPMediaItemPropertyPlaybackDuration] = currentDuration
        info[MPMediaItemPropertyArtwork] = nowPlayingArtwork
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func loadArtwork(for track: AudioTrack) {
        artworkTask?.cancel()
        nowPlayingArtwork = nil

        guard let url = track.artworkURL else { return }
        if let cached = artworkCache[url] {
            nowPlayingArtwork = cached
            return
        }
        artworkTask = Task { [weak self] in
            guard
                let (data, _) = try? await URLSession.shared.data(from: url),
                let image = UIImage(data: data),
                let self,
                // A newer track may have started while this was in flight.
                self.track?.artworkURL == url
            else { return }
            let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
            self.artworkCache[url] = artwork
            self.nowPlayingArtwork = artwork
            self.updateNowPlaying()
        }
    }

    // MARK: - Remote commands

    /// Registered once — `addTarget` stacks handlers, so re-registering on every
    /// track would fire a lock-screen tap N times. Handlers only report the tap;
    /// `SongPreviewFeature` decides what it means.
    private func registerCommandsIfNeeded() {
        guard !hasRegisteredCommands else { return }
        hasRegisteredCommands = true

        let center = MPRemoteCommandCenter.shared()

        center.playCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.emit(.remote(.play)) }
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.emit(.remote(.pause)) }
            return .success
        }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.emit(.remote(.toggle)) }
            return .success
        }
        center.nextTrackCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.emit(.remote(.next)) }
            return .success
        }
        center.previousTrackCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.emit(.remote(.previous)) }
            return .success
        }
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            MainActor.assumeIsolated { self?.emit(.remote(.seek(event.positionTime))) }
            return .success
        }
    }

    /// Keeps the lock screen from showing dead ⏮ / ⏭ buttons at the ends of the queue.
    private func updateCommandAvailability() {
        let center = MPRemoteCommandCenter.shared()
        center.nextTrackCommand.isEnabled = track?.canGoNext ?? false
        center.previousTrackCommand.isEnabled = track?.canGoPrevious ?? false
    }
}
