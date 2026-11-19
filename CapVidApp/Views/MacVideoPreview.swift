import AVKit
import AppKit
import SwiftUI

struct MacVideoPreview: View {
    let url: URL

    @State private var player: AVPlayer?

    var body: some View {
        Group {
            if let player {
                MacVideoPlayerRepresentable(player: player)
            } else {
                Color.black
            }
        }
        .onAppear {
            ensurePlayer(for: url)
        }
        .onChange(of: url) { _, newURL in
            replacePlayer(with: newURL)
        }
        .onDisappear {
            tearDownPlayer()
        }
    }

    private func ensurePlayer(for url: URL) {
        guard player == nil else { return }
        player = AVPlayer(url: url)
    }

    private func replacePlayer(with url: URL) {
        player?.pause()
        player?.replaceCurrentItem(with: AVPlayerItem(url: url))
        if player == nil {
            player = AVPlayer(url: url)
        }
    }

    private func tearDownPlayer() {
        player?.pause()
        player?.replaceCurrentItem(with: nil)
        player = nil
    }
}

private struct MacVideoPlayerRepresentable: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.controlsStyle = .none
        view.showsFullScreenToggleButton = false
        view.showsSharingServiceButton = false
        view.player = player
        return view
    }

    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        if nsView.player !== player {
            nsView.player = player
        }
    }

    static func dismantleNSView(_ nsView: AVPlayerView, coordinator: ()) {
        nsView.player = nil
    }
}
