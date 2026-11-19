import CapVid
import Foundation
import Observation

enum TranscriptionPhase: Equatable {
    case idle
    case loadingRecommendations
    case downloadingModel
    case transcribing
    case completed
    case failed(String)
}

enum MergePhase: Equatable {
    case idle
    case exporting
    case completed
    case failed(String)
}

enum CaptionBurnPhase: Equatable {
    case idle
    case exporting
    case completed
    case failed(String)
}

@MainActor
@Observable
final class ProjectViewModel {
    var settings: AppSettings
    var showWelcomeSettings = false

    var videoURL: URL?
    var videoDisplayName: String = "No video selected"

    var assetDuration: TimeInterval?
    var videoTrackDuration: TimeInterval?
    var audioTrackDuration: TimeInterval?

    var rawSegments: [TranscriptionSegment] = []
    var editableSegments: [TranscriptionSegment] = []

    var captionFontName: String = CaptionFontCatalog.defaultFont
    var captionFontSize: Int = CaptionFontCatalog.defaultSize
    var previewSegmentIndex: Int = 0

    var transcriptionPhase: TranscriptionPhase = .idle
    var transcriptionProgress: Double = 0
    var statusMessage: String?

    var deviceProfile: DeviceProfile?
    var selectedModelID: String?

    var mergeVideoURL: URL?
    var mergeSRTURL: URL?
    var mergeVideoDisplayName: String = "Not selected"
    var mergeSRTDisplayName: String = "Not selected"
    var mergeStatusMessage: String?
    var mergePhase: MergePhase = .idle
    var mergeProgress: Double = 0

    var captionBurnPhase: CaptionBurnPhase = .idle
    var captionBurnProgress: Double = 0

    private let transcriptionService = WhisperTranscriptionService()
    private var securityScopedVideoURL: URL?
    private var securityScopedMergeVideoURL: URL?
    private var securityScopedMergeSRTURL: URL?

    init(settings: AppSettings = AppSettingsStore.load()) {
        self.settings = settings
        self.showWelcomeSettings = !settings.hasCompletedWelcome
        self.selectedModelID = nil
    }

    var modelDownloadCoordinator: ModelDownloadCoordinator {
        transcriptionService.downloadCoordinator
    }

    var exportTimelineSeconds: TimeInterval {
        CaptionTimeline.compositionDurationSeconds(
            assetDuration: assetDuration,
            videoTrackDuration: videoTrackDuration,
            audioTrackDuration: audioTrackDuration
        )
    }

    var sanitizedSegments: [TranscriptionSegment] {
        CaptionTimeline.sanitizedForBurn(editableSegments, timelineEnd: exportTimelineSeconds)
    }

    var previewCaptionText: String {
        if sanitizedSegments.isEmpty {
            return "Generate captions to preview styling on your video."
        }
        let index = min(max(previewSegmentIndex, 0), sanitizedSegments.count - 1)
        return sanitizedSegments[index].text
    }

    var tierOptions: [WhisperTierOption] {
        tierOptions(for: settings.language)
    }

    func tierOptions(for language: TranscriptionLanguage) -> [WhisperTierOption] {
        guard let profile = deviceProfile else { return [] }
        let recommended = WhisperModelCatalog.recommendedTier(
            memoryGB: profile.memoryGB,
            processorCount: profile.processorCount
        )
        return ModelSizeTier.allCases.map { tier in
            WhisperModelCatalog.tierOption(
                tier: tier,
                language: language,
                supported: profile.supportedModels,
                memoryGB: profile.memoryGB,
                processorCount: profile.processorCount,
                recommendedTier: recommended
            )
        }
    }

    var selectedTierOption: WhisperTierOption? {
        deviceProfile?.tierOption(for: settings.modelTier)
    }

    var settingsSummary: String {
        "\(settings.modelTier.modelVariant(for: settings.language)) · \(settings.language.displayName)"
    }

    var selectedModelWarning: String? {
        guard let option = selectedTierOption else { return nil }
        if case .warning(let message) = option.fitLevel {
            return message
        }
        return nil
    }

    var canTranscribe: Bool {
        videoURL != nil
            && selectedModelID != nil
            && transcriptionPhase != .downloadingModel
            && transcriptionPhase != .transcribing
            && transcriptionPhase != .loadingRecommendations
    }

    var canMerge: Bool {
        mergeVideoURL != nil
            && mergeSRTURL != nil
            && mergePhase != .exporting
    }

    var hasMergeFiles: Bool {
        mergeVideoURL != nil || mergeSRTURL != nil
    }

    var hasVideo: Bool { videoURL != nil }

    var canExportCaptionedVideo: Bool {
        videoURL != nil
            && sanitizedSegments.isEmpty == false
            && captionBurnPhase != .exporting
    }

