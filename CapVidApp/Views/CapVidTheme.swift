import SwiftUI

enum CapVidTheme {
    static let background = Color(red: 0.11, green: 0.11, blue: 0.12)
    static let surface = Color(red: 0.15, green: 0.15, blue: 0.16)
    static let surfaceElevated = Color(red: 0.18, green: 0.18, blue: 0.19)
    static let border = Color.white.opacity(0.14)
    static let dashedBorder = Color.white.opacity(0.22)
    static let accent = Color(red: 0.0, green: 0.48, blue: 1.0)
    static let previewBackground = Color.black
    static let mutedText = Color.white.opacity(0.45)

    static let cornerRadius: CGFloat = 12
    static let pillRadius: CGFloat = 22
}

struct CapVidTabButton: View {
    let tab: AppTab
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: tab.icon)
                    .font(.system(size: 14, weight: .semibold))
                Text(tab.title)
                    .font(.system(size: 15, weight: .semibold))
            }
            .foregroundStyle(isSelected ? .white : CapVidTheme.mutedText)
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background {
                if isSelected {
                    Capsule().fill(CapVidTheme.accent)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

struct CapVidBrowseButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(title, action: action)
            .buttonStyle(.bordered)
            .controlSize(.regular)
    }
}

struct CapVidPrimaryButton: View {
    let title: String
    let icon: String
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                Text(title)
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .foregroundStyle(.white)
            .background(CapVidTheme.accent.opacity(isEnabled ? 1 : 0.35), in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
    }
}

struct CapVidFileRow: View {
    let icon: String
    let title: String
    let subtitle: String
    let browseTitle: String
    let action: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 22))
                .foregroundStyle(CapVidTheme.mutedText)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                Text(subtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(CapVidTheme.mutedText)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            CapVidBrowseButton(title: browseTitle, action: action)
        }
        .padding(.vertical, 6)
    }
}
