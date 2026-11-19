import SwiftUI

struct ContentView: View {
    @State private var viewModel = ProjectViewModel()
    @State private var selectedTab: AppTab = .caption

    var body: some View {
        ZStack {
            mainContent

            if viewModel.showWelcomeSettings {
                WelcomeSettingsView(
                    viewModel: viewModel,
                    isFirstLaunch: !viewModel.settings.hasCompletedWelcome
                )
                .transition(.opacity)
                .zIndex(1)
            }
        }
        .background(CapVidTheme.background)
        .preferredColorScheme(.dark)
        .onAppear {
            viewModel.bootstrap()
        }
    }

    private var mainContent: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                ForEach(AppTab.allCases) { tab in
                    CapVidTabButton(tab: tab, isSelected: selectedTab == tab) {
                        selectedTab = tab
                    }
                }

                Spacer()

                Button {
                    viewModel.openSettings()
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(CapVidTheme.mutedText)
                        .padding(10)
                        .background(CapVidTheme.surface, in: Circle())
                }
                .buttonStyle(.plain)
                .help("Transcription settings")
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 12)

            Group {
                switch selectedTab {
                case .caption:
                    CaptionTabView(viewModel: viewModel)
                case .merge:
                    MergeTabView(viewModel: viewModel)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .opacity(viewModel.showWelcomeSettings ? 0.35 : 1)
        .disabled(viewModel.showWelcomeSettings)
    }
}

#Preview {
    ContentView()
        .frame(width: 1000, height: 680)
}
