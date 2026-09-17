// Packages/AnteUI/Sources/AnteUI/WorkspaceView.swift
import SwiftUI
import AnteCore

/// The whole window: sidebar | (toolbar / banners / panes over wallpaper).
public struct WorkspaceView: View {
    @Bindable var runtime: WorkspaceRuntime
    let toggleWindow: @MainActor @Sendable () -> Void
    @State private var dismissedBanners: Set<String> = []

    public init(runtime: WorkspaceRuntime, toggleWindow: @escaping @MainActor @Sendable () -> Void = {}) {
        self.runtime = runtime
        self.toggleWindow = toggleWindow
    }

    public var body: some View {
        HStack(spacing: 0) {
            if runtime.isSidebarVisible {
                SidebarView(runtime: runtime)
                    .transition(.move(edge: .leading))
                Divider().overlay(AnteStyle.hairline)
            }
            VStack(spacing: 0) {
                WorkspaceToolbar(runtime: runtime)
                Divider().overlay(AnteStyle.hairline)
                ZStack(alignment: .top) {
                    // Backdrop layers must not take hits: SwiftUI otherwise claims scroll-wheel
                    // events for them and the terminal underneath never scrolls.
                    chrome.pane(AnteStyle.paneBackground)
                        .allowsHitTesting(false)
                    WallpaperView(config: runtime.config.wallpaper)
                        .opacity(runtime.config.wallpaper.path.isEmpty ? 0 : 1)
                        .allowsHitTesting(false)
                    if runtime.isSessionsViewerVisible {
                        SessionsView(runtime: runtime)
                    } else if let session = runtime.store.state.focusedSessionID {
                        if let tree = runtime.existingLayout(for: session) {
                            SplitContainerView(runtime: runtime, tree: tree)
                        } else {
                            // First render of a not-yet-opened session: open it outside of body.
                            Color.clear.onAppear { runtime.open(session: session) }
                        }
                    } else {
                        emptyState
                    }
                    VStack(spacing: 6) {
                        ForEach(banners, id: \.self) { text in
                            BannerView(text: text) { dismissedBanners.insert(text) }
                        }
                    }
                    if runtime.isPaletteVisible {
                        Color.black.opacity(0.25)
                            .ignoresSafeArea()
                            .onTapGesture { runtime.isPaletteVisible = false }
                        CommandPaletteView(items: PaletteItems.build(runtime: runtime, toggleWindow: toggleWindow),
                                           onClose: { runtime.isPaletteVisible = false })
                            .padding(.top, 60)
                    }
                }
            }
        }
        .ignoresSafeArea(.container, edges: .top)
        .background(chrome.pane(AnteStyle.paneBackground))
        .background(WindowTranslucency(chrome: chrome))
        .preferredColorScheme(preferredScheme)
        .environment(\.anteAccent, runtime.accentColor)
        .environment(\.anteChrome, chrome)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Text("No session")
                .font(AnteStyle.uiFontSemibold)
                .foregroundStyle(AnteStyle.textPrimary)
            Text("Press ⌘T to open one")
                .font(AnteStyle.uiFont)
                .foregroundStyle(AnteStyle.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var banners: [String] {
        var out: [String] = []
        if let error = runtime.configError {
            out.append("config.toml line \(error.line.map(String.init) ?? "?"): \(error.message) — using defaults")
        }
        if case let .startedFresh(reason, backup)? = runtime.store.loadNotice {
            out.append("Started fresh: \(reason).\(backup.map { " Backup at \($0.lastPathComponent)." } ?? "")")
        }
        return out.filter { !dismissedBanners.contains($0) }
    }

    /// The chrome follows the *terminal theme*, not the system: a dark palette with light chrome
    /// reads as two apps stitched together.
    private var chrome: AnteChrome { runtime.chrome }

    private var preferredScheme: ColorScheme {
        runtime.appearance.theme.appearance == .dark ? .dark : .light
    }
}
