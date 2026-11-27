// Drives ChannelPicker through a few inputs and prints, for each, the channel heard after every
// buffer and how many times it faded to another, and the level it hears from real audio buffers.
// test/unit/ears.test.mjs compiles and checks it.
import AVFoundation

func run(_ buffers: [[Float]], skip: Set<Int> = []) -> [String: Any] {
    var p = ChannelPicker()
    var heard: [Int] = [], switches = 0
    for b in buffers {
        let (from, to) = p.pick(b, skip: skip)
        if from != to { switches += 1 }
        heard.append(to)
    }
    return ["heard": heard, "switches": switches]
}

let quiet: Float = 1e-12          // an unused input: about -120 dBFS
let mic: Float = 1e-5             // a room through the mic: about -50 dBFS
// The same wobble every run (a small LCG), so the test never flakes: each buffer 0.5 to 1.5 times v.
nonisolated(unsafe) var seed: UInt32 = 1
func jitter(_ v: Float) -> Float { seed = seed &* 1_664_525 &+ 1_013_904_223; return v * (0.5 + Float(seed >> 8) / Float(1 << 24)) }

/// A tone on input `loud` of `channels`, the others silent (or every input silent when `loud` is nil),
/// through monoCopy for a few buffers. Returns the RMS heard in the last one, the loud input's own RMS,
/// and the RMS of the average of all inputs (how it was heard before).
func level(channels: Int, loud: Int?, interleaved: Bool = false) -> [String: Any] {
    let layout = AVAudioChannelLayout(layoutTag: kAudioChannelLayoutTag_DiscreteInOrder | UInt32(channels))!
    let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48000, interleaved: interleaved, channelLayout: layout)
    let mono = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48000, channels: 1, interleaved: false)!
    let n = 2048
    let tone = (0..<n).map { Float(0.1 * sin(2 * Double.pi * 440 * Double($0) / 48000)) }
    let rms = { (x: [Float]) -> Double in sqrt(x.reduce(0) { $0 + Double($1 * $1) } / Double(x.count)) }
    var p = ChannelPicker(), heard: Double = 0
    for _ in 0..<5 {
        let b = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(n))!
        b.frameLength = AVAudioFrameCount(n)
        let src = b.floatChannelData!
        for c in 0..<channels { for i in 0..<n { let v = c == loud ? tone[i] : 0; if interleaved { src[0][i * channels + c] = v } else { src[c][i] = v } } }
        let out = p.monoCopy(b, to: mono)
        heard = rms(Array(UnsafeBufferPointer(start: out.floatChannelData![0], count: Int(out.frameLength))))
    }
    let input = loud == nil ? 0 : rms(tone)
    return ["heard": heard, "input": input, "average": input / Double(channels), "channel": p.channel]
}

@main
struct Main {
    static func main() {
        var out: [String: Any] = [:]
        // A Scarlett: 26 inputs, the mic on input 1.
        out["interface"] = run((0..<40).map { _ in (0..<26).map { $0 == 0 ? jitter(mic) : quiet } })
        // The mic on input 2, input 1 empty.
        out["second"] = run((0..<40).map { _ in [quiet, jitter(mic)] })
        // A stereo mic: the same level on both sides, wobbling from buffer to buffer.
        out["stereo"] = run((0..<200).map { _ in [jitter(mic), jitter(mic)] })
        // The loopback input (9) carries JARVIS's voice, far louder than the mic.
        out["loopback"] = run((0..<40).map { _ in (0..<26).map { $0 == 0 ? jitter(mic) : $0 == 8 ? 1e-2 : quiet } }, skip: [8])
        // One loud buffer on another input (a knock) and back to normal.
        out["knock"] = run((0..<40).map { i in (0..<4).map { $0 == 0 ? mic : $0 == 2 && i == 20 ? mic * 3 : quiet } })
        // The mic moves from input 1 to input 4 for good.
        out["moved"] = run((0..<40).map { i in (0..<4).map { c in i < 20 ? (c == 0 ? mic : quiet) : (c == 3 ? mic * 100 : quiet) } })
        // Every channel skipped: still hears something rather than nothing.
        out["allSkipped"] = run([[quiet, mic]], skip: [0, 1])
        // Every input silent: stays on input 1, without hopping.
        out["silent"] = run((0..<40).map { _ in [Float](repeating: 0, count: 26) })
        // The level heard from real buffers.
        out["levelInterface"] = level(channels: 26, loud: 0)
        out["levelSecond"] = level(channels: 26, loud: 1)
        out["levelStereo"] = level(channels: 2, loud: 1, interleaved: true)
        out["levelMono"] = level(channels: 1, loud: 0)
        out["levelSilent"] = level(channels: 26, loud: nil)

        let data = try! JSONSerialization.data(withJSONObject: out, options: [.sortedKeys])
        print(String(data: data, encoding: .utf8)!)
    }
}
