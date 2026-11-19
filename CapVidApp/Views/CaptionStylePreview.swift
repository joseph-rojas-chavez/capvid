import SwiftUI

struct CaptionStylePreview: View {
    let videoURL: URL?
    let captionText: String
    let fontName: String
    let fontSize: CGFloat

    var body: some View {
        ZStack {
            previewBackground

            VStack {
                Spacer()
                CaptionBurnInText(
                    text: captionText,
                    fontName: fontName,
                    fontSize: fontSize
                )
                .padding(.horizontal, 28)
                .padding(.bottom, 36)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
        }
    }

    @ViewBuilder
    private var previewBackground: some View {
        if let videoURL {
            MacVideoPreview(url: videoURL)
        } else {
            LinearGradient(
                colors: [Color(red: 0.12, green: 0.14, blue: 0.2), Color(red: 0.05, green: 0.06, blue: 0.09)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .overlay {
                Image(systemName: "play.rectangle")
                    .font(.system(size: 48))
                    .foregroundStyle(.white.opacity(0.25))
            }
        }
    }
}

struct CaptionBurnInText: View {
    let text: String
    let fontName: String
    let fontSize: CGFloat

    var body: some View {
        Text(text)
            .font(.custom(fontName, size: fontSize).weight(.medium))
            .foregroundStyle(.white)
            .multilineTextAlignment(.center)
            .lineLimit(3)
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.black.opacity(0.72))
            }
            .frame(maxWidth: 520)
    }
}
