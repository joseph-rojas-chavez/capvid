import Foundation

/// Sanitizes raw ML transcript segments so captions burn in cleanly on export.
public enum CaptionTimeline {
    /// Minimum readable caption duration in seconds.
    public static let minSegmentDuration: TimeInterval = 0.12

    /// Floating-point tolerance for time comparisons.
    public static let timeEpsilon: TimeInterval = 0.001

    /// Maximum overlap-resolution passes before merging intersecting segments.
    public static let maxOverlapResolutionIterations = 12

    /// Floor for the export timeline length parameter.
    public static let minimumTimelineEnd: TimeInterval = 0.02

    /// Computes export timeline length from the shortest valid media duration.
    public static func compositionDurationSeconds(
        assetDuration: TimeInterval?,
        videoTrackDuration: TimeInterval?,
        audioTrackDuration: TimeInterval?
    ) -> TimeInterval {
        let candidates = [assetDuration, videoTrackDuration, audioTrackDuration]
            .compactMap { $0 }
            .filter { $0 > 0 }

        guard let shortest = candidates.min() else {
            return minimumTimelineEnd
        }

        return max(shortest, minimumTimelineEnd)
    }

    /// Cleans raw segments for burn-in: clamp, de-overlap, merge tail pile-ups, re-index.
    public static func sanitizedForBurn(
        _ segments: [TranscriptionSegment],
        timelineEnd: TimeInterval
    ) -> [TranscriptionSegment] {
        let effectiveTimelineEnd = max(timelineEnd, minimumTimelineEnd)

        var result = segments
            .filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .compactMap { clampAndValidate($0, timelineEnd: effectiveTimelineEnd) }

        result.sort { $0.startTime < $1.startTime }

        for _ in 0 ..< maxOverlapResolutionIterations {
            let changed = resolveOverlaps(&result)
            if !changed {
                break
            }
        }

        result = mergeIntersectingSegments(result, timelineEnd: effectiveTimelineEnd)
        result = result.compactMap { enforceMinimumDuration($0, timelineEnd: effectiveTimelineEnd) }

        for index in result.indices {
            result[index].index = index + 1
        }

        return result
    }

    /// Preserves authored caption start times (for SRT/TXT merge) while clamping to the video timeline.
    /// Only trims overlapping ends — never shifts when a line should appear.
    public static func timedForBurnIn(
        _ segments: [TranscriptionSegment],
        timelineEnd: TimeInterval
    ) -> [TranscriptionSegment] {
        let effectiveTimelineEnd = max(timelineEnd, minimumTimelineEnd)

        var result = segments
            .filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .map { segment -> TranscriptionSegment in
                var timed = segment
                timed.startTime = max(0, min(segment.startTime, effectiveTimelineEnd))
                timed.endTime = max(0, min(segment.endTime, effectiveTimelineEnd))
                return timed
            }
            .filter { $0.startTime < $0.endTime - timeEpsilon }
            .sorted { $0.startTime < $1.startTime }

        guard result.count > 1 else {
            return reindexed(result)
        }

        for index in 0 ..< (result.count - 1) {
            if result[index].endTime > result[index + 1].startTime + timeEpsilon {
                result[index].endTime = result[index + 1].startTime
            }
            if result[index].startTime >= result[index].endTime - timeEpsilon {
                result[index].endTime = min(
                    result[index].startTime + minSegmentDuration,
                    effectiveTimelineEnd
                )
            }
        }

        result = result.filter { $0.startTime < $0.endTime - timeEpsilon }
        return reindexed(result)
    }

    private static func reindexed(_ segments: [TranscriptionSegment]) -> [TranscriptionSegment] {
        segments.enumerated().map { offset, segment in
            var updated = segment
            updated.index = offset + 1
            return updated
        }
    }

    // MARK: - Private

    private static func clampAndValidate(
        _ segment: TranscriptionSegment,
        timelineEnd: TimeInterval
    ) -> TranscriptionSegment? {
        var sanitized = segment
        sanitized.startTime = max(0, min(segment.startTime, timelineEnd))
        sanitized.endTime = max(0, min(segment.endTime, timelineEnd))

        guard sanitized.startTime < sanitized.endTime - timeEpsilon else {
            return nil
        }

        return enforceMinimumDuration(sanitized, timelineEnd: timelineEnd)
    }

    private static func enforceMinimumDuration(
        _ segment: TranscriptionSegment,
        timelineEnd: TimeInterval
    ) -> TranscriptionSegment? {
        var sanitized = segment

        if sanitized.duration < minSegmentDuration - timeEpsilon {
            let proposedEnd = min(sanitized.startTime + minSegmentDuration, timelineEnd)
            guard proposedEnd > sanitized.startTime + timeEpsilon else {
                return nil
            }
            sanitized.endTime = proposedEnd
        }

        guard sanitized.duration >= minSegmentDuration - timeEpsilon else {
            return nil
        }

        return sanitized
    }

    private static func resolveOverlaps(_ segments: inout [TranscriptionSegment]) -> Bool {
        guard segments.count > 1 else {
            return false
        }

        var changed = false

        for index in 0 ..< (segments.count - 1) {
            let overlap = segments[index].endTime - segments[index + 1].startTime
            guard overlap > timeEpsilon else {
                continue
            }

            segments[index].endTime = segments[index + 1].startTime
            changed = true

            if segments[index].duration < minSegmentDuration - timeEpsilon {
                let deficit = minSegmentDuration - segments[index].duration
                let newStart = segments[index].startTime - deficit
                if newStart >= -timeEpsilon {
                    segments[index].startTime = max(0, newStart)
                }
            }
        }

        return changed
    }

    private static func mergeIntersectingSegments(
        _ segments: [TranscriptionSegment],
        timelineEnd: TimeInterval
    ) -> [TranscriptionSegment] {
        guard !segments.isEmpty else {
            return []
        }

        var merged: [TranscriptionSegment] = []
        var current = segments[0]

        for segment in segments.dropFirst() {
            if current.endTime > segment.startTime + timeEpsilon {
                current.endTime = max(current.endTime, min(segment.endTime, timelineEnd))
                current.text = [current.text, segment.text]
                    .joined(separator: " ")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            } else {
                merged.append(current)
                current = segment
            }
        }

        merged.append(current)
        return merged
    }
}
