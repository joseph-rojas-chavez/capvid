import SwiftUI
import UniformTypeIdentifiers

private enum MergeImportTarget {
    case video
    case caption
    case multiple
}

struct MergeTabView: View {
    @Bindable var viewModel: ProjectViewModel
    @State private var importTarget: MergeImportTarget?
    @State private var isDropTargeted = false

    private let supportedFormats = "Video: MP4, MOV, MKV · Captions: SRT, TXT, VTT"

    var body: some View {
        Group {
            if viewModel.hasMergeFiles {
                mergeWorkspace
            } else {
                mergeDropZone
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(CapVidTheme.background)
        .fileImporter(
            isPresented: importBinding,
            allowedContentTypes: allowedContentTypes,
            allowsMultipleSelection: importTarget == .multiple
        ) { result in
            handleImport(result)
        }
    }

    private var importBinding: Binding<Bool> {
        Binding(
            get: { importTarget != nil },
            set: { isPresented in
                if isPresented == false {
                    importTarget = nil
                }
            }
        )
    }

    private var allowedContentTypes: [UTType] {
        switch importTarget {
        case .video:
            return MergeFileClassifier.videoContentTypes
        case .caption:
            return MergeFileClassifier.captionContentTypes
        case .multiple, nil:
            return MergeFileClassifier.allContentTypes
        }
    }

    private var mergeDropZone: some View {
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
                Image(systemName: "arrow.down.doc.on.doc")
                    .font(.system(size: 44, weight: .light))
                    .foregroundStyle(CapVidTheme.mutedText)

                Text("Drop video and captions here")
                    .font(.system(size: 28, weight: .semibold))

                Text("Drop one or both files — CapVid detects video vs caption files automatically")
                    .font(.system(size: 14))
                    .foregroundStyle(CapVidTheme.mutedText)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)

                Text(supportedFormats)
                    .font(.system(size: 13))
                    .foregroundStyle(CapVidTheme.mutedText)

                Button("Browse Files…") {
                    importTarget = .multiple
                }
                .buttonStyle(.borderedProminent)
                .tint(CapVidTheme.accent)
                .controlSize(.large)
            }
            .padding(.horizontal, 24)
        }
        .padding(24)
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            handleDrop(providers)
        }
    }

    private var mergeWorkspace: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                Text("Merge Files")
                    .font(.system(size: 28, weight: .bold))
                    .padding(.horizontal, 24)
                    .padding(.top, 24)
                    .padding(.bottom, 20)

                VStack(spacing: 18) {
                    CapVidFileRow(
                        icon: "film",
                        title: "Video",
                        subtitle: viewModel.mergeVideoDisplayName,
                        browseTitle: "Browse"
                    ) {
                        importTarget = .video
                    }

                    CapVidFileRow(
                        icon: "doc.text",
                        title: "Caption File",
                        subtitle: viewModel.mergeSRTDisplayName,
                        browseTitle: "Browse"
                    ) {
                        importTarget = .caption
                    }
                }
                .padding(.horizontal, 24)

                if viewModel.mergePhase == .exporting {
                    VStack(alignment: .leading, spacing: 8) {
                        ProgressView(value: viewModel.mergeProgress) {
                            Text("Exporting captioned video…")
                                .font(.caption)
                        }
                        Text("\(Int(viewModel.mergeProgress * 100))%")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(CapVidTheme.mutedText)
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 8)
                }

                Spacer()

                Divider().overlay(CapVidTheme.border)
                    .padding(.vertical, 20)

                CapVidPrimaryButton(
                    title: "Merge & Burn Captions",
                    icon: "film",
                    isEnabled: viewModel.canMerge
                ) {
                    viewModel.mergeAndBurnCaptions()
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)

                if let mergeStatus = viewModel.mergeStatusMessage {
                    Text(mergeStatus)
                        .font(.caption)
                        .foregroundStyle(isMergeFailed ? .red : CapVidTheme.mutedText)
                        .padding(.horizontal, 24)
                        .padding(.bottom, 16)
                }
            }
            .frame(width: 360)
            .background(CapVidTheme.surface)

            Divider().overlay(CapVidTheme.border)

            ZStack {
                CapVidTheme.previewBackground

                if let videoURL = viewModel.mergeVideoURL {
                    MacVideoPreview(url: videoURL)
                        .padding(24)
                } else {
                    partialDropHint(icon: "film", title: "Drop video here")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
                handleDrop(providers)
            }
        }
    }

    private var isMergeFailed: Bool {
        if case .failed = viewModel.mergePhase {
            return true
        }
        return false
    }

    private func partialDropHint(icon: String, title: String) -> some View {
        VStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(CapVidTheme.mutedText)
            Text(title)
                .font(.headline)
            Text("Or drop both files anywhere in this tab")
                .font(.caption)
                .foregroundStyle(CapVidTheme.mutedText)
        }
        .padding(24)
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        defer { importTarget = nil }

        guard case .success(let urls) = result, urls.isEmpty == false else { return }
        viewModel.registerMergeFiles(from: urls)
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        let fileProviders = providers.filter {
            $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier)
        }
        guard fileProviders.isEmpty == false else { return false }

        loadFileURLs(from: fileProviders) { urls in
            viewModel.registerMergeFiles(from: urls)
        }
        return true
    }

    private func loadFileURLs(from providers: [NSItemProvider], completion: @escaping ([URL]) -> Void) {
        var urls: [URL] = []
        let group = DispatchGroup()
        let lock = NSLock()

        for provider in providers {
            group.enter()
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                defer { group.leave() }
                guard let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) else {
                    return
                }
                lock.lock()
                urls.append(url)
                lock.unlock()
            }
        }

        group.notify(queue: .main) {
            completion(urls)
        }
    }
}
