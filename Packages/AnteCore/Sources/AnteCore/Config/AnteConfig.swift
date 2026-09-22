import Foundation

/// Ante's user configuration. Every field has a default; the TOML file is an override layer.
/// Decoding is written by hand so a missing key means "use the default", never "fail".
public struct AnteConfig: Equatable, Sendable, Decodable {
    public enum Appearance: String, Equatable, Sendable, Decodable {
        case system, light, dark
    }

    public struct Font: Equatable, Sendable, Decodable {
        /// iTerm2's defaults, so a fresh Ante reads like the terminal most people come from.
        /// JetBrains Mono ships in the bundle for anyone who prefers it.
        public var family: String = "Monaco"
        public var size: Double = 12
        public var ligatures: Bool = true

        public init() {}

        private enum CodingKeys: String, CodingKey { case family, size, ligatures }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            family = try c.decodeIfPresent(String.self, forKey: .family) ?? family
            size = try c.decodeNumberIfPresent(forKey: .size) ?? size
            ligatures = try c.decodeIfPresent(Bool.self, forKey: .ligatures) ?? ligatures
        }
    }

    public struct Theme: Equatable, Sendable, Decodable {
        public var name: String = "ante-dark"
        public var appearance: Appearance = .system
        /// Chrome accent (focus ring, waiting badges, selection) as `#RRGGBB`; nil is Ante's amber.
        public var accent: String?
        /// One background for the whole window (terminal and chrome) as `#RRGGBB`; nil uses the theme's.
        public var background: String?
        /// Window opacity, 0.01–1. Below 1 the desktop shows through the sidebar and terminal.
        public var opacity: Double = 1
        /// How strongly to frost what shows through a translucent window, 0–1 (`true`/`false`
        /// still decode as 1/0).
        public var blur: Double = 1
        /// The top bar (toolbar and the strip under the traffic lights) as `#RRGGBB`; nil follows
        /// the window. Text on it flips light/dark to suit.
        public var header: String?

        public init() {}

        private enum CodingKeys: String, CodingKey { case name, appearance, accent, background, opacity, blur, header }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            name = try c.decodeIfPresent(String.self, forKey: .name) ?? name
            appearance = try c.decodeIfPresent(Appearance.self, forKey: .appearance) ?? appearance
            if let raw = try c.decodeIfPresent(String.self, forKey: .accent) {
                guard let color = HexColor.parse(raw) else {
                    throw DecodingError.dataCorruptedError(forKey: .accent, in: c, debugDescription: "accent must be #RRGGBB, got \"\(raw)\"")
                }
                accent = color.hex
            }
            if let raw = try c.decodeIfPresent(String.self, forKey: .background), !raw.isEmpty {
                guard let color = HexColor.parse(raw) else {
                    throw DecodingError.dataCorruptedError(forKey: .background, in: c, debugDescription: "background must be #RRGGBB, got \"\(raw)\"")
                }
                background = color.hex
            }
            if let raw = try c.decodeNumberIfPresent(forKey: .opacity) { opacity = min(max(raw, 0.01), 1) }
            if let flag = try? c.decodeIfPresent(Bool.self, forKey: .blur) {
                blur = flag ? 1 : 0
            } else if let amount = try c.decodeNumberIfPresent(forKey: .blur) {
                blur = min(max(amount, 0), 1)
            }
            if let raw = try c.decodeIfPresent(String.self, forKey: .header), !raw.isEmpty {
                guard let color = HexColor.parse(raw) else {
                    throw DecodingError.dataCorruptedError(forKey: .header, in: c, debugDescription: "header must be #RRGGBB, got \"\(raw)\"")
                }
                header = color.hex
            }
        }
    }

    public struct Wallpaper: Equatable, Sendable, Decodable {
        /// Empty means off.
        public var path: String = ""
        public var opacity: Double = 0.35
        public var blur: Double = 12

        public init() {}

        private enum CodingKeys: String, CodingKey { case path, opacity, blur }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            path = try c.decodeIfPresent(String.self, forKey: .path) ?? path
            opacity = try c.decodeNumberIfPresent(forKey: .opacity) ?? opacity
            blur = try c.decodeNumberIfPresent(forKey: .blur) ?? blur
        }
    }

    public struct Hotkey: Equatable, Sendable, Decodable {
        /// How the window arrives when summoned (and leaves when hidden).
        public enum Animation: String, Equatable, Sendable, Decodable, CaseIterable {
            case fade, slideDown = "slide_down", slideUp = "slide_up", slideLeft = "slide_left", slideRight = "slide_right", none
            public var label: String {
                switch self {
                case .fade: return "Fade"
                case .slideDown: return "Drop from the top"
                case .slideUp: return "Rise from the bottom"
                case .slideLeft: return "Slide in from the left"
                case .slideRight: return "Slide in from the right"
                case .none: return "None"
                }
            }
        }

        public var hideOnFocusLoss: Bool = true
        public var animation: Animation = .slideDown
        /// Size of the summoned overlay as a fraction of the screen (0.3–1). It docks to the top
        /// edge, centred; the window's own frame comes back when it hides.
        public var width: Double = 0.9
        public var height: Double = 0.6

        public init() {}

        private enum CodingKeys: String, CodingKey { case hideOnFocusLoss = "hide_on_focus_loss", animation, width, height }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            hideOnFocusLoss = try c.decodeIfPresent(Bool.self, forKey: .hideOnFocusLoss) ?? hideOnFocusLoss
            animation = try c.decodeIfPresent(Animation.self, forKey: .animation) ?? animation
            if let w = try c.decodeNumberIfPresent(forKey: .width) { width = min(max(w, 0.3), 1) }
            if let h = try c.decodeNumberIfPresent(forKey: .height) { height = min(max(h, 0.3), 1) }
        }
    }

    public struct Shell: Equatable, Sendable, Decodable {
        /// Empty means the user's login shell.
        public var program: String = ""
        public var arguments: [String] = ["-l"]
        /// Inject the OSC 133/7 shell integration shim.
        public var integration: Bool = true

        public init() {}

        private enum CodingKeys: String, CodingKey { case program, arguments = "args", integration }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            program = try c.decodeIfPresent(String.self, forKey: .program) ?? program
            arguments = try c.decodeIfPresent([String].self, forKey: .arguments) ?? arguments
            integration = try c.decodeIfPresent(Bool.self, forKey: .integration) ?? integration
        }
    }

    public var font = Font()
    public var window = Window()
    public var theme = Theme()
    public var wallpaper = Wallpaper()
    public var hotkey = Hotkey()
    public var shell = Shell()
    public var security = Security()
    public var keys = Keys()
    public var cursor = Cursor()
    public var agents = Agents()

    /// `[window]`: the size the workspace window opens at, as fractions of the screen's usable
    /// area. 0 for either means "remember the last size" instead.
    public struct Window: Equatable, Sendable, Decodable {
        public var width: Double = 0.8
        public var height: Double = 0.8

        public init() {}
        public init(width: Double, height: Double) { self.width = width; self.height = height }

        /// True when the window opens at the configured size rather than the remembered one.
        public var isFixed: Bool { width > 0 && height > 0 }

        private enum CodingKeys: String, CodingKey { case width, height }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            width = try c.decodeNumberIfPresent(forKey: .width) ?? width
            height = try c.decodeNumberIfPresent(forKey: .height) ?? height
        }
    }

    public init() {}

    public static let `default` = AnteConfig()

    private enum CodingKeys: String, CodingKey { case font, window, theme, wallpaper, hotkey, shell, security, keys, cursor, agents }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        font = try c.decodeIfPresent(Font.self, forKey: .font) ?? font
        window = try c.decodeIfPresent(Window.self, forKey: .window) ?? window
        theme = try c.decodeIfPresent(Theme.self, forKey: .theme) ?? theme
        wallpaper = try c.decodeIfPresent(Wallpaper.self, forKey: .wallpaper) ?? wallpaper
        hotkey = try c.decodeIfPresent(Hotkey.self, forKey: .hotkey) ?? hotkey
        shell = try c.decodeIfPresent(Shell.self, forKey: .shell) ?? shell
        security = try c.decodeIfPresent(Security.self, forKey: .security) ?? security
        keys = try c.decodeIfPresent(Keys.self, forKey: .keys) ?? keys
        cursor = try c.decodeIfPresent(Cursor.self, forKey: .cursor) ?? cursor
        agents = try c.decodeIfPresent(Agents.self, forKey: .agents) ?? agents
    }
}

extension KeyedDecodingContainer {
    /// TOML distinguishes `13` from `13.0`; users write either. Accept both as a Double.
    func decodeNumberIfPresent(forKey key: Key) throws -> Double? {
        if let value = try? decodeIfPresent(Double.self, forKey: key) { return value }
        if let value = try decodeIfPresent(Int.self, forKey: key) { return Double(value) }
        return nil
    }
}
