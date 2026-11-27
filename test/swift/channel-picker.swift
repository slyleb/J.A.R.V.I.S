// Drives ChannelPicker through a few inputs and prints, for each, the channel heard after every
// buffer and how many times it faded to another. test/unit/ears.test.mjs compiles and checks it.
import Foundation

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

        let data = try! JSONSerialization.data(withJSONObject: out, options: [.sortedKeys])
        print(String(data: data, encoding: .utf8)!)
    }
}
