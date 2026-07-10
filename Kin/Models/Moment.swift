import Foundation
import SwiftData

/// A shared moment. Everything is optional except the timestamp and people.
@Model
public final class Moment {
    public var id: UUID = UUID()
    public var timestamp: Date = Date()
    public var note: String = ""              // ≤ 280 chars, enforced in UI
    public var feelingRaw: String? = nil      // one of 5 subtle glyphs, optional
    public var photoID: String? = nil         // asset in app container; synced separately
    public var isBackdated: Bool = false

    public var people: [Person]? = []

    public init(timestamp: Date = Date(), note: String = "", people: [Person] = [],
                feeling: Feeling? = nil, isBackdated: Bool = false) {
        self.id = UUID()
        self.timestamp = timestamp
        self.note = note
        self.people = people
        self.feelingRaw = feeling?.rawValue
        self.isBackdated = isBackdated
    }

    public var feeling: Feeling? {
        get { feelingRaw.flatMap(Feeling.init(rawValue:)) }
        set { feelingRaw = newValue?.rawValue }
    }
}

/// Five subtle glyphs — deliberately not emoji, not a 1–5 score.
public enum Feeling: String, Codable, CaseIterable, Sendable {
    case warm, bright, calm, tender, wild

    public var symbolName: String {
        switch self {
        case .warm:   return "sun.min"
        case .bright: return "sparkle"
        case .calm:   return "moon"
        case .tender: return "heart"
        case .wild:   return "wind"
        }
    }

    /// Shown under the glyph row when selected — what the feeling means.
    public var whisper: String {
        switch self {
        case .warm:   return "Warm — comfort, closeness"
        case .bright: return "Bright — joy, laughter"
        case .calm:   return "Calm — quiet, at ease"
        case .tender: return "Tender — soft, and it moved you"
        case .wild:   return "Wild — adventure, a little chaos"
        }
    }
}
