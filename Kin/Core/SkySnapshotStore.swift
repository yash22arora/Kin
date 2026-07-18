import Foundation

/// Shared constants for app ↔ widget communication.
/// ⚠️ Must match the App Group you enable in Signing & Capabilities
/// on BOTH the Kin and KinWidget targets.
public enum KinShared {
    public static let appGroupID = "group.com.servatom.kin"
    public static let snapshotFilename = "sky-snapshot.json"
    public static let dustBrightnessKey = "dustBrightness"

    /// Dust brightness multiplier, shared app ↔ widget via the App Group.
    /// Range 1.0 (floor, the original look) … 2.5 (brightest). Default sits
    /// at the middle detent, 1.75.
    public static var dustBrightness: Double {
        let value = UserDefaults(suiteName: appGroupID)?
            .double(forKey: dustBrightnessKey) ?? 1.75
        guard value >= 1.0 else { return 1.75 } // unset (0) → middle default
        return min(value, 2.5)
    }
}

/// Writes/reads the SkySnapshot to the App Group container.
/// The app writes on every data change; the widget reads on timeline refresh.
public struct SkySnapshotStore {

    public static func containerURL() -> URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: KinShared.appGroupID)?
            .appendingPathComponent(KinShared.snapshotFilename)
    }

    @discardableResult
    public static func save(_ snapshot: SkySnapshot) -> Bool {
        guard let url = containerURL() else { return false }
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(snapshot)
            try data.write(to: url, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    public static func load() -> SkySnapshot? {
        guard let url = containerURL(),
              let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(SkySnapshot.self, from: data)
    }
}
