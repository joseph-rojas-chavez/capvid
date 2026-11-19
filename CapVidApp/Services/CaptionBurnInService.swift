import AVFoundation
import AppKit
import CapVid
import Foundation
import QuartzCore

struct CaptionBurnInStyle {
    var fontName: String = CaptionFontCatalog.defaultFont
    var fontSize: CGFloat = CGFloat(CaptionFontCatalog.defaultSize)
}

enum CaptionBurnInService {
    enum BurnInError: LocalizedError {
        case noVideoTrack
        case noCaptions
        case compositionFailed
        case exportFailed

        var errorDescription: String? {
            switch self {
            case .noVideoTrack:
                "The selected video does not contain a video track."
            case .noCaptions:
                "No captions were found in the caption file."
            case .compositionFailed:
                "Could not prepare the captioned video composition."
            case .exportFailed:
                "Could not export the captioned video."
            }
        }
    }

    private static let fadeDuration: TimeInterval = 0.12

    static func export(
        videoURL: URL,
        captionURL: URL,
        outputURL: URL,
        style: CaptionBurnInStyle = CaptionBurnInStyle(),
        progress: @escaping @Sendable (Double) -> Void
    ) async throws {
        let rawSegments = try CaptionFileParser.parse(url: captionURL)
        try await export(
            videoURL: videoURL,
            segments: rawSegments,
            outputURL: outputURL,
            style: style,
            progress: progress
        )
    }

    static func export(
        videoURL: URL,
        segments: [TranscriptionSegment],
        outputURL: URL,
        style: CaptionBurnInStyle = CaptionBurnInStyle(),
        progress: @escaping @Sendable (Double) -> Void
    ) async throws {
        let asset = AVURLAsset(url: videoURL)
        let duration = try await asset.load(.duration)
        let timelineEnd = max(duration.seconds, CaptionTimeline.minimumTimelineEnd)
        let timedSegments = CaptionTimeline.timedForBurnIn(segments, timelineEnd: timelineEnd)

        guard timedSegments.isEmpty == false else {
            throw BurnInError.noCaptions
        }

        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }

