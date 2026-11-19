import Foundation

enum WhisperModelCatalog {
    static func whisperModelID(
        tier: ModelSizeTier,
        language: TranscriptionLanguage,
        supported: [String]
    ) -> String? {
        let candidates = candidateModelIDs(tier: tier, language: language)
        return candidates.first { candidate in
            supported.contains { $0.contains(candidate) || $0 == candidate }
        } ?? candidates.first
    }

    static func tierOption(
        tier: ModelSizeTier,
        language: TranscriptionLanguage,
        supported: [String],
        memoryGB: Int,
        processorCount: Int,
        recommendedTier: ModelSizeTier
    ) -> WhisperTierOption {
        let candidates = candidateModelIDs(tier: tier, language: language)
        let recommendedModelID = candidates.first { candidate in
            supported.contains { $0.contains(candidate) || $0 == candidate }
        }
        let modelID = recommendedModelID ?? candidates.first
        let isWhisperKitRecommended = recommendedModelID != nil

        return WhisperTierOption(
            tier: tier,
            language: language,
            whisperModelID: modelID,
            isWhisperKitRecommended: isWhisperKitRecommended,
            isRecommended: tier == recommendedTier,
            fitLevel: fitLevel(
                tier: tier,
                memoryGB: memoryGB,
                processorCount: processorCount,
                recommendedTier: recommendedTier,
                isWhisperKitRecommended: isWhisperKitRecommended
            )
        )
    }

    static func recommendedTier(memoryGB: Int, processorCount: Int) -> ModelSizeTier {
        if memoryGB >= 16 && processorCount >= 8 { return .medium }
        if memoryGB >= 10 { return .small }
        if memoryGB >= 8 { return .small }
        return .tiny
    }

    static func pickRecommendedModel(
        supportedEnglish: Set<String>,
        memoryGB: Int,
        processorCount: Int
    ) -> String? {
        let tier = recommendedTier(memoryGB: memoryGB, processorCount: processorCount)
        return whisperModelID(tier: tier, language: .english, supported: Array(supportedEnglish))
    }

    static func buildProfile(
        modelIdentifier: String,
        chipFamily: String,
        memoryGB: Int,
        processorCount: Int,
        modelSupport: ModelSupportSnapshot,
        settings: AppSettings
    ) -> DeviceProfile {
        let recommendedTier = recommendedTier(memoryGB: memoryGB, processorCount: processorCount)
        let tierOptions = ModelSizeTier.allCases.map { tier in
            tierOption(
                tier: tier,
                language: settings.language,
                supported: modelSupport.supported,
                memoryGB: memoryGB,
                processorCount: processorCount,
                recommendedTier: recommendedTier
            )
        }

        let selectedModelID = whisperModelID(
            tier: settings.modelTier,
            language: settings.language,
            supported: modelSupport.supported
        )

        return DeviceProfile(
            modelIdentifier: modelIdentifier,
            chipFamily: chipFamily,
            memoryGB: memoryGB,
            processorCount: processorCount,
            whisperDefaultModel: modelSupport.default,
            supportedModels: modelSupport.supported,
            tierOptions: tierOptions,
            selectedModelID: selectedModelID,
            selectedTier: settings.modelTier,
            selectedLanguage: settings.language
        )
    }

    private static func candidateModelIDs(
        tier: ModelSizeTier,
        language: TranscriptionLanguage
    ) -> [String] {
        if language.usesEnglishModel {
            switch tier {
            case .tiny: return ["tiny.en", "tiny"]
            case .small: return ["small.en", "small"]
            case .medium: return ["medium.en", "medium"]
            case .large:
                return [
                    "large-v3-v20240930_626MB",
                    "large-v3-v20240930",
                    "large-v3",
                    "large-v2",
                    "large",
                ]
            }
        }

        switch tier {
        case .tiny: return ["tiny"]
        case .small: return ["small"]
        case .medium: return ["medium"]
        case .large:
            return [
                "large-v3-v20240930_626MB",
                "large-v3-v20240930",
                "large-v3",
                "large-v2",
                "large",
            ]
        }
    }

    private static func fitLevel(
        tier: ModelSizeTier,
        memoryGB: Int,
        processorCount: Int,
        recommendedTier: ModelSizeTier,
        isWhisperKitRecommended: Bool
    ) -> ModelFitLevel {
        if isWhisperKitRecommended == false {
            return .warning(
                "\(tier.title) isn't in WhisperKit's official list for this Mac. You can still try it, but download and transcription may be slow or fail."
            )
        }

        if tier == recommendedTier { return .ideal }

        if memoryGB < tier.minMemoryGB {
            return .warning(
                "\(tier.title) usually needs at least \(tier.minMemoryGB) GB RAM. Your Mac has \(memoryGB) GB."
            )
        }

        if tier == .large && memoryGB < 16 {
            return .warning("Large v3 Turbo still needs plenty of memory on \(memoryGB) GB RAM. Expect slower runs.")
        }

        if tier == .medium && processorCount < 8 {
            return .warning("Classic Medium can run slowly on fewer CPU cores.")
        }

        return .acceptable
    }
}

struct WhisperTierOption: Identifiable, Hashable {
    let tier: ModelSizeTier
    let language: TranscriptionLanguage
    let whisperModelID: String?
    let isWhisperKitRecommended: Bool
    let isRecommended: Bool
    let fitLevel: ModelFitLevel

    var id: String { tier.id }

    var isSelectable: Bool { whisperModelID != nil }

    var modelVariant: String {
        tier.modelVariant(for: language)
    }

    var resolvedModelLabel: String? {
        guard let whisperModelID else { return nil }
        return "Uses model: \(whisperModelID)"
    }

    var pickerLabel: String {
        "\(tier.title) (\(tier.performanceHint))"
    }
}

struct DeviceProfile: Equatable {
    let modelIdentifier: String
    let chipFamily: String
    let memoryGB: Int
    let processorCount: Int
    let whisperDefaultModel: String
    let supportedModels: [String]
    let tierOptions: [WhisperTierOption]
    let selectedModelID: String?
    let selectedTier: ModelSizeTier
    let selectedLanguage: TranscriptionLanguage

    func tierOption(for tier: ModelSizeTier) -> WhisperTierOption? {
        tierOptions.first(where: { $0.tier == tier })
    }

    var summary: String {
        "\(chipFamily) · \(memoryGB) GB RAM · \(processorCount) cores"
    }
}

enum ModelPerformanceLabel: String {
    case fast = "Fast"
    case balanced = "Balanced"
    case highQuality = "High Quality"
    case maximum = "Maximum"
}

enum ModelFitLevel: Equatable, Hashable {
    case ideal
    case acceptable
    case warning(String)

    var isIdeal: Bool {
        if case .ideal = self { return true }
        return false
    }
}

struct ModelSupportSnapshot: Equatable {
    let `default`: String
    let supported: [String]
}
