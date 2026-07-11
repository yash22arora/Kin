import SwiftUI
import UIKit

/// Kin speaks in two voices:
/// - **Voice** (Fraunces): the poetic, in-world lines — onboarding headlines,
///   star names, the letter-like copy. Warm, soft serif.
/// - **Chrome** (SF Pro): buttons, labels, dates, settings — the system voice.
///
/// Fraunces is a variable font under the SIL Open Font License.
/// SETUP (one-time): download "Fraunces" from fonts.google.com, drag
/// `Fraunces[opsz,SOFT,WONK,wght].ttf` into Kin/Resources renamed as
/// `Fraunces.ttf`, check the Kin target. Info.plist already declares it.
/// Until the file exists, everything falls back to New York (system serif)
/// so nothing ever renders wrong.
enum KinType {

    private static let fontName = "Fraunces"

    private static var isAvailable: Bool = {
        UIFont(name: fontName, size: 17) != nil
    }()

    /// The poetic voice at a given size, scaling with Dynamic Type.
    static func voice(_ size: CGFloat, relativeTo style: Font.TextStyle = .title3) -> Font {
        isAvailable
            ? .custom(fontName, size: size, relativeTo: style)
            : .system(style, design: .serif)
    }

    // Semantic sizes — use these, not raw numbers, so the scale stays coherent.
    static var heroLine: Font { voice(26, relativeTo: .title2) }   // "Everyone you love is a light."
    static var title: Font { voice(22, relativeTo: .title3) }      // step headlines, star names
    static var whisper: Font { voice(15, relativeTo: .callout) }   // demo captions, letters
}
