import Foundation

struct TranscriptSegment: Sendable, Equatable {
    let start: Double
    let end: Double
    let text: String
    let isFinal: Bool
}

struct Transcript {
    private(set) var segments: [TranscriptSegment] = []
    private var finished = false
    var preview: String { segments.map(\.text).joined() }
    var finalText: String { segments.filter(\.isFinal).map(\.text).joined() }

    mutating func receive(_ segment: TranscriptSegment) {
        guard !finished, segment.start.isFinite, segment.end.isFinite,
              segment.end >= segment.start else { return }
        // Finalized ranges are immutable; late volatile callbacks cannot rewrite them.
        guard !segments.contains(where: {
            $0.isFinal && ($0.start == segment.start || ($0.start < segment.end && segment.start < $0.end))
        }) else { return }
        segments.removeAll {
            !$0.isFinal && ($0.start == segment.start || ($0.start < segment.end && segment.start < $0.end))
        }
        segments.append(segment)
        segments.sort { $0.start < $1.start }
    }

    mutating func finish() {
        finished = true
        segments.removeAll { !$0.isFinal }
    }
}
