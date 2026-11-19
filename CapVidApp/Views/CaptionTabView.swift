import CapVid
import SwiftUI
import UniformTypeIdentifiers

struct CaptionTabView: View {
    @Bindable var viewModel: ProjectViewModel
    @State private var isImporterPresented = false
    @State private var isDropTargeted = false

    private let supportedFormats = "MP4, MOV, MKV, MP3, M4A"

    var body: some View {
        Group {
            if viewModel.hasVideo {
                captionWorkspace
            } else {
                dropZone
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(CapVidTheme.background)
        .fileImporter(
            isPresented: $isImporterPresented,
            allowedContentTypes: supportedTypes,
            allowsMultipleSelection: false
        ) { result in
            handleImport(result)
        }
        .onAppear {
            if viewModel.settings.hasCompletedWelcome {
                viewModel.loadModelRecommendationsIfNeeded()
            }
        }
    }

    private var dropZone: some View {
        ZStack {
            RoundedRectangle(cornerRadius: CapVidTheme.cornerRadius, style: .continuous)
                .strokeBorder(
                    CapVidTheme.dashedBorder,
                    style: StrokeStyle(lineWidth: 1.5, dash: [10, 8])
                )
                .background(
                    RoundedRectangle(cornerRadius: CapVidTheme.cornerRadius, style: .continuous)
                        .fill(isDropTargeted ? CapVidTheme.surfaceElevated : CapVidTheme.surface.opacity(0.35))
                )
                .padding(28)

            VStack(spacing: 18) {
                Image(systemName: "arrow.down.doc")
                    .font(.system(size: 44, weight: .light))
                    .foregroundStyle(CapVidTheme.mutedText)

                Text("Drop media here")
                    .font(.system(size: 28, weight: .semibold))

                Text(supportedFormats)
                    .font(.system(size: 14))
                    .foregroundStyle(CapVidTheme.mutedText)

                Button("Browse Files…") {
                    isImporterPresented = true
                }
                .buttonStyle(.borderedProminent)
                .tint(CapVidTheme.accent)
                .controlSize(.large)
            }
        }
        .padding(24)
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            handleDrop(providers)
        }
    }

    private var captionWorkspace: some View {
        HStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    fileSummary

                    if viewModel.modelDownloadCoordinator.isActive
                        || viewModel.transcriptionPhase == .downloadingModel
                        || viewModel.transcriptionPhase == .transcribing {
                        ModelDownloadProgressView(coordinator: viewModel.modelDownloadCoordinator)
                    }

                    modelSection
                    reviewSection
                    styleSection
                    exportSection

                    if let statusMessage = viewModel.statusMessage {
                        Text(statusMessage)
                            .font(.caption)
                            .foregroundStyle(CapVidTheme.mutedText)
                    }

                    if case .failed(let message) = viewModel.transcriptionPhase {
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
                .padding(24)
            }
            .frame(width: 360)
            .background(CapVidTheme.surface)

            Divider().overlay(CapVidTheme.border)

            ZStack {
                CapVidTheme.previewBackground

                if let videoURL = viewModel.videoURL {
                    CaptionStylePreview(
                        videoURL: videoURL,
                        captionText: viewModel.previewCaptionText,
                        fontName: viewModel.captionFontName,
                        fontSize: CGFloat(viewModel.captionFontSize)
                    )
                    .padding(24)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var fileSummary: some View {
        HStack(spacing: 14) {
            Image(systemName: "film")
                .font(.system(size: 22))
                .foregroundStyle(CapVidTheme.mutedText)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(viewModel.videoDisplayName)
                    .font(.system(size: 16, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)

                if let duration = viewModel.assetDuration {
                    Text(String(format: "%.1f sec", duration))
                        .font(.system(size: 13))
                        .foregroundStyle(CapVidTheme.mutedText)
                }
            }

            Spacer()

            CapVidBrowseButton(title: "Browse") {
                isImporterPresented = true
            }
        }
        .padding(.vertical, 6)
    }

    private var modelSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("Transcription")

            HStack(spacing: 14) {
                Image(systemName: "waveform")
                    .font(.system(size: 22))
                    .foregroundStyle(CapVidTheme.mutedText)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(viewModel.settingsSummary)
                        .font(.system(size: 16, weight: .semibold))
                    Text("Whisper model settings")
                        .font(.system(size: 13))
                        .foregroundStyle(CapVidTheme.mutedText)
                }

                Spacer()

                CapVidBrowseButton(title: "Change") {
                    viewModel.openSettings()
                }
            }
            .padding(.vertical, 6)

            if let warning = viewModel.selectedModelWarning {
                Label(warning, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            CapVidPrimaryButton(
                title: "Generate Captions",
                icon: "waveform.badge.mic",
                isEnabled: viewModel.canTranscribe
            ) {
                viewModel.generateCaptions()
            }
        }
    }

    @ViewBuilder
    private var reviewSection: some View {
        if viewModel.editableSegments.isEmpty == false {
            VStack(alignment: .leading, spacing: 10) {
                sectionTitle("Captions")

                Text("\(viewModel.editableSegments.count) lines · \(viewModel.sanitizedSegments.count) after cleanup")
                    .font(.caption)
                    .foregroundStyle(CapVidTheme.mutedText)

                ForEach(viewModel.editableSegments.prefix(6)) { segment in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(String(format: "%.1fs", segment.startTime))
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(CapVidTheme.mutedText)
                        TextField("Caption", text: binding(for: segment))
                            .textFieldStyle(.roundedBorder)
                    }
                }

                if viewModel.editableSegments.count > 6 {
                    Text("+ \(viewModel.editableSegments.count - 6) more lines")
                        .font(.caption)
                        .foregroundStyle(CapVidTheme.mutedText)
                }
            }
        }
    }

    private var styleSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("Style")

            Picker("Font", selection: $viewModel.captionFontName) {
                ForEach(CaptionFontCatalog.availableFonts, id: \.self) { font in
                    Text(font).tag(font)
                }
            }

            LabeledContent("Size") {
                HStack(spacing: 6) {
                    TextField("Size", value: $viewModel.captionFontSize, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 64)
                        .monospacedDigit()
                    Text("pt")
                        .foregroundStyle(CapVidTheme.mutedText)
                }
            }

            if viewModel.sanitizedSegments.count > 1 {
                Stepper(
                    "Preview line #\(viewModel.previewSegmentIndex + 1)",
                    value: $viewModel.previewSegmentIndex,
                    in: 0...(viewModel.sanitizedSegments.count - 1)
                )
                .font(.caption)
            }
        }
    }

