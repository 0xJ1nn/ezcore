import AVFoundation
import Foundation

/// Device output adapter. All state is confined to the main queue, including
/// completion accounting. Queue bounds prevent unbounded latency/memory.
final class PcmAudio {
    private var engine: AVAudioEngine?
    private var player: AVAudioPlayerNode?
    private var format: AVAudioFormat?
    private var queued = 0
    private var generation = 0

    func start(rate: Double) throws {
        stop()
        guard rate.isFinite, rate >= 8000, rate <= 192000,
              let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 2) else {
            throw NSError(domain: "ezcore.audio", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Invalid sample rate"])
        }
        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        try engine.start()
        player.play()
        self.engine = engine
        self.player = player
        self.format = format
    }

    func write(_ data: Data) throws {
        guard let player = player, let format = format,
              data.count % 4 == 0, data.count <= 262144 else {
            throw NSError(domain: "ezcore.audio", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "Invalid PCM or output not started"])
        }
        if data.isEmpty { return }
        let frames = data.count / 4
        // Bound queued audio to 150 ms. A stalled device must not grow a queue.
        guard queued + frames <= Int(format.sampleRate * 0.15) else { return }
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format,
                frameCapacity: AVAudioFrameCount(frames)), let channels = buffer.floatChannelData else { return }
        buffer.frameLength = AVAudioFrameCount(frames)
        data.withUnsafeBytes { raw in
            let bytes = raw.bindMemory(to: UInt8.self)
            for f in 0..<frames {
                for c in 0..<2 {
                    let i = f * 4 + c * 2
                    let sample = Int16(bitPattern: UInt16(bytes[i]) | UInt16(bytes[i+1]) << 8)
                    channels[c][f] = Float(sample) / 32768.0
                }
            }
        }
        queued += frames
        let current = generation
        player.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { [weak self] _ in
            DispatchQueue.main.async {
                guard let self = self, self.generation == current else { return }
                self.queued = max(0, self.queued - frames)
            }
        }
    }

    func stop() {
        generation += 1
        player?.stop()
        engine?.stop()
        player = nil; engine = nil; format = nil; queued = 0
    }
}
