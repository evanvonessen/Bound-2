import UIKit
import SwiftUI

/// Unmodified bundled pixel font. TextKit/Core Text uses system fallback for
/// unsupported characters, including emoji; text and IME runs are unmodified.
@MainActor enum BoundNotesFont {
    static let postScriptName = "Early-GameBoy"
    static func uiFont(pointSize: CGFloat = 16, textStyle: UIFont.TextStyle = .body,
                       compatibleWith traits: UITraitCollection? = nil) -> UIFont {
        guard let font = UIFont(name: postScriptName, size: pointSize) else {
            return UIFont.preferredFont(forTextStyle: textStyle, compatibleWith: traits)
        }
        return UIFontMetrics(forTextStyle: textStyle).scaledFont(for: font, compatibleWith: traits)
    }
    static func swiftUIFont(pointSize: CGFloat = 16, relativeTo style: Font.TextStyle = .body) -> Font {
        guard UIFont(name: postScriptName, size: pointSize) != nil else { return .system(style) }
        return .custom(postScriptName, size: pointSize, relativeTo: style)
    }
}
