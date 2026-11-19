import SwiftUI

struct ModelDownloadProgressView: View {
    let coordinator: ModelDownloadCoordinator

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    Image(systemName: stageIcon)
                        .font(.title3)
                        .foregroundStyle(.blue)
                        .symbolEffect(.pulse, isActive: coordinator.isActive)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(coordinator.stage.title)
                            .font(.headline)
                        Text(coordinator.detailText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer()

                    Text(percentText)
                        .font(.caption.monospacedDigit().bold())
                        .foregroundStyle(.secondary)
                }

                ProgressView(value: coordinator.progress)
                    .progressViewStyle(.linear)

                if coordinator.computeSummary.isEmpty == false {
                    Label(coordinator.computeSummary, systemImage: "cpu")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var percentText: String {
        "\(Int((coordinator.progress * 100).rounded()))%"
    }

    private var stageIcon: String {
        switch coordinator.stage {
        case .idle:
            "checkmark.circle"
        case .downloading:
            "arrow.down.circle"
        case .optimizing:
            "cpu"
        case .loading:
            "memorychip"
        case .ready:
            "checkmark.seal"
        case .transcribing:
            "waveform"
        }
    }
}
