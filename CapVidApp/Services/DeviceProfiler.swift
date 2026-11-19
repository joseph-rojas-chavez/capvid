import Foundation
@preconcurrency import WhisperKit

enum DeviceProfiler {
    static func loadProfile(settings: AppSettings) async -> DeviceProfile {
        let modelIdentifier = WhisperKit.deviceName()
        let memoryGB = max(1, Int(ProcessInfo.processInfo.physicalMemory / 1_073_741_824))
        let processorCount = ProcessInfo.processInfo.processorCount
        let chipFamily = chipFamily(for: modelIdentifier)

        let localSupport = WhisperKit.recommendedModels()
        let remoteSupport = await WhisperKit.recommendedRemoteModels()
        let mergedSupport = mergeSupport(local: localSupport, remote: remoteSupport)

        return WhisperModelCatalog.buildProfile(
            modelIdentifier: modelIdentifier,
            chipFamily: chipFamily,
            memoryGB: memoryGB,
            processorCount: processorCount,
            modelSupport: mergedSupport,
            settings: settings
        )
    }

    static func chipFamily(for modelIdentifier: String) -> String {
        if modelIdentifier.hasPrefix("Mac16") || modelIdentifier.hasPrefix("Mac15") || modelIdentifier.hasPrefix("Mac14") {
            return "Apple M2/M3/M4"
        }

        if modelIdentifier.hasPrefix("Mac13")
            || modelIdentifier.hasPrefix("MacBookPro17")
            || modelIdentifier.hasPrefix("MacBookPro18")
            || modelIdentifier.hasPrefix("MacBookAir10")
            || modelIdentifier.hasPrefix("Macmini9")
            || modelIdentifier.hasPrefix("iMac21") {
            return "Apple M1"
        }

        if modelIdentifier.hasPrefix("Mac") || modelIdentifier.hasPrefix("iMac") {
            return "Apple Silicon"
        }

        return "This Mac"
    }

    private static func mergeSupport(local: ModelSupport, remote: ModelSupport) -> ModelSupportSnapshot {
        let supported = Array(Set(local.supported + remote.supported)).sorted()
        let defaultModel = remote.default.isEmpty ? local.default : remote.default
        return ModelSupportSnapshot(default: defaultModel, supported: supported)
    }
}
