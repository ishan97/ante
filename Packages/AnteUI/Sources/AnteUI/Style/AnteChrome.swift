// Packages/AnteUI/Sources/AnteUI/Style/AnteChrome.swift
import SwiftUI
import AppKit
import AnteCore

/// The window's background treatment from `[theme] background` / `opacity`: one colour for
/// chrome and terminal alike, with the sidebar and toolbar shaded a step off it, all at the
/// configured opacity so the desktop can show through.
public struct AnteChrome: Equatable, Sendable {
    public var background: HexColor?
    public var opacity: Double
    /// Frost strength, 0–1.
    public var blur: Double
    /// The top bar's own colour, when it should not follow the window.
    public var header: HexColor?

    public init(background: HexColor? = nil, opacity: Double = 1, blur: Double = 1, header: HexColor? = nil) {
        self.background = background
        self.opacity = min(max(opacity, 0.01), 1)
        self.blur = min(max(blur, 0), 1)
        self.header = header
    }

    /// Whether text on the header should be light (dark header) or dark; nil follows the window.
    public var headerIsDark: Bool? { header.map { $0.luminance < 0.5 } }

    /// Whether a frosted layer should sit behind the chrome.
    public var wantsBlur: Bool { blur > 0 && opacity < 1 }

    public var isDark: Bool? { background.map { $0.luminance < 0.5 } }

    public func pane(_ fallback: Color) -> Color { paint(background, fallback) }
    public func sidebar(_ fallback: Color) -> Color { paint(background.map { $0.shaded(isDark == true ? 1.25 : 0.985) }, fallback) }
    /// The toolbar keeps full opacity: the controls stay legible however see-through the rest is.
    public func toolbar(_ fallback: Color) -> Color { paint(header ?? background, fallback, opaque: true) }

    private func paint(_ custom: HexColor?, _ fallback: Color, opaque: Bool = false) -> Color {
        let base = custom.map { Color(.sRGB, red: $0.red, green: $0.green, blue: $0.blue) } ?? fallback
        return opacity < 1 && !opaque ? base.opacity(opacity) : base
    }
}

private struct AnteChromeKey: EnvironmentKey {
    static let defaultValue = AnteChrome()
}

extension EnvironmentValues {
    public var anteChrome: AnteChrome {
        get { self[AnteChromeKey.self] }
        set { self[AnteChromeKey.self] = newValue }
    }
}

/// Makes the hosting window see-through when the chrome is translucent, and frosts what shows
/// through (an `NSVisualEffectView` blending behind the window) so text stays readable. Lives
/// in the view tree so a config change re-applies without a relaunch.
struct WindowTranslucency: NSViewRepresentable {
    let chrome: AnteChrome

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView(frame: .zero)
        view.blendingMode = .behindWindow
        view.material = .hudWindow
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.isHidden = !chrome.wantsBlur
        // The material's blur has no radius; blending the frosted layer in by `blur` reads as
        // more or less blur between the bare desktop (0) and the full material (1).
        view.alphaValue = chrome.blur
        view.material = chrome.isDark == false ? .sheet : .hudWindow
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            let translucent = chrome.opacity < 1
            window.isOpaque = !translucent
            window.backgroundColor = translucent ? .clear : .windowBackgroundColor
        }
    }
}
