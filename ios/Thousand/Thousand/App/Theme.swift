//
//  Theme.swift
//  Thousand
//
//  BRAND_THOUSAND.md §3–4: pure monochrome, no accent color, no radius.
//  Direction shown with ▲▼ glyphs and weight — never color.
//  All numbers/addresses/data render monospaced.
//

import SwiftUI

enum Theme {
    static let bg = Color.black                                   // Jet Black
    static let text = Color.white                                 // Pure White
    static let secondary = Color(red: 0x8A/255, green: 0x8F/255, blue: 0x98/255) // Grey 60
    static let hairline = Color(red: 0x1F/255, green: 0x1F/255, blue: 0x1F/255)  // Grey 15
    static let surface = Color(red: 0x14/255, green: 0x14/255, blue: 0x14/255)   // Grey 8

    // Type scale: 11 label / 14 body / 22 section / one huge number per screen
    static func label(_ size: CGFloat = 11) -> Font {
        .system(size: size, weight: .semibold).uppercaseSmallCaps()
    }
    static func mono(_ size: CGFloat = 14, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
    static func display(_ size: CGFloat = 34) -> Font {
        .system(size: size, weight: .bold, design: .monospaced)
    }
    static func heading(_ size: CGFloat = 22) -> Font {
        .system(size: size, weight: .bold)
    }
}

// MARK: - Building blocks

/// Sharp-cornered surface card. No radius, hairline border.
struct Card<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 12) { content }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(Theme.surface)
            .overlay(Rectangle().stroke(Theme.hairline, lineWidth: 1))
    }
}

struct SectionLabel: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text.uppercased())
            .font(Theme.label())
            .tracking(1.2)
            .foregroundStyle(Theme.secondary)
    }
}

struct StatRow: View {
    let label: String
    let value: String
    var dimValue = false
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label.uppercased())
                .font(Theme.label())
                .tracking(1.0)
                .foregroundStyle(Theme.secondary)
            Spacer()
            Text(value)
                .font(Theme.mono(14, weight: .medium))
                .foregroundStyle(dimValue ? Theme.secondary : Theme.text)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
    }
}

/// One huge number per screen.
struct HeroNumber: View {
    let label: String
    let value: String
    var sub: String? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel(label)
            Text(value)
                .font(Theme.display())
                .foregroundStyle(Theme.text)
                .lineLimit(1)
                .minimumScaleFactor(0.4)
            if let sub {
                Text(sub)
                    .font(Theme.mono(12))
                    .foregroundStyle(Theme.secondary)
            }
        }
    }
}

/// Direction glyph — weight and glyph, never color (brand rule).
struct ChangeGlyph: View {
    let value: Double
    var body: some View {
        Text(value >= 0 ? "▲ \(Self.fmt(value))%" : "▼ \(Self.fmt(-value))%")
            .font(Theme.mono(12, weight: value >= 0 ? .bold : .regular))
            .foregroundStyle(Theme.text)
    }
    private static func fmt(_ v: Double) -> String { String(format: "%.2f", v) }
}

struct AddressText: View {
    let address: String
    var body: some View {
        Link(destination: URL(string: Config.basescan + address)!) {
            Text(shortened)
                .font(Theme.mono(12))
                .foregroundStyle(Theme.text)
                .underline(true, color: Theme.hairline)
        }
    }
    private var shortened: String {
        guard address.count > 12 else { return address }
        return String(address.prefix(6)) + "…" + String(address.suffix(4))
    }
}

/// Primary action button. White fill = primary, outline = secondary.
struct ActionButton: View {
    enum Style { case primary, secondary }
    let title: String
    var style: Style = .primary
    var disabled = false
    var busy = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if busy { ProgressView().tint(style == .primary ? .black : .white) }
                Text(busy ? "CONFIRM IN WALLET…" : title.uppercased())
                    .font(Theme.mono(13, weight: .bold))
                    .tracking(1.0)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .background(style == .primary ? Theme.text : Color.clear)
            .foregroundStyle(style == .primary ? Color.black : Theme.text)
            .overlay(Rectangle().stroke(style == .primary ? Color.clear : Theme.text, lineWidth: 1))
        }
        .disabled(disabled || busy)
        .opacity(disabled && !busy ? 0.35 : 1)
    }
}

/// SYS status line (brand voice §6).
struct SysLine: View {
    let text: String
    var body: some View {
        Text("SYS: \(text)")
            .font(Theme.mono(11))
            .foregroundStyle(Theme.secondary)
    }
}
