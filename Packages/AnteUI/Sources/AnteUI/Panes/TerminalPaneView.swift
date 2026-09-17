// Packages/AnteUI/Sources/AnteUI/Panes/TerminalPaneView.swift
import SwiftUI
import AppKit
import AnteTerm

/// Hosts one `AnteTerminalView` and reports first-responder changes so focus follows clicks.
struct TerminalHostView: NSViewRepresentable {
    let controller: TerminalSessionController
    let isFocused: Bool
    let onFocus: () -> Void

    func makeNSView(context: Context) -> AnteTerminalView {
        let view = controller.view
        // Defensive: if this host is ever reused for another controller, refuse silently rather
        // than show the wrong terminal (the `.id(pane)` in SplitContainerView prevents it).
        assert(context.coordinator.hostedController == nil || context.coordinator.hostedController === controller)
        context.coordinator.hostedController = controller
        view.scrollerStyle = .overlay
        controller.applyRenderer()
        context.coordinator.observe(view: view, onFocus: onFocus)
        view.claimsKeyboardWhenFocused = isFocused
        return view
    }

    func updateNSView(_ view: AnteTerminalView, context: Context) {
        context.coordinator.onFocus = onFocus
        if context.coordinator.hostedController !== controller {
            // Should not happen with `.id(pane)`; log so a regression is visible in Console.
            NSLog("Ante: TerminalHostView asked to show a different controller than it hosts")
        }
        // The view claims the keyboard itself when it gains a window or is clicked; this just
        // keeps it told which pane is focused.
        view.claimsKeyboardWhenFocused = isFocused
        view.claimKeyboardIfAppropriate()
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    @MainActor
    final class Coordinator {
        var onFocus: () -> Void = {}
        weak var hostedController: TerminalSessionController?
        // Touched from deinit, which is nonisolated; the monitor token is only ever used on main.
        nonisolated(unsafe) private var monitor: Any?

        func observe(view: AnteTerminalView, onFocus: @escaping () -> Void) {
            self.onFocus = onFocus
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self, weak view] event in
                guard let view, event.window === view.window,
                      view.hitTest(view.superview?.convert(event.locationInWindow, from: nil) ?? .zero) != nil,
                      let point = view.superview?.convert(event.locationInWindow, from: nil),
                      view.frame.contains(point) else { return event }
                self?.onFocus()
                return event
            }
        }

        deinit {
            if let monitor { NSEvent.removeMonitor(monitor) }
        }
    }
}

struct TerminalPaneView: View {

    @Environment(\.anteAccent) private var accent
    let controller: TerminalSessionController
    let isFocused: Bool
    let onFocus: () -> Void
    var showSearch = false
    var onCloseSearch: () -> Void = {}
    var showClose = false
    var onClose: () -> Void = {}
    @State private var isHovering = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            HStack(spacing: 0) {
                GutterView(controller: controller)
                TerminalHostView(controller: controller, isFocused: isFocused, onFocus: onFocus)
            }
            .padding(AnteStyle.paneInset)
            if showSearch {
                SearchBarView(controller: controller, onClose: onCloseSearch)
                    .padding(.top, AnteStyle.paneInset + 6)
                    .padding(.trailing, AnteStyle.paneInset + 6)
            } else if showClose {
                // Close control for split panes: quiet until hovered.
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(AnteStyle.textSecondary)
                        .frame(width: 18, height: 18)
                        .background(.ultraThinMaterial, in: Circle())
                        .overlay(Circle().strokeBorder(AnteStyle.hairline))
                }
                .buttonStyle(.plain)
                .help("Close Pane")
                .opacity(isHovering ? 1 : 0.35)
                .padding(.top, AnteStyle.paneInset + 4)
                .padding(.trailing, AnteStyle.paneInset + 4)
            }
            if case let .exited(code) = controller.state {
                overlay {
                    Text("exited (code \(code.map(String.init) ?? "signal"))")
                        .font(AnteStyle.monoCaption)
                    Button("Restart") { controller.restart() }
                        .keyboardShortcut(.return, modifiers: [])
                }
            }
            if case let .failed(message) = controller.state {
                overlay {
                    Text(message).font(AnteStyle.monoCaption).foregroundStyle(AnteStyle.statusFailed)
                }
            }
        }
        .onHover { isHovering = $0 }
        // No box around the terminal: it sits directly on the window. With several panes, a thin
        // accent line along the top marks the one with the keyboard.
        .overlay(alignment: .top) {
            if showClose && isFocused {
                accent.opacity(0.8).frame(height: 2).allowsHitTesting(false)
            }
        }
    }

    private func overlay<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(spacing: 8, content: content)
            .padding(16)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
