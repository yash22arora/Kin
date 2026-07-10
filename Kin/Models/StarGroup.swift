import Foundation
import SwiftData

/// A named constellation ("The College Crew"). v1.x feature; model ships
/// in v1 so CloudKit schema doesn't need migration later.
@Model
public final class StarGroup {
    public var id: UUID = UUID()
    public var name: String = ""
    public var personIDs: [UUID] = []
    public var createdAt: Date = Date()

    public init(name: String, personIDs: [UUID] = []) {
        self.id = UUID()
        self.name = name
        self.personIDs = personIDs
        self.createdAt = Date()
    }
}
