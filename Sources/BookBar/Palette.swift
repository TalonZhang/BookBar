import AppKit
import SwiftUI

extension NSColor {
    convenience init(hex: String) {
        let number = Int(hex.dropFirst(), radix: 16) ?? 0
        self.init(srgbRed: CGFloat((number >> 16) & 255) / 255,
                  green: CGFloat((number >> 8) & 255) / 255,
                  blue: CGFloat(number & 255) / 255, alpha: 1)
    }
}

struct Palette: Equatable {
    let theme: ReadingTheme
    var systemIsDark = false
    var reduceTransparency = false

    var colors: ReadingTheme { theme == .glass && systemIsDark ? .night : theme }
    var isDark: Bool { colors == .night }
    var isTranslucent: Bool { theme == .glass && !reduceTransparency }
    var paper: Color { Color(nsColor: NSColor(hex: colors.background)) }
    var panelBackground: Color { isTranslucent ? paper.opacity(0.30) : paper }
    var pageBackground: NSColor { isTranslucent ? .clear : NSColor(hex: colors.background) }
    var ink: Color { Color(nsColor: NSColor(hex: colors.ink)) }
    var muted: Color { Color(nsColor: NSColor(hex: colors.muted)) }
    var accent: Color { Color(nsColor: NSColor(hex: colors.accent)) }
    var line: Color { ink.opacity(0.14) }
    var fill: Color { accent.opacity(0.10) }
    var actionInk: Color { Color(nsColor: NSColor(hex: isDark ? "#1C3227" : "#F5FAF3")) }
}
