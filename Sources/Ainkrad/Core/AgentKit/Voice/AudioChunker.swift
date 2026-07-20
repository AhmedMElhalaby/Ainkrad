import Foundation

enum AudioChunker {
    struct Chunk: Equatable {
        let index: Int
        let start: Double
        let duration: Double
    }

    /// Splits a duration into contiguous chunks no longer than `maxChunk`.
    static func plan(totalDuration: Double, maxChunk: Double = 120) -> [Chunk] {
        guard totalDuration > 0, maxChunk > 0 else {
            return [Chunk(index: 0, start: 0, duration: max(0, totalDuration))]
        }
        var chunks: [Chunk] = []
        var start = 0.0
        var index = 0
        while start < totalDuration {
            let duration = min(maxChunk, totalDuration - start)
            chunks.append(Chunk(index: index, start: start, duration: duration))
            start += duration
            index += 1
        }
        return chunks
    }
}