    func bootstrap() {
        if settings.hasCompletedWelcome {
            loadModelRecommendationsIfNeeded()
        }
    }

    func openSettings() {
        showWelcomeSettings = true
    }

    func applySettings(
        tier: ModelSizeTier,
        language: TranscriptionLanguage,
        markWelcomeComplete: Bool
    ) {
        let modelChanged = settings.modelTier != tier || settings.language != language

        settings.modelTier = tier
        settings.language = language
        if markWelcomeComplete {
            settings.hasCompletedWelcome = true
        }
        AppSettingsStore.save(settings)

        if modelChanged {
            transcriptionService.unloadModel()
            selectedModelID = nil
        }

        showWelcomeSettings = false
        reloadDeviceProfile()
    }

    func loadModelRecommendationsIfNeeded() {
        guard transcriptionPhase != .loadingRecommendations else { return }
        reloadDeviceProfile()
    }

    func reloadDeviceProfile() {
        transcriptionPhase = .loadingRecommendations

        Task {
            do {
                let profile = await DeviceProfiler.loadProfile(settings: settings)
                deviceProfile = profile
                selectedModelID = profile.selectedModelID
                transcriptionPhase = .idle

                if let modelID = profile.selectedModelID {
                    statusMessage = "Using \(settings.modelTier.modelVariant(for: settings.language)) → \(modelID)"
                } else {
                    statusMessage = "Could not resolve a model for \(settings.modelTier.title). Open settings to choose another."
                }
            } catch {
                transcriptionPhase = .failed(error.localizedDescription)
                statusMessage = error.localizedDescription
            }
        }
    }

    func selectVideo(_ url: URL) {
        releaseSecurityScopedAccess(for: &securityScopedVideoURL)
        if url.startAccessingSecurityScopedResource() {
            securityScopedVideoURL = url
        }

        videoURL = url
        videoDisplayName = url.lastPathComponent
        rawSegments = []
        editableSegments = []
        previewSegmentIndex = 0
        transcriptionPhase = .idle
        transcriptionProgress = 0
        captionBurnPhase = .idle
        captionBurnProgress = 0
        statusMessage = nil

        Task {
            await loadVideoMetadata()
        }
    }

    func selectMergeVideo(_ url: URL) {
        releaseSecurityScopedAccess(for: &securityScopedMergeVideoURL)
        if url.startAccessingSecurityScopedResource() {
            securityScopedMergeVideoURL = url
        }

        mergeVideoURL = url
        mergeVideoDisplayName = url.lastPathComponent
        mergePhase = .idle
        mergeProgress = 0
        updateMergeStatusMessage()
    }

    func selectMergeSRT(_ url: URL) {
        releaseSecurityScopedAccess(for: &securityScopedMergeSRTURL)
        if url.startAccessingSecurityScopedResource() {
            securityScopedMergeSRTURL = url
        }

        mergeSRTURL = url
        mergeSRTDisplayName = url.lastPathComponent
        mergePhase = .idle
        mergeProgress = 0
        updateMergeStatusMessage()
    }

    func registerMergeFiles(from urls: [URL]) {
        var unrecognized: [String] = []

        for url in urls {
            switch MergeFileClassifier.kind(for: url) {
            case .video:
                selectMergeVideo(url)
            case .caption:
                selectMergeSRT(url)
            case nil:
                unrecognized.append(url.lastPathComponent)
            }
        }

        if unrecognized.isEmpty == false {
            mergeStatusMessage = "Couldn't recognize: \(unrecognized.joined(separator: ", ")). Use MP4/MOV for video and SRT for captions."
        } else {
            updateMergeStatusMessage()
        }
    }

    private func updateMergeStatusMessage() {
        switch (mergeVideoURL, mergeSRTURL) {
        case (nil, nil):
            mergeStatusMessage = nil
        case (nil, _):
            mergeStatusMessage = "Caption file ready. Drop or browse for a video file."
        case (_, nil):
            mergeStatusMessage = "Video ready. Drop or browse for an SRT caption file."
        case (_, _):
            mergeStatusMessage = "Ready to merge \(mergeVideoDisplayName) with \(mergeSRTDisplayName)."
        }
    }

