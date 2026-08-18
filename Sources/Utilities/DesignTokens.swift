import AppKit
import SwiftUI

// MARK: - Colors

enum CueColors {
  // Primary accent — broadcast studio amber
  static let accent = Color(red: 232 / 255, green: 164 / 255, blue: 48 / 255)  // #E8A430
  static let accentHover = Color(red: 240 / 255, green: 184 / 255, blue: 77 / 255)  // #F0B84D
  static let accentMuted = Color(red: 232 / 255, green: 164 / 255, blue: 48 / 255).opacity(0.15)

  // NSColor versions for AppKit (PrompterTextView, LayoutManager)
  static let accentNS = NSColor(red: 232 / 255, green: 164 / 255, blue: 48 / 255, alpha: 1.0)

  // Surfaces
  static let prompterBg = Color.black  // #000000
  static let surface = Color(red: 28 / 255, green: 28 / 255, blue: 30 / 255)  // #1C1C1E
  static let elevated = Color(red: 44 / 255, green: 44 / 255, blue: 46 / 255)  // #2C2C2E
  static let hover = Color(red: 58 / 255, green: 58 / 255, blue: 60 / 255)  // #3A3A3C

  // Text
  static let textPrimary = Color.white  // #FFFFFF
  static let textSecondary = Color(red: 229 / 255, green: 229 / 255, blue: 231 / 255)  // #E5E5E7
  static let textMuted = Color(red: 142 / 255, green: 142 / 255, blue: 147 / 255)  // #8E8E93
  static let textFaint = Color(red: 72 / 255, green: 72 / 255, blue: 74 / 255)  // #48484A

  // Semantic
  static let micActive = Color(red: 48 / 255, green: 209 / 255, blue: 88 / 255)  // #30D158
  static let warning = Color(red: 255 / 255, green: 159 / 255, blue: 10 / 255)  // #FF9F0A
  static let error = Color(red: 255 / 255, green: 69 / 255, blue: 58 / 255)  // #FF453A
  static let info = Color(red: 10 / 255, green: 132 / 255, blue: 255 / 255)  // #0A84FF

  // NSColor semantic
  static let micActiveNS = NSColor(red: 48 / 255, green: 209 / 255, blue: 88 / 255, alpha: 1.0)
  static let warningNS = NSColor(red: 255 / 255, green: 159 / 255, blue: 10 / 255, alpha: 1.0)
  static let errorNS = NSColor(red: 255 / 255, green: 69 / 255, blue: 58 / 255, alpha: 1.0)
}

// MARK: - Spacing

enum CueSpacing {
  static let xxs: CGFloat = 2
  static let xs: CGFloat = 4
  static let sm: CGFloat = 8
  static let md: CGFloat = 16
  static let lg: CGFloat = 24
  static let xl: CGFloat = 32
  static let xxl: CGFloat = 48
  static let xxxl: CGFloat = 64
}

// MARK: - Border Radius

enum CueRadius {
  static let sm: CGFloat = 4
  static let md: CGFloat = 8
  static let lg: CGFloat = 12
  static let full: CGFloat = 9999
  static let prompterBottom: CGFloat = 16
}

// MARK: - Animation Durations

enum CueDuration {
  static let micro: TimeInterval = 0.08
  static let short: TimeInterval = 0.18
  static let medium: TimeInterval = 0.30
  static let long: TimeInterval = 0.50
}

// MARK: - Typography Helpers

enum CueFont {
  static func display(_ size: CGFloat, weight: Font.Weight = .bold) -> Font {
    .system(size: size, weight: weight, design: .default)
  }

  static func body(_ size: CGFloat = 15) -> Font {
    .system(size: size, design: .default)
  }

  static func mono(_ size: CGFloat = 12, weight: Font.Weight = .regular) -> Font {
    .system(size: size, weight: weight, design: .monospaced)
  }

  static func caption() -> Font {
    .system(size: 11, design: .default)
  }

  // NSFont for prompter text (New York serif default)
  static func prompterFont(name: String, size: Double) -> NSFont {
    if name == "New York" {
      // Apple's New York serif via system font descriptor
      if let descriptor = NSFontDescriptor.preferredFontDescriptor(forTextStyle: .body)
        .withDesign(.serif) {
        return NSFont(descriptor: descriptor, size: size)
          ?? NSFont.systemFont(ofSize: size)
      }
    }
    return NSFont(name: name, size: size)
      ?? NSFont.systemFont(ofSize: size)
  }
}
