import Foundation

enum ModelPipelineStage: String, Equatable {
    case idle
    case downloading
    case optimizing
    case loading
    case ready
    case transcribing

    var title: String {
        switch self {
        case .idle: "Ready"
        case .downloading: "Downloading model"
        case .optimizing: "Optimizing for your chip"
        case .loading: "Loading model"
        case .ready: "Model ready"
        case .transcribing: "Transcribing video"
        }
    }
}

@MainActor
@Observable
final class ModelDownloadCoordinator {
    var stage: ModelPipelineStage = .idle
    var progress: Double = 0
    var detailText: String = ""
    var computeSummary: String = ""
    var isActive: Bool = false

    func reset() {
        stage = .idle
        progress = 0
        detailText = ""
        computeSummary = ""
        isActive = false
    }

    func begin(stage: ModelPipelineStage, detail: String = "") {
        isActive = true
        self.stage = stage
        detailText = detail
    }

    func updateDownload(_ progress: Progress) {
        stage = .downloading
        isActive = true
        self.progress = progress.fractionCompleted

        let completed = progress.completedUnitCount
        let total = progress.totalUnitCount
        if total > 0 {
            detailText = "\(formatBytes(completed)) of \(formatBytes(total))"
        } else {
            detailText = "Fetching model files from HuggingFace…"
        }
    }

    func updateOptimizing() {
        stage = .optimizing
        progress = max(progress, 0.9)
        detailText = "Core ML is specializing the model for your Apple Silicon chip. This is a one-time step per model."
    }

    func updateLoading() {
        stage = .loading
        progress = max(progress, 0.95)
        detailText = "Loading optimized model into memory…"
    }

    func updateReady() {
        stage = .ready
        progress = 1
        detailText = "Model is ready to transcribe."
    }

    func updateTranscribing(videoName: String) {
        stage = .transcribing
        progress = 1
        detailText = "Transcribing \(videoName)…"
    }

    func finish() {
        isActive = false
        stage = .ready
        progress = 1
    }

    func setComputeSummary(_ summary: String) {
        computeSummary = summary
    }

    func applyDownloadSnapshot(fraction: Double, completed: Int64, total: Int64) {
        stage = .downloading
        isActive = true
        progress = fraction

        if total > 0 {
            detailText = "\(formatBytes(completed)) of \(formatBytes(total))"
        } else if fraction > 0 {
            detailText = "Downloading model files…"
        }
    }

    private func formatBytes(_ value: Int64) -> String {
        guard value > 0 else { return "0 B" }
        let units = ["B", "KB", "MB", "GB"]
        var amount = Double(value)
        var unitIndex = 0
        while amount >= 1024, unitIndex < units.count - 1 {
            amount /= 1024
            unitIndex += 1
        }
        return String(format: unitIndex == 0 ? "%.0f %@" : "%.1f %@", amount, units[unitIndex])
    }
}

struct ModelDownloadSnapshot {
    let fraction: Double
    let completed: Int64
    let total: Int64
}

final class ModelDownloadProgressBox: @unchecked Sendable {
    private let lock = NSLock()
    private nonisolated(unsafe) var fraction: Double = 0
    private nonisolated(unsafe) var completed: Int64 = 0
    private nonisolated(unsafe) var total: Int64 = 0

    nonisolated func update(_ progress: Progress) {
        lock.lock()
        fraction = progress.fractionCompleted
        completed = progress.completedUnitCount
        total = progress.totalUnitCount
        lock.unlock()
    }

    nonisolated var snapshot: ModelDownloadSnapshot {
        lock.lock()
        defer { lock.unlock() }
        return ModelDownloadSnapshot(fraction: fraction, completed: completed, total: total)
    }
}
