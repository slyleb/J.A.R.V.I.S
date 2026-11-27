import Foundation

/// Which input channel the listener hears. An audio interface has many inputs and the microphone is
/// on one of them (a Scarlett 18i20 shows 26, the mic on input 1): averaging them all puts the voice
/// about 28 dB down, under SoundGate's threshold. So it takes the loudest channel instead. Each
/// channel's level is smoothed over a few buffers, and another channel takes over only once it is
/// clearly louder (`margin`), so it doesn't hop between inputs on every buffer. The buffer where it
/// switches fades from the old channel to the new one (`from`, `to`), so there is no click.
/// Channels in `skip` are never chosen: an interface's loopback inputs carry the Mac's own sound.
struct ChannelPicker {
    /// Weight of the newest buffer (about 43 ms) in each channel's smoothed level.
    static let smoothing: Float = 0.25
    /// In power: another channel must be about 3 dB louder to take over.
    static let margin: Float = 2

    private(set) var channel = 0
    private var power: [Float] = []

    /// One buffer's mean square per channel. Returns the channel to fade from and the one to fade to;
    /// the same one unless it switches.
    mutating func pick(_ meanSquare: [Float], skip: Set<Int> = []) -> (from: Int, to: Int) {
        var usable = meanSquare.indices.filter { !skip.contains($0) }
        if usable.isEmpty { usable = Array(meanSquare.indices) }
        guard let first = usable.first else { return (0, 0) }
        if power.count != meanSquare.count {
            // A new input, or the first buffer: start on the loudest, without a fade.
            power = meanSquare
            channel = usable.max { power[$0] < power[$1] } ?? first
            return (channel, channel)
        }
        for c in power.indices { power[c] += Self.smoothing * (meanSquare[c] - power[c]) }
        let from = usable.contains(channel) ? channel : first
        let best = usable.max { power[$0] < power[$1] } ?? first
        if best != from && power[best] > power[from] * Self.margin { channel = best } else { channel = from }
        return (from, channel)
    }
}
