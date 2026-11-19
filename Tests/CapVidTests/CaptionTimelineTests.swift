import CapVid
import Testing

@Test func compositionDurationUsesShortestValidTrack() {
    let duration = CaptionTimeline.compositionDurationSeconds(
        assetDuration: 120.0,
        videoTrackDuration: 118.5,
        audioTrackDuration: 119.0
    )
    #expect(duration == 118.5)
}

@Test func compositionDurationFallsBackToMinimum() {
    let duration = CaptionTimeline.compositionDurationSeconds(
        assetDuration: nil,
        videoTrackDuration: nil,
        audioTrackDuration: nil
    )
    #expect(duration == CaptionTimeline.minimumTimelineEnd)
}

@Test func sanitizedForBurnRemovesOverlaps() {
    let raw = [
        TranscriptionSegment(index: 1, startTime: 0.0, endTime: 3.5, text: "First"),
        TranscriptionSegment(index: 2, startTime: 3.0, endTime: 5.0, text: "Second"),
    ]

    let sanitized = CaptionTimeline.sanitizedForBurn(raw, timelineEnd: 10.0)

    #expect(sanitized.count == 2)
    #expect(sanitized[0].endTime <= sanitized[1].startTime + CaptionTimeline.timeEpsilon)
}

@Test func sanitizedForBurnClampsToTimelineEnd() {
    let raw = [
        TranscriptionSegment(index: 1, startTime: 7.0, endTime: 12.0, text: "Out of bounds"),
    ]

    let sanitized = CaptionTimeline.sanitizedForBurn(raw, timelineEnd: 10.0)

    #expect(sanitized.count == 1)
    #expect(sanitized[0].endTime == 10.0)
}

@Test func sanitizedForBurnEnforcesMinimumDuration() {
    let raw = [
        TranscriptionSegment(index: 1, startTime: 1.0, endTime: 1.05, text: "Flash"),
    ]

    let sanitized = CaptionTimeline.sanitizedForBurn(raw, timelineEnd: 10.0)

    #expect(sanitized.count == 1)
    #expect(sanitized[0].duration >= CaptionTimeline.minSegmentDuration - CaptionTimeline.timeEpsilon)
}

@Test func sanitizedForBurnReindexesSegments() {
    let raw = [
        TranscriptionSegment(index: 99, startTime: 0.0, endTime: 1.0, text: "A"),
        TranscriptionSegment(index: 42, startTime: 2.0, endTime: 3.0, text: "B"),
    ]

    let sanitized = CaptionTimeline.sanitizedForBurn(raw, timelineEnd: 10.0)

    #expect(sanitized.map(\.index) == [1, 2])
}

@Test func demoSampleDataProducesSanitizedOutput() {
    let raw = [
        TranscriptionSegment(index: 1, startTime: 0.0, endTime: 3.5, text: "Welcome to CapVid."),
        TranscriptionSegment(index: 2, startTime: 3.0, endTime: 5.0, text: "This overlaps the previous line."),
        TranscriptionSegment(index: 3, startTime: 7.0, endTime: 12.0, text: "This extends past the video end."),
        TranscriptionSegment(index: 4, startTime: 9.5, endTime: 9.7, text: "Too short flash."),
        TranscriptionSegment(index: 5, startTime: 9.6, endTime: 11.0, text: "Tail pile-up segment."),
    ]

    let sanitized = CaptionTimeline.sanitizedForBurn(raw, timelineEnd: 10.0)

    #expect(!sanitized.isEmpty)
    #expect(sanitized.allSatisfy { $0.endTime <= 10.0 + CaptionTimeline.timeEpsilon })

    for index in 0 ..< (sanitized.count - 1) {
        #expect(sanitized[index].endTime <= sanitized[index + 1].startTime + CaptionTimeline.timeEpsilon)
    }
}

@Test func timedForBurnInPreservesStartTimes() {
    let raw = [
        TranscriptionSegment(index: 1, startTime: 1.0, endTime: 3.5, text: "First"),
        TranscriptionSegment(index: 2, startTime: 3.0, endTime: 5.0, text: "Second"),
    ]

    let timed = CaptionTimeline.timedForBurnIn(raw, timelineEnd: 10.0)

    #expect(timed.count == 2)
    #expect(timed[0].startTime == 1.0)
    #expect(timed[1].startTime == 3.0)
    #expect(timed[0].endTime == 3.0)
    #expect(timed[1].endTime == 5.0)
}
