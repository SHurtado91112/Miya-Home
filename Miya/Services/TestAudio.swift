//
//  TestAudio.swift
//  Miya
//
//  Bundled stand-in audio for songs the server has no audio file for. The
//  GraphQL API exposes `audioUrl` (see `MiyaGraphQLClient.songFields`), but it
//  is null for any song whose media hasn't been ingested yet, and the bundled
//  JSON fixtures have no audio at all — so without a fallback most taps would
//  open a silent player.
//
//  The three tracks are generated tones, not licensed music: a pentatonic
//  phrase over a distinct base pitch each, so switching tracks is audibly
//  different and scrub position is obvious by ear.
//

import Foundation

enum TestAudio {
    private static let names = ["test-track-0", "test-track-1", "test-track-2"]

    /// A bundled track chosen deterministically from an item id, so a given song
    /// always sounds the same across launches. Uses FNV-1a rather than
    /// `hashValue`, which Swift seeds randomly per process.
    static func url(for itemID: String) -> URL? {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in itemID.utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x100_0000_01b3
        }
        let name = names[Int(hash % UInt64(names.count))]
        return Bundle.main.url(forResource: name, withExtension: "m4a")
    }
}