    private var exportSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Export")

            if viewModel.captionBurnPhase == .exporting {
                VStack(alignment: .leading, spacing: 8) {
                    ProgressView(value: viewModel.captionBurnProgress) {
                        Text("Exporting captioned video…")
                            .font(.caption)
                    }
                    Text("\(Int(viewModel.captionBurnProgress * 100))%")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(CapVidTheme.mutedText)
                }
            }

            CapVidPrimaryButton(
                title: "Export Captioned Video",
                icon: "film",
                isEnabled: viewModel.canExportCaptionedVideo
            ) {
                viewModel.exportCaptionedVideo()
            }

            ExportCaptionButton(viewModel: viewModel)
        }
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 18, weight: .bold))
    }

    private func binding(for segment: TranscriptionSegment) -> Binding<String> {
        Binding(
            get: {
                viewModel.editableSegments.first(where: { $0.id == segment.id })?.text ?? segment.text
            },
            set: { viewModel.updateSegmentText(id: segment.id, text: $0) }
        )
    }

    private var supportedTypes: [UTType] {
        [.movie, .mpeg4Movie, .quickTimeMovie, .video, .mpeg4Audio, .mp3, .audio]
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        if case .success(let urls) = result, let url = urls.first {
            importURL(url)
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }) else {
            return false
        }

        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            guard let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
            Task { @MainActor in
                importURL(url)
            }
        }
        return true
    }

    private func importURL(_ url: URL) {
        viewModel.selectVideo(url)
    }
}

private struct ExportCaptionButton: View {
    @Bindable var viewModel: ProjectViewModel
    @State private var isExporterPresented = false

    var body: some View {
        CapVidPrimaryButton(
            title: "Export Caption File",
            icon: "square.and.arrow.up",
            isEnabled: viewModel.sanitizedSegments.isEmpty == false
        ) {
            isExporterPresented = true
        }
        .fileExporter(
            isPresented: $isExporterPresented,
            document: CaptionTextDocument(text: viewModel.exportCaptionText()),
            contentType: .plainText,
            defaultFilename: exportFilename
        ) { _ in }
    }

    private var exportFilename: String {
        let base = (viewModel.videoDisplayName as NSString).deletingPathExtension
        return "\(base)-captions"
    }
}
