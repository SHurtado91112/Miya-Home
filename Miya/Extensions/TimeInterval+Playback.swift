//
//  TimeInterval+Playback.swift
//  Miya
//
//  Created by Steven Hurtado on 9/9/26.
//

import Foundation

extension TimeInterval {
    /// `m:ss` for a playback position. Negative and non-finite values (an
    /// `AVPlayerItem` that hasn't reported a duration yet) clamp to `0:00`.
    var playbackLabel: String {
        guard isFinite, self > 0 else { return "0:00" }
        return Duration.seconds(self).formatted(.time(pattern: .minuteSecond))
    }

    /// `-m:ss` remaining, given a total length. Empty when the length is unknown,
    /// so the trailing label simply doesn't render rather than showing `-0:00`.
    func remainingLabel(of duration: TimeInterval?) -> String {
        guard let duration, duration.isFinite, duration > 0 else { return "" }
        return "-\(max(0, duration - self).playbackLabel)"
    }
}
