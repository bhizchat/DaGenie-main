import Foundation
import AVFoundation
import Accelerate

final class WaveformGenerator {
    // Downsample target samples per second at default zoom
    private static let targetSamplesPerSecond: Int = 300

    static func loadOrGenerate(for asset: AVAsset) async -> [Float] {
        if let urlAsset = asset as? AVURLAsset, let cached = loadCache(for: urlAsset.url) {
            return cached
        }
        return await generate(for: asset)
    }

    private static func cacheURL(for url: URL) -> URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let name = "wf_\(url.lastPathComponent.hashValue).bin"
        return caches.appendingPathComponent(name)
    }

    private static func loadCache(for url: URL) -> [Float]? {
        let u = cacheURL(for: url)
        guard let data = try? Data(contentsOf: u) else { return nil }
        let count = data.count / MemoryLayout<Float>.size
        return data.withUnsafeBytes { ptr in
            let buf = ptr.bindMemory(to: Float.self)
            return Array(buf.prefix(count))
        }
    }

    private static func saveCache(_ samples: [Float], for url: URL) {
        let u = cacheURL(for: url)
        samples.withUnsafeBufferPointer { bp in
            let d = Data(buffer: bp)
            try? d.write(to: u, options: .atomic)
        }
    }

    static func generate(for asset: AVAsset) async -> [Float] {
        guard let track = asset.tracks(withMediaType: .audio).first else { return [] }
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                var result: [Float] = []
                do {
                    let reader = try AVAssetReader(asset: asset)
                    let settings: [String: Any] = [
                        AVFormatIDKey: kAudioFormatLinearPCM,
                        AVLinearPCMBitDepthKey: 16,
                        AVLinearPCMIsBigEndianKey: false,
                        AVLinearPCMIsFloatKey: false,
                        AVLinearPCMIsNonInterleaved: false
                    ]
                    let output = AVAssetReaderTrackOutput(track: track, outputSettings: settings)
                    reader.add(output)
                    reader.startReading()

                    var all: [Float] = []
                    while reader.status == .reading {
                        autoreleasepool {
                            if let sb = output.copyNextSampleBuffer(),
                               let bb = CMSampleBufferGetDataBuffer(sb) {
                                var length = 0
                                var dataPointer: UnsafeMutablePointer<Int8>?
                                CMBlockBufferGetDataPointer(bb, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &length, dataPointerOut: &dataPointer)
                                let count = length / 2 // 16-bit
                                let srcPtr = UnsafeRawPointer(dataPointer!).bindMemory(to: Int16.self, capacity: count)
                                let floatBuf = UnsafeMutablePointer<Float>.allocate(capacity: count)
                                vDSP_vflt16(srcPtr, 1, floatBuf, 1, vDSP_Length(count))
                                var absBuf = [Float](repeating: 0, count: count)
                                vDSP_vabs(floatBuf, 1, &absBuf, 1, vDSP_Length(count))
                                floatBuf.deallocate()
                                all.append(contentsOf: absBuf)
                            }
                        }
                    }

                    // Downsample to target samples per second
                    let seconds = max(1, Int(ceil(CMTimeGetSeconds(asset.duration))))
                    let target = max(1, seconds * targetSamplesPerSecond)
                    let chunk = max(1, all.count / target)
                    var down: [Float] = []
                    down.reserveCapacity(target)
                    var i = 0
                    while i < all.count {
                        let end = min(i + chunk, all.count)
                        let slice = all[i..<end]
                        var avg: Float = 0
                        vDSP_meanv(Array(slice), 1, &avg, vDSP_Length(slice.count))
                        down.append(avg)
                        i = end
                    }
                    var maxVal: Float = 0
                    vDSP_maxv(down, 1, &maxVal, vDSP_Length(down.count))
                    if maxVal > 0 {
                        vDSP_vsdiv(down, 1, &maxVal, &down, 1, vDSP_Length(down.count))
                    }

                    result = down
                    if let urlAsset = asset as? AVURLAsset { saveCache(result, for: urlAsset.url) }
                } catch {
                    result = []
                }
                continuation.resume(returning: result)
            }
        }
    }
}


