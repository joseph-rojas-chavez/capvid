import Foundation

enum AppTab: String, CaseIterable, Identifiable {
    case caption
    case merge

    var id: String { rawValue }

    var title: String {
        switch self {
        case .caption: "Caption"
        case .merge: "Merge"
        }
    }

    var icon: String {
        switch self {
        case .caption: "captions.bubble"
        case .merge: "arrow.triangle.merge"
        }
    }
}
