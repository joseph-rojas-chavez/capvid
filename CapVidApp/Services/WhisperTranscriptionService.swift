import CapVid
import CoreML
import Foundation
@preconcurrency import WhisperKit

/// On-device English transcription with user-selected Whisper models.
@MainActor
final class WhisperTranscriptionService {
    private var whisperKit: WhisperKit?
    private var loadedModelName: String?
    private var cachedModelFolders: [String: URL] = [:]

    let downloadCoordinator = ModelDownloadCoordinator()

    var loadedModel: String? { loadedModelName }

    func unloadModel() {
        whisperKit = nil
        loadedModelName = nil
    }

    func prepare(
        model: String,
        deviceProfile: DeviceProfile
    ) async throws {
        if loadedModelName == model, whisperKit != nil {
            downloadCoordinator.updateReady()
            return
        }

        whisperKit = nil
        loadedModelName = nil

        downloadCoordinator.begin(stage: .downloading, detail: "Preparing \(model)…")
        downloadCoordinator.setComputeSummary(computeSummary(for: deviceProfile))

        let modelFolder = try await resolveModelFolder(for: model)

        let computeOptions = computeOptions(for: deviceProfile)
        let config = WhisperKitConfig(
            model: model,
            modelRepo: WhisperModelRepository.repo,
            modelFolder: modelFolder.path(percentEncoded: false),
            computeOptions: computeOptions,
            verbose: false,
            logLevel: .error,
            prewarm: true,
            load: false,
            download: false
        )

        downloadCoordinator.updateOptimizing()
        let pipe = try await WhisperKit(config)

        pipe.modelStateCallback = { [weak self] _, newState in
            Task { @MainActor in
                self?.handleModelState(newState)
            }
        }

        downloadCoordinator.updateLoading()
        try await pipe.loadModels()
        try await pipe.prewarmModels()

        whisperKit = pipe
        loadedModelName = model
        downloadCoordinator.updateReady()
    }

    func downloadOnly(model: String, deviceProfile: DeviceProfile) async throws {
        try await prepare(model: model, deviceProfile: deviceProfile)
        downloadCoordinator.finish()
    }

    func transcribe(
        videoURL: URL,
        model: String,
        language: TranscriptionLanguage,
        deviceProfile: DeviceProfile,
        videoDisplayName: String
    ) async throws -> [CapVid.TranscriptionSegment] {
        try await prepare(model: model, deviceProfile: deviceProfile)
        downloadCoordinator.updateTranscribing(videoName: videoDisplayName)

        guard let whisperKit else {
            throw WhisperTranscriptionError.modelUnavailable(model)
        }

        let audioURL = try await VideoAssetService.extractAudioURL(from: videoURL)
        defer { try? FileManager.default.removeItem(at: audioURL) }

        let usesAutoDetect = language == .auto
        let options = DecodingOptions(
            task: .transcribe,
            language: usesAutoDetect ? nil : language.rawValue,
            detectLanguage: usesAutoDetect,
            skipSpecialTokens: true,
            wordTimestamps: false,
            concurrentWorkerCount: concurrentWorkers(for: deviceProfile)
        )

        let results = try await whisperKit.transcribe(
            audioPath: audioURL.path(percentEncoded: false),
            decodeOptions: options
        )

        var segments: [CapVid.TranscriptionSegment] = []
        var index = 1

        for result in results {
            for segment in result.segments {
                let text = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { continue }

                segments.append(
                    CapVid.TranscriptionSegment(
                        index: index,
                        startTime: TimeInterval(segment.start),
                        endTime: TimeInterval(segment.end),
                        text: text
                    )
                )
                index += 1
            }
        }

        downloadCoordinator.finish()
        return segments
    }

    private func resolveModelFolder(for model: String) async throws -> URL {
        if let cached = cachedModelFolders[model],
           FileManager.default.fileExists(atPath: cached.path) {
            downloadCoordinator.progress = 1
            downloadCoordinator.detailText = "Using cached model on disk."
            return cached
        }

        let progressBox = ModelDownloadProgressBox()
        let pollTask = Task { @MainActor [downloadCoordinator] in
            while !Task.isCancelled {
                let snapshot = progressBox.snapshot
                downloadCoordinator.applyDownloadSnapshot(
                    fraction: snapshot.fraction,
                    completed: snapshot.completed,
                    total: snapshot.total
                )
                try? await Task.sleep(for: .milliseconds(80))
            }
        }
        defer { pollTask.cancel() }

        let folder = try await Self.fetchModelFolder(
            model: model,
            downloadBase: WhisperModelRepository.downloadBase,
            progressBox: progressBox
        )

        cachedModelFolders[model] = folder
        return folder
    }

    private nonisolated static func fetchModelFolder(
        model: String,
        downloadBase: URL,
        progressBox: ModelDownloadProgressBox
    ) async throws -> URL {
        try await WhisperKit.download(
            variant: model,
            downloadBase: downloadBase,
            from: WhisperModelRepository.repo,
            progressCallback: { progress in
                progressBox.update(progress)
            }
        )
    }

    private func handleModelState(_ state: ModelState) {
        switch state {
        case .prewarming:
            downloadCoordinator.updateOptimizing()
        case .loading:
            downloadCoordinator.updateLoading()
        case .loaded:
            downloadCoordinator.updateReady()
        default:
            break
        }
    }

    private func computeOptions(for profile: DeviceProfile) -> ModelComputeOptions {
        if profile.memoryGB < 8 {
            return ModelComputeOptions(
                melCompute: .cpuAndGPU,
                audioEncoderCompute: .cpuAndGPU,
                textDecoderCompute: .cpuAndGPU
            )
        }

        if profile.chipFamily.contains("M1") {
            return ModelComputeOptions(
                melCompute: .cpuAndGPU,
                audioEncoderCompute: .cpuAndNeuralEngine,
                textDecoderCompute: .cpuAndNeuralEngine
            )
        }

        return ModelComputeOptions(
            melCompute: .cpuAndGPU,
            audioEncoderCompute: .cpuAndNeuralEngine,
            textDecoderCompute: .cpuAndNeuralEngine
        )
    }

    private func computeSummary(for profile: DeviceProfile) -> String {
        if profile.memoryGB < 8 {
            return "Optimizer: GPU-only mode for low-memory Macs (\(profile.memoryGB) GB RAM)."
        }

        if profile.chipFamily.contains("M1") {
            return "Optimizer: Neural Engine + GPU tuned for \(profile.chipFamily)."
        }

        return "Optimizer: Neural Engine + GPU tuned for \(profile.chipFamily) with \(concurrentWorkers(for: profile)) transcription workers."
    }

    private func concurrentWorkers(for profile: DeviceProfile) -> Int {
        switch profile.memoryGB {
        case ..<8:
            return 1
        case 8..<16:
            return min(2, max(1, profile.processorCount / 4))
        default:
            return min(4, max(2, profile.processorCount / 3))
        }
    }
}

enum WhisperModelRepository {
    static let repo = "argmaxinc/whisperkit-coreml"

    static var downloadBase: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let folder = base.appendingPathComponent("CapVid/Models", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }
}

enum WhisperTranscriptionError: LocalizedError {
    case modelUnavailable(String)
    case modelNotSupported(String)

    var errorDescription: String? {
        switch self {
        case .modelUnavailable(let model):
            "The Whisper \(model) model could not be loaded."
        case .modelNotSupported(let model):
            "\(model) is not recommended for this Mac. Choose a smaller English model."
        }
    }
}
