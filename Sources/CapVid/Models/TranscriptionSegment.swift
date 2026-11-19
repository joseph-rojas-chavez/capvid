import Foundation

/// A single timed caption line produced by speech-to-text or user edits.
public struct TranscriptionSegment: Equatable, Sendable, Identifiable {
    public var index: Int
    public var startTime: TimeInterval
    public var endTime: TimeInterval
    public var text: String

    public var id: Int { index }

    public var duration: TimeInterval {
        endTime - startTime
    }

    public init(
        index: Int,
        startTime: TimeInterval,
        endTime: TimeInterval,
        text: String
    ) {
        self.index = index
        self.startTime = startTime
        self.endTime = endTime
        self.text = text
    }
}
