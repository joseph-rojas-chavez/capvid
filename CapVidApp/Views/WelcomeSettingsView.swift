import SwiftUI

struct WelcomeSettingsView: View {
    @Bindable var viewModel: ProjectViewModel
    let isFirstLaunch: Bool

    @State private var draftTier: ModelSizeTier
    @State private var draftLanguage: TranscriptionLanguage

    init(viewModel: ProjectViewModel, isFirstLaunch: Bool) {
        self.viewModel = viewModel
        self.isFirstLaunch = isFirstLaunch
        _draftTier = State(initialValue: viewModel.settings.modelTier)
        _draftLanguage = State(initialValue: viewModel.settings.language)
    }

    var body: some View {
        ZStack {
            CapVidTheme.background.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    header
                    languageSection
                    modelSection
                    deviceSection
                    actionButton
                }
                .padding(32)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            }
        }
        .onAppear {
            if viewModel.deviceProfile == nil {
                viewModel.loadModelRecommendationsIfNeeded()
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(isFirstLaunch ? "Welcome to CapVid" : "Transcription Settings")
                .font(.system(size: 34, weight: .bold))

            Text(
                isFirstLaunch
                    ? "Choose your speech model and language before you start. You can change these anytime."
                    : "Update the Whisper model size and caption language. Changing these may require downloading a new model."
            )
            .font(.body)
            .foregroundStyle(CapVidTheme.mutedText)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var languageSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("Language")

            Picker("Language", selection: $draftLanguage) {
                ForEach(TranscriptionLanguage.allCases) { language in
                    Text(language.displayName).tag(language)
                }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(20)
        .background(CapVidTheme.surface, in: RoundedRectangle(cornerRadius: CapVidTheme.cornerRadius))
    }

    private var modelSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle("Model Size")

            if viewModel.tierOptions(for: draftLanguage).isEmpty {
                ProgressView("Checking your Mac…")
            } else {
                VStack(spacing: 10) {
                    ForEach(viewModel.tierOptions(for: draftLanguage)) { option in
                        modelCard(option)
                    }
                }
            }
        }
    }

    private func modelCard(_ option: WhisperTierOption) -> some View {
        let isSelected = draftTier == option.tier

        return Button {
            draftTier = option.tier
        } label: {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(isSelected ? CapVidTheme.accent : CapVidTheme.mutedText)
                    .font(.title3)
                    .padding(.top, 2)

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text(option.tier.title)
                            .font(.headline)
                        Text(option.tier.sizeLabel)
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(.quaternary, in: Capsule())
                        Text(option.tier.performanceHint)
                            .font(.caption)
                            .foregroundStyle(CapVidTheme.mutedText)
                        if option.isRecommended {
                            Text("Suggested")
                                .font(.caption.bold())
                                .foregroundStyle(.green)
                        }
                    }

                    Text(option.tier.detail)
                        .font(.caption)
                        .foregroundStyle(CapVidTheme.mutedText)
                        .multilineTextAlignment(.leading)

                    Text(option.modelVariant)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(CapVidTheme.mutedText)

                    if let resolvedModelLabel = option.resolvedModelLabel {
                        Text(resolvedModelLabel)
                            .font(.caption2)
                            .foregroundStyle(CapVidTheme.mutedText)
                    }

                    if let warning = tierWarning(option) {
                        Label(warning, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: CapVidTheme.cornerRadius)
                    .fill(isSelected ? CapVidTheme.accent.opacity(0.12) : CapVidTheme.surface)
            )
            .overlay {
                RoundedRectangle(cornerRadius: CapVidTheme.cornerRadius)
                    .strokeBorder(isSelected ? CapVidTheme.accent : CapVidTheme.border, lineWidth: isSelected ? 1.5 : 1)
            }
        }
        .buttonStyle(.plain)
        .disabled(option.isSelectable == false)
    }

    private var deviceSection: some View {
        Group {
            if let profile = viewModel.deviceProfile {
                VStack(alignment: .leading, spacing: 8) {
                    sectionTitle("Your Mac")
                    Text(profile.summary)
                        .font(.subheadline)
                    Text("Models download once, then Core ML optimizes them for your chip.")
                        .font(.caption)
                        .foregroundStyle(CapVidTheme.mutedText)
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(CapVidTheme.surface, in: RoundedRectangle(cornerRadius: CapVidTheme.cornerRadius))
            }
        }
    }

    private var actionButton: some View {
        CapVidPrimaryButton(
            title: isFirstLaunch ? "Continue" : "Save Settings",
            icon: isFirstLaunch ? "arrow.right.circle" : "checkmark.circle",
            isEnabled: selectedOption?.isSelectable == true
        ) {
            viewModel.applySettings(tier: draftTier, language: draftLanguage, markWelcomeComplete: isFirstLaunch)
        }
    }

    private var selectedOption: WhisperTierOption? {
        viewModel.tierOptions(for: draftLanguage).first(where: { $0.tier == draftTier })
    }

    private func tierWarning(_ option: WhisperTierOption) -> String? {
        if case .warning(let message) = option.fitLevel {
            return message
        }
        return nil
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 18, weight: .bold))
    }
}
