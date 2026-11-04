import SwiftUI

struct PreferencesPage: View {
    @ObservedObject var store: ReaderStore
    let palette: Palette
    let quit: () -> Void

    private var preferences: ReaderPreferences { store.state.preferences }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text("阅读设置")
                    .font(.system(size: 13, weight: .semibold))
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                GlyphButton(icon: "xmark", label: "关闭阅读设置", palette: palette) {
                    store.showsSettings = false
                }
            }
            if store.current?.format != .pdf {
                row("字号") {
                    HStack(spacing: 2) {
                        GlyphButton(icon: "minus", label: "减小字号", palette: palette) { store.adjustFont(-1) }
                            .disabled(preferences.fontSize <= 12)
                        Text("\(preferences.fontSize) pt")
                            .font(.system(size: 11, weight: .medium))
                            .monospacedDigit()
                            .frame(width: 37)
                        GlyphButton(icon: "plus", label: "增大字号", palette: palette) { store.adjustFont(1) }
                            .disabled(preferences.fontSize >= 32)
                    }
                }
                row("行距") {
                    choices {
                        choice("紧凑", selected: preferences.lineHeight == 1.5) { setLineHeight(1.5) }
                        choice("舒适", selected: preferences.lineHeight == 1.8) { setLineHeight(1.8) }
                        choice("宽松", selected: preferences.lineHeight == 2.1) { setLineHeight(2.1) }
                    }
                }
            }
            row("配色") {
                choices {
                    ForEach(ReadingTheme.allCases) { theme in
                        choice(theme.title, selected: preferences.theme == theme, width: 49, swatch: theme) {
                            store.updatePreferences { $0.theme = theme }
                        }
                    }
                }
            }
            row("弹窗尺寸") {
                choices {
                    ForEach(PanelSize.allCases) { size in
                        choice(size.title, selected: preferences.panelSize == size) {
                            store.updatePreferences { $0.panelSize = size }
                        }
                    }
                }
            }
            Rectangle().fill(palette.line).frame(height: 1).padding(.top, 3)
            Button("退出BookBar", action: quit)
                .buttonStyle(.plain)
                .foregroundStyle(palette.muted)
                .font(.system(size: 11))
                .padding(.vertical, 3)
        }
        .padding(12)
        .fixedSize(horizontal: false, vertical: true)
        .background(palette.paper, in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12).strokeBorder(palette.line)
                .allowsHitTesting(false)
        }
        .shadow(color: .black.opacity(0.17), radius: 11, y: 4)
    }

    private func row<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 8) {
            Text(title).font(.system(size: 11, weight: .semibold)).fixedSize()
            Spacer(minLength: 0)
            content()
        }
    }

    private func choices<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 2, content: content)
            .padding(2)
            .background(palette.ink.opacity(0.06), in: RoundedRectangle(cornerRadius: 7))
    }

    private func setLineHeight(_ value: Double) {
        store.updatePreferences { $0.lineHeight = value }
    }

    private func choice(_ title: String, selected: Bool, width: CGFloat = 59, swatch: ReadingTheme? = nil,
                        action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let swatch {
                    if swatch == .glass {
                        Image(systemName: "circle.lefthalf.filled")
                            .font(.system(size: 9))
                            .foregroundStyle(palette.muted)
                    } else {
                        let colors = Palette(theme: swatch)
                        Circle().fill(colors.paper)
                            .overlay(Circle().strokeBorder(colors.ink.opacity(0.55), lineWidth: 1))
                            .frame(width: 9, height: 9)
                    }
                }
                Text(title)
                    .font(.system(size: 11, weight: selected ? .semibold : .regular))
                    .fixedSize()
            }
            .frame(width: width, height: 26)
            .contentShape(Rectangle())
            .foregroundStyle(selected ? palette.accent : palette.ink)
        }
        .buttonStyle(ReaderButtonStyle(palette: palette, selected: selected))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct ReaderButtonStyle: ButtonStyle {
    let palette: Palette
    var selected = false

    func makeBody(configuration: Configuration) -> some View {
        Surface(configuration: configuration, palette: palette, selected: selected)
    }

    private struct Surface: View {
        let configuration: ButtonStyle.Configuration
        let palette: Palette
        let selected: Bool
        @Environment(\.isEnabled) private var enabled
        @State private var hovered = false

        var body: some View {
            configuration.label
                .opacity(enabled ? 1 : 0.36)
                .background {
                    RoundedRectangle(cornerRadius: 7)
                        .fill(palette.accent.opacity(highlight))
                }
                .onHover { hovered = $0 }
        }

        private var highlight: Double {
            if configuration.isPressed { return 0.19 }
            if selected || (hovered && enabled) { return 0.12 }
            return 0
        }
    }
}

struct GlyphButton: View {
    let icon: String
    let label: String
    let palette: Palette
    var selected = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                .frame(width: 30, height: 30)
                .contentShape(Rectangle())
                .foregroundStyle(selected ? palette.accent : palette.ink)
        }
        .buttonStyle(ReaderButtonStyle(palette: palette, selected: selected))
        .help(label)
        .accessibilityLabel(label)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct ActionButton: View {
    let title: String
    let icon: String
    let palette: Palette
    let action: () -> Void
    @Environment(\.isEnabled) private var enabled
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.system(size: 12, weight: .semibold))
                .padding(.horizontal, 13)
                .padding(.vertical, 8)
                .foregroundStyle(palette.actionInk)
                .background(palette.accent.opacity(hovered ? 0.88 : 1), in: RoundedRectangle(cornerRadius: 7))
                .opacity(enabled ? 1 : 0.45)
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
    }
}

struct ProgressTrack: View {
    let percentage: Int
    let palette: Palette

    var body: some View {
        GeometryReader { geometry in
            Capsule().fill(palette.line)
                .overlay(alignment: .leading) {
                    Capsule().fill(palette.accent)
                        .frame(width: geometry.size.width * Double(min(100, max(0, percentage))) / 100)
                }
        }
        .frame(height: 2)
        .accessibilityHidden(true)
    }
}
