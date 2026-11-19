import Foundation

enum ModelSizeTier: String, CaseIterable, Identifiable, Codable {
    case tiny
    case small
    case medium
    case large

    var id: String { rawValue }

    var title: String {
        rawValue.capitalized
    }

    var sizeLabel: String {
        switch self {
        case .tiny: "~75 MB"
        case .small: "~466 MB"
        case .medium: "~1.5 GB"
        case .large: "~626 MB"
        }
    }

    var performanceHint: String {
        switch self {
        case .tiny: "Fastest"
        case .small: "Balanced"
        case .medium: "Classic"
        case .large: "Best accuracy"
        }
    }

    func modelVariant(for language: TranscriptionLanguage) -> String {
        switch self {
        case .tiny:
            return language.usesEnglishModel ? "Whisper Tiny.en" : "Whisper Tiny"
        case .small:
            return language.usesEnglishModel ? "Whisper Small.en" : "Whisper Small"
        case .medium:
            return language.usesEnglishModel ? "Whisper Medium.en (classic)" : "Whisper Medium (classic)"
        case .large:
            return "Whisper Large v3 Turbo (compressed)"
        }
    }

    var detail: String {
        switch self {
        case .tiny:
            "Fastest option. Good for quick drafts and short clips."
        case .small:
            "Best default for most videos. Balanced speed and accuracy."
        case .medium:
            "Full classic Medium checkpoint. Larger download and ~3 GB RAM when loaded."
        case .large:
            "Compressed Large v3 Turbo (626 MB). Higher accuracy than Medium with a smaller download — not the full ~3 GB Large v3 model."
        }
    }

    var minMemoryGB: Int {
        switch self {
        case .tiny: 4
        case .small: 6
        case .medium: 10
        case .large: 12
        }
    }
}

enum TranscriptionLanguage: String, CaseIterable, Identifiable, Codable {
    case english = "en"
    case spanish = "es"
    case french = "fr"
    case german = "de"
    case italian = "it"
    case portuguese = "pt"
    case japanese = "ja"
    case korean = "ko"
    case chinese = "zh"
    case auto = "auto"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .english: "English"
        case .spanish: "Spanish"
        case .french: "French"
        case .german: "German"
        case .italian: "Italian"
        case .portuguese: "Portuguese"
        case .japanese: "Japanese"
        case .korean: "Korean"
        case .chinese: "Chinese"
        case .auto: "Auto-detect"
        }
    }

    var usesEnglishModel: Bool {
        self == .english
    }
}

struct AppSettings: Equatable, Codable {
    var modelTier: ModelSizeTier
    var language: TranscriptionLanguage
    var hasCompletedWelcome: Bool

    static let `default` = AppSettings(
        modelTier: .small,
        language: .english,
        hasCompletedWelcome: false
    )
}

enum AppSettingsStore {
    private static let defaults = UserDefaults.standard
    private static let settingsKey = "capvid.appSettings"

    static func load() -> AppSettings {
        guard
            let data = defaults.data(forKey: settingsKey),
            let settings = try? JSONDecoder().decode(AppSettings.self, from: data)
        else {
            return .default
        }
        return settings
    }

    static func save(_ settings: AppSettings) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        defaults.set(data, forKey: settingsKey)
    }
}
