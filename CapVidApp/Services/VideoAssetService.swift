import AVFoundation
import Foundation

enum VideoAssetService {
    static func loadDurations(for url: URL) async throws -> (
        assetDuration: TimeInterval,
        videoTrackDuration: TimeInterval?,
        audioTrackDuration: TimeInterval?
    ) {
        let asset = AVURLAsset(url: url)

        let assetDuration = try await asset.load(.duration).seconds
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)

        let videoTrackDuration = try await videoTracks.first?.load(.timeRange).duration.seconds
        let audioTrackDuration = try await audioTracks.first?.load(.timeRange).duration.seconds

        return (assetDuration, videoTrackDuration, audioTrackDuration)
    }

    static func extractAudioURL(from videoURL: URL) async throws -> URL {
        let asset = AVURLAsset(url: videoURL)
        guard try await asset.loadTracks(withMediaType: .audio).isEmpty == false else {
            throw VideoAssetError.noAudioTrack
        }

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("capvid-audio-\(UUID().uuidString).m4a")

        guard let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            throw VideoAssetError.exportFailed
        }

        exportSession.outputURL = outputURL
        exportSession.outputFileType = .m4a

        await exportSession.export()

        guard exportSession.status == .completed else {
            throw exportSession.error ?? VideoAssetError.exportFailed
        }

        return outputURL
    }
}

enum VideoAssetError: LocalizedError {
    case noAudioTrack
    case exportFailed

    var errorDescription: String? {
        switch self {
        case .noAudioTrack:
            "This video does not contain an audio track to transcribe."
        case .exportFailed:
            "Could not extract audio from the selected video."
        }
    }
}

private extension CMTime {
    var seconds: TimeInterval {
        CMTimeGetSeconds(self)
    }
}
