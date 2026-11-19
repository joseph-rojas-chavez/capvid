import CapVid
import Foundation

enum CaptionFileParser {
    enum ParserError: LocalizedError {
        case emptyFile
        case noValidSegments

        var errorDescription: String? {
            switch self {
            case .emptyFile:
                "The caption file is empty."
            case .noValidSegments:
                "No valid caption lines were found. Use SRT format with timestamps."
            }
        }
    }

    static func parse(url: URL) throws -> [TranscriptionSegment] {
        let content = try String(contentsOf: url, encoding: .utf8)
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            throw ParserError.emptyFile
        }

        let segments = parseSRT(trimmed)
        guard segments.isEmpty == false else {
            throw ParserError.noValidSegments
        }
        return segments
    }

    static func parseSRT(_ content: String) -> [TranscriptionSegment] {
        let normalized = content
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        let blocks = normalized.components(separatedBy: "\n\n")
        var segments: [TranscriptionSegment] = []
        var fallbackIndex = 1

        for block in blocks {
            guard let segment = parseBlock(block, fallbackIndex: fallbackIndex) else { continue }
            segments.append(segment)
            fallbackIndex = segment.index + 1
        }

        return segments
    }

    private static func parseBlock(_ block: String, fallbackIndex: Int) -> TranscriptionSegment? {
        let lines = block
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.isEmpty == false }

        guard lines.count >= 2 else { return nil }

        var timingLineIndex = 0
        var index = fallbackIndex

        if lines.count >= 3, let parsedIndex = Int(lines[0]) {
            index = parsedIndex
            timingLineIndex = 1
        }

        guard timingLineIndex < lines.count,
              let timing = parseTimingLine(lines[timingLineIndex]) else {
            return nil
        }

        let text = lines[(timingLineIndex + 1)...].joined(separator: "\n")
        guard text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            return nil
        }

        return TranscriptionSegment(
            index: index,
            startTime: timing.start,
            endTime: timing.end,
            text: text
        )
    }

    private static func parseTimingLine(_ line: String) -> (start: TimeInterval, end: TimeInterval)? {
        let parts = line.components(separatedBy: "-->")
        guard parts.count == 2,
              let start = parseTimestamp(parts[0]),
              let end = parseTimestamp(parts[1]),
              end > start else {
            return nil
        }
        return (start, end)
    }

    private static func parseTimestamp(_ raw: String) -> TimeInterval? {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = value.replacingOccurrences(of: ".", with: ",")
        let chunks = normalized.split(separator: ",")
        guard chunks.count == 2 else { return nil }

        let timeParts = chunks[0].split(separator: ":")
        guard timeParts.count == 3,
              let hours = Double(timeParts[0]),
              let minutes = Double(timeParts[1]),
              let seconds = Double(timeParts[2]),
              let millis = Double(chunks[1]) else {
            return nil
        }

        return hours * 3_600 + minutes * 60 + seconds + millis / 1_000
    }
}
