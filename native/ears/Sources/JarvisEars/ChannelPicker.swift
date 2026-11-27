import AVFoundation

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

extension ChannelPicker {
    /// The loudest input channel of `buffer` as mono, fading across the buffer where it switches.
    /// A mono buffer comes back as it is.
    mutating func monoCopy(_ buffer: AVAudioPCMBuffer, to mono: AVAudioFormat, skip: Set<Int> = []) -> AVAudioPCMBuffer {
        let channels = Int(buffer.format.channelCount)
        guard channels > 1, let src = buffer.floatChannelData,
              let out = AVAudioPCMBuffer(pcmFormat: mono, frameCapacity: buffer.frameLength),
              let dst = out.floatChannelData else { return buffer }
        let n = Int(buffer.frameLength)
        out.frameLength = buffer.frameLength
        guard n > 0 else { return out }
        let interleaved = buffer.format.isInterleaved
        let at = { (c: Int, i: Int) -> Float in interleaved ? src[0][i * channels + c] : src[c][i] }
        var power = [Float](repeating: 0, count: channels)
        for c in 0..<channels { var s: Float = 0; for i in 0..<n { let v = at(c, i); s += v * v }; power[c] = s / Float(n) }
        let (from, to) = pick(power, skip: skip)
        if from == to {
            for i in 0..<n { dst[0][i] = at(to, i) }
        } else {
            let step = 1 / Float(n)
            for i in 0..<n { let t = Float(i) * step; dst[0][i] = at(from, i) * (1 - t) + at(to, i) * t }
        }
        return out
    }
}
