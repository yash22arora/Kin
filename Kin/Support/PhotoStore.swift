import UIKit

/// Photos live in the app container, referenced by ID from Moment.photoID.
/// Kept out of SwiftData so CloudKit sync of photos stays a separate,
/// user-controllable concern.
enum PhotoStore {
    private static var directory: URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Photos", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static func url(for id: String) -> URL {
        directory.appendingPathComponent("\(id).jpg")
    }

    /// Saves image data (re-encoded to JPEG, longest side capped at 2048px)
    /// and returns the new photo ID.
    static func save(_ data: Data) -> String? {
        guard let image = UIImage(data: data) else { return nil }
        let maxSide: CGFloat = 2048
        let scale = min(1, maxSide / max(image.size.width, image.size.height))
        let target = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: target)
        let resized = renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: target)) }
        guard let jpeg = resized.jpegData(compressionQuality: 0.85) else { return nil }

        let id = UUID().uuidString
        do {
            try jpeg.write(to: url(for: id), options: .atomic)
            return id
        } catch {
            return nil
        }
    }

    static func image(for id: String) -> UIImage? {
        UIImage(contentsOfFile: url(for: id).path)
    }

    static func delete(id: String) {
        try? FileManager.default.removeItem(at: url(for: id))
    }
}
