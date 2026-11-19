import AppKit
import UniformTypeIdentifiers

enum ExportSavePanel {
    @MainActor
    static func chooseVideoDestination(defaultFilename: String) -> URL? {
        let panel = NSSavePanel()
        panel.title = "Save Captioned Video"
        panel.prompt = "Export"
        panel.nameFieldStringValue = defaultFilename
        panel.allowedContentTypes = [.mpeg4Movie, .quickTimeMovie]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false

        guard panel.runModal() == .OK, let url = panel.url else {
            return nil
        }
        return url
    }
}