    func mergeAndBurnCaptions() {
        guard let videoURL = mergeVideoURL, let captionURL = mergeSRTURL else { return }

        let baseName = (mergeVideoDisplayName as NSString).deletingPathExtension
        let defaultName = "\(baseName)-captioned"

        guard let outputURL = ExportSavePanel.chooseVideoDestination(defaultFilename: defaultName) else {
            mergeStatusMessage = "Export cancelled."
            return
        }

        mergePhase = .exporting
        mergeProgress = 0
        mergeStatusMessage = "Burning captions into video…"

        Task {
            do {
                let accessed = outputURL.startAccessingSecurityScopedResource()
                defer {
                    if accessed {
                        outputURL.stopAccessingSecurityScopedResource()
                    }
                }

                try await CaptionBurnInService.export(
                    videoURL: videoURL,
                    captionURL: captionURL,
                    outputURL: outputURL,
                    progress: { [weak self] value in
                        Task { @MainActor in
                            self?.mergeProgress = value
                        }
                    }
                )

                mergePhase = .completed
                mergeProgress = 1
                mergeStatusMessage = "Saved captioned video to \(outputURL.path)."
            } catch {
                mergePhase = .failed(error.localizedDescription)
                mergeStatusMessage = error.localizedDescription
            }
        }
    }

    func exportCaptionedVideo() {
        guard let videoURL, sanitizedSegments.isEmpty == false else { return }

        let baseName = (videoDisplayName as NSString).deletingPathExtension
        let defaultName = "\(baseName)-captioned"

        guard let outputURL = ExportSavePanel.chooseVideoDestination(defaultFilename: defaultName) else {
            statusMessage = "Export cancelled."
            return
        }

        captionBurnPhase = .exporting
        captionBurnProgress = 0
        statusMessage = "Burning captions into video…"

        let style = CaptionBurnInStyle(
            fontName: captionFontName,
            fontSize: CGFloat(captionFontSize)
        )

        Task {
            do {
                let accessed = outputURL.startAccessingSecurityScopedResource()
                defer {
                    if accessed {
                        outputURL.stopAccessingSecurityScopedResource()
                    }
                }

                try await CaptionBurnInService.export(
                    videoURL: videoURL,
                    segments: sanitizedSegments,
                    outputURL: outputURL,
                    style: style,
                    progress: { [weak self] value in
                        Task { @MainActor in
                            self?.captionBurnProgress = value
                        }
                    }
                )

                captionBurnPhase = .completed
                captionBurnProgress = 1
                statusMessage = "Saved captioned video to \(outputURL.lastPathComponent)."
            } catch {
                captionBurnPhase = .failed(error.localizedDescription)
                statusMessage = error.localizedDescription
            }
        }
    }

    func loadVideoMetadata() async {
        guard let videoURL else { return }

        do {
            let durations = try await VideoAssetService.loadDurations(for: videoURL)
            assetDuration = durations.assetDuration
            videoTrackDuration = durations.videoTrackDuration
            audioTrackDuration = durations.audioTrackDuration
            statusMessage = "Loaded \(videoDisplayName)."
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func generateCaptions() {
        guard let videoURL, let modelID = selectedModelID, let profile = deviceProfile else { return }

        transcriptionPhase = .downloadingModel
        transcriptionProgress = 0
        statusMessage = "Preparing \(settings.modelTier.title) model…"
        modelDownloadCoordinator.reset()

        Task {
            do {
                let segments = try await transcriptionService.transcribe(
                    videoURL: videoURL,
                    model: modelID,
                    language: settings.language,
                    deviceProfile: profile,
                    videoDisplayName: videoDisplayName
                )

                rawSegments = segments
                editableSegments = segments
                previewSegmentIndex = 0
                transcriptionPhase = .completed
                transcriptionProgress = 1
                statusMessage = "Created \(segments.count) captions for \(videoDisplayName)."
            } catch {
                transcriptionPhase = .failed(error.localizedDescription)
                statusMessage = error.localizedDescription
                modelDownloadCoordinator.reset()
            }
        }
    }

    func updateSegmentText(id: Int, text: String) {
        guard let index = editableSegments.firstIndex(where: { $0.id == id }) else { return }
        editableSegments[index].text = text
    }

    func exportCaptionText() -> String {
        sanitizedSegments
            .map { segment in
                let start = formatSRTTime(segment.startTime)
                let end = formatSRTTime(segment.endTime)
                return "\(segment.index)\n\(start) --> \(end)\n\(segment.text)\n"
            }
            .joined(separator: "\n")
    }

    private func releaseSecurityScopedAccess(for scopedURL: inout URL?) {
        scopedURL?.stopAccessingSecurityScopedResource()
        scopedURL = nil
    }

    private func formatSRTTime(_ seconds: TimeInterval) -> String {
        let totalMilliseconds = max(0, Int((seconds * 1000).rounded()))
        let hours = totalMilliseconds / 3_600_000
        let minutes = (totalMilliseconds % 3_600_000) / 60_000
        let secs = (totalMilliseconds % 60_000) / 1000
        let millis = totalMilliseconds % 1000
        return String(format: "%02d:%02d:%02d,%03d", hours, minutes, secs, millis)
    }
}
