import Foundation
import UniformTypeIdentifiers

enum MergeFileKind {
    case video
    case caption
}

enum MergeFileClassifier {
    private static let videoExtensions: Set<String> = [
        "mp4", "mov", "mkv", "m4v", "avi", "webm", "mpg", "mpeg", "m4a", "mp3", "wav",
    ]

    private static let captionExtensions: Set<String> = [
        "srt", "vtt", "txt",
    ]

    static func kind(for url: URL) -> MergeFileKind? {
        let ext = url.pathExtension.lowercased()

        if captionExtensions.contains(ext) {
            return .caption
        }

        if videoExtensions.contains(ext) {
            return .video
        }

        if let type = UTType(filenameExtension: ext) {
            if type.conforms(to: .movie) || type.conforms(to: .video) || type.conforms(to: .audio) {
                return .video
            }
            if type.conforms(to: .plainText) || type.conforms(to: .text) {
                return .caption
            }
        }

        return nil
    }

    static var videoContentTypes: [UTType] {
        [.movie, .mpeg4Movie, .quickTimeMovie, .video, .mpeg4Audio, .mp3, .audio]
    }

    static var captionContentTypes: [UTType] {
        var types: [UTType] = [.plainText, .text]
        if let srt = UTType(filenameExtension: "srt") {
            types.append(srt)
        }
        if let vtt = UTType(filenameExtension: "vtt") {
            types.append(vtt)
        }
        return types
    }

    static var allContentTypes: [UTType] {
        Array(Set(videoContentTypes + captionContentTypes))
    }
}