        try await burn(
            asset: asset,
            segments: timedSegments,
            outputURL: outputURL,
            style: style,
            progress: progress
        )
    }

    private static func burn(
        asset: AVURLAsset,
        segments: [TranscriptionSegment],
        outputURL: URL,
        style: CaptionBurnInStyle,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws {
        let duration = try await asset.load(.duration)
        let totalDuration = max(duration.seconds, CaptionTimeline.minimumTimelineEnd)
        let sourceVideoTracks = try await asset.loadTracks(withMediaType: .video)
        guard let sourceVideoTrack = sourceVideoTracks.first else {
            throw BurnInError.noVideoTrack
        }

        let naturalSize = try await sourceVideoTrack.load(.naturalSize)
        let preferredTransform = try await sourceVideoTrack.load(.preferredTransform)
        let nominalFrameRate = try await sourceVideoTrack.load(.nominalFrameRate)
        let renderSize = displaySize(naturalSize: naturalSize, transform: preferredTransform)

        let composition = AVMutableComposition()
        guard let compositionVideoTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw BurnInError.compositionFailed
        }

        let sourceRange = CMTimeRange(start: .zero, duration: duration)
        try compositionVideoTrack.insertTimeRange(sourceRange, of: sourceVideoTrack, at: .zero)
        compositionVideoTrack.preferredTransform = preferredTransform

        let sourceAudioTracks = try await asset.loadTracks(withMediaType: .audio)
        if let sourceAudioTrack = sourceAudioTracks.first,
           let compositionAudioTrack = composition.addMutableTrack(
               withMediaType: .audio,
               preferredTrackID: kCMPersistentTrackID_Invalid
           ) {
            try compositionAudioTrack.insertTimeRange(sourceRange, of: sourceAudioTrack, at: .zero)
        }

        let parentLayer = CALayer()
        let videoLayer = CALayer()
        parentLayer.frame = CGRect(origin: .zero, size: renderSize)
        parentLayer.beginTime = AVCoreAnimationBeginTimeAtZero
        parentLayer.speed = 1
        videoLayer.frame = parentLayer.frame
        parentLayer.addSublayer(videoLayer)

        for segment in segments {
            let captionLayer = makeCaptionLayer(
                text: segment.text,
                renderSize: renderSize,
                style: style
            )
            applyTiming(
                to: captionLayer,
                start: segment.startTime,
                end: segment.endTime,
                totalDuration: totalDuration
            )
            parentLayer.addSublayer(captionLayer)
        }

        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = sourceRange

        let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: compositionVideoTrack)
        layerInstruction.setTransform(preferredTransform, at: .zero)
        instruction.layerInstructions = [layerInstruction]

        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = renderSize
        videoComposition.frameDuration = frameDuration(for: nominalFrameRate)
        videoComposition.instructions = [instruction]
        videoComposition.animationTool = AVVideoCompositionCoreAnimationTool(
            postProcessingAsVideoLayer: videoLayer,
            in: parentLayer
        )

        guard let exportSession = AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPresetHighestQuality
        ) else {
            throw BurnInError.exportFailed
        }

        exportSession.outputURL = outputURL
        exportSession.outputFileType = outputFileType(for: outputURL)
        exportSession.videoComposition = videoComposition
        exportSession.shouldOptimizeForNetworkUse = true

        let progressTask = Task {
            while Task.isCancelled == false {
                let status = exportSession.status
                if status == .exporting || status == .waiting {
                    progress(Double(exportSession.progress))
                }
                if status != .waiting && status != .exporting {
                    break
                }
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
        }

        await exportSession.export()
        progressTask.cancel()
        progress(1)

        guard exportSession.status == .completed else {
            throw exportSession.error ?? BurnInError.exportFailed
        }
    }

    private static func makeCaptionLayer(
        text: String,
        renderSize: CGSize,
        style: CaptionBurnInStyle
    ) -> CALayer {
        let font = NSFont(name: style.fontName, size: style.fontSize)
            ?? NSFont.systemFont(ofSize: style.fontSize, weight: .medium)

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = .byWordWrapping

        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.white,
            .paragraphStyle: paragraph,
        ]

        let maxTextWidth = min(renderSize.width * 0.82, 520)
        let attributed = NSAttributedString(string: text, attributes: attributes)
        let textBounds = attributed.boundingRect(
            with: CGSize(width: maxTextWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        ).integral

        let paddingH: CGFloat = 18
        let paddingV: CGFloat = 10
        let backgroundWidth = min(renderSize.width * 0.9, textBounds.width + paddingH * 2)
        let backgroundHeight = textBounds.height + paddingV * 2
        let originX = (renderSize.width - backgroundWidth) / 2
        let originY: CGFloat = 36

        let backgroundLayer = CALayer()
        backgroundLayer.backgroundColor = NSColor.black.withAlphaComponent(0.72).cgColor
        backgroundLayer.cornerRadius = 14
        backgroundLayer.masksToBounds = true
        backgroundLayer.frame = CGRect(
            x: originX,
            y: originY,
            width: backgroundWidth,
            height: backgroundHeight
        )

        let textLayer = CATextLayer()
        textLayer.contentsScale = NSScreen.main?.backingScaleFactor ?? 2
        textLayer.string = attributed
        textLayer.alignmentMode = .center
        textLayer.isWrapped = true
        textLayer.frame = CGRect(
            x: paddingH,
            y: paddingV,
            width: backgroundWidth - paddingH * 2,
            height: textBounds.height
        )

        backgroundLayer.addSublayer(textLayer)
        return backgroundLayer
    }

    private static func applyTiming(
        to layer: CALayer,
        start: TimeInterval,
        end: TimeInterval,
        totalDuration: TimeInterval
    ) {
        guard totalDuration > 0, end > start else {
            layer.opacity = 0
            return
        }

        let segmentDuration = end - start
        let fadeIn = min(fadeDuration, segmentDuration / 3)
        let fadeOut = min(fadeDuration, segmentDuration / 3)
        let visibleStart = start
        let visibleEnd = end
        let fadeInEnd = min(visibleEnd, visibleStart + fadeIn)
        let fadeOutStart = max(fadeInEnd, visibleEnd - fadeOut)

        let keyTimes = monotonicKeyTimes(
            totalDuration: totalDuration,
            points: [0, visibleStart, fadeInEnd, fadeOutStart, visibleEnd, totalDuration]
        )

        let animation = CAKeyframeAnimation(keyPath: "opacity")
        animation.values = [0, 0, 1, 1, 0, 0]
        animation.keyTimes = keyTimes
        animation.duration = totalDuration
        animation.beginTime = AVCoreAnimationBeginTimeAtZero
        animation.fillMode = .both
        animation.isRemovedOnCompletion = false
        animation.calculationMode = .linear

        layer.opacity = 0
        layer.add(animation, forKey: "opacity")
    }

    private static func monotonicKeyTimes(
        totalDuration: TimeInterval,
        points: [TimeInterval]
    ) -> [NSNumber] {
        var normalized = points.map { min(1, max(0, $0 / totalDuration)) }
        for index in 1 ..< normalized.count {
            if normalized[index] <= normalized[index - 1] {
                normalized[index] = min(1, normalized[index - 1] + 0.0001)
            }
        }
        normalized[normalized.count - 1] = 1
        return normalized.map { NSNumber(value: $0) }
    }

    private static func frameDuration(for nominalFrameRate: Float) -> CMTime {
        let fps = max(nominalFrameRate, 30)
        return CMTime(value: 1, timescale: CMTimeScale(fps.rounded()))
    }

    private static func displaySize(naturalSize: CGSize, transform: CGAffineTransform) -> CGSize {
        let rect = CGRect(origin: .zero, size: naturalSize).applying(transform)
        return CGSize(width: abs(rect.width), height: abs(rect.height))
    }

    private static func outputFileType(for url: URL) -> AVFileType {
        switch url.pathExtension.lowercased() {
        case "mov":
            return .mov
        default:
            return .mp4
        }
    }
}

private extension CMTime {
    var seconds: TimeInterval {
        CMTimeGetSeconds(self)
    }
}
