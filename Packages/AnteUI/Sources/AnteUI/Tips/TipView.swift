// Packages/AnteUI/Sources/AnteUI/Tips/TipView.swift
import SwiftUI
import AppKit
import KeyboardShortcuts
import AntePanel
import AnteCore

/// Hosts the occasional tip in the bottom-right corner of the workspace and decides, once a
/// minute, whether one is due. Takes no clicks outside the card itself.
struct TipHost: View {
    @Bindable var runtime: WorkspaceRuntime

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Color.clear.allowsHitTesting(false)
            if let tip = runtime.tips.current {
                TipCard(tip: tip, tips: runtime.tips)
                    .padding(12)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .id(tip.id)
            }
        }
        .animation(.spring(duration: 0.35, bounce: 0.15), value: runtime.tips.current?.id)
        .task {
            // Not the moment Ante opens: give the user half a minute first.
            try? await Task.sleep(for: .seconds(30))
            while !Task.isCancelled {
                // Only while someone is looking, so a tip is never spent on a hidden window (a
                // closed window leaves Ante active with nothing on screen).
                if NSApp.isActive, NSApp.keyWindow?.isVisible == true, !runtime.isPaletteVisible {
                    runtime.tips.presentIfDue(TipCatalog.tips(keys: runtime.config.keys,
                                                              hotkey: KeyboardShortcuts.getShortcut(for: .showHideAnte)?.description,
                                                              focusMinutes: runtime.pomodoro.focusMinutes,
                                                              breakMinutes: runtime.pomodoro.breakMinutes))
                }
                try? await Task.sleep(for: .seconds(60))
            }
        }
    }
}

/// A small, quiet card: the tip, "Don't show again", and a close button. It goes away by itself
/// after a while, but never while the pointer is on it.
struct TipCard: View {
    let tip: Tip
    let tips: TipsModel
    @Environment(\.anteAccent) private var accent
    @State private var isHovering = false

    static let lifetime: Double = 14

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: tip.symbol)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(accent)
                .frame(width: 18)
            text
                .font(AnteStyle.uiFont)
                .foregroundStyle(AnteStyle.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 360, alignment: .leading)
            Button("Don't show again") { tips.hideCurrentForever() }
                .buttonStyle(.plain)
                .font(AnteStyle.captionFont)
                .foregroundStyle(AnteStyle.textSecondary)
                .help("Never show this tip again")
            Button {
                tips.close()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(AnteStyle.textSecondary)
                    .frame(width: 16, height: 16)
                    .background(Circle().fill(isHovering ? AnteStyle.rowHover : .clear))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help("Close")
            .accessibilityLabel("Close tip")
        }
        .padding(.leading, 12)
        .padding(.trailing, 10)
        .padding(.vertical, 9)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(AnteStyle.hairline))
        .shadow(color: .black.opacity(0.18), radius: 14, y: 6)
        .onHover { isHovering = $0 }
        .contextMenu {
            Button("Don't Show This Tip Again") { tips.hideCurrentForever() }
            Button("Turn Off Tips") { tips.isEnabled = false }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Tip: \(tip.plainText)")
        .task(id: tip.id) {
            // Counts down only while the pointer is elsewhere, so reading it is never cut short.
            var remaining = Self.lifetime
            while remaining > 0 {
                try? await Task.sleep(for: .milliseconds(250))
                if Task.isCancelled { return }
                if !isHovering { remaining -= 0.25 }
            }
            if tips.current?.id == tip.id { tips.close() }
        }
    }

    /// Prose in the body font, keys set heavier so they read as something to press.
    private var text: Text {
        tip.parts.reduce(Text(verbatim: "")) { sentence, part in
            switch part {
            case let .text(s):
                return Text("\(sentence)\(Text(verbatim: s))")
            case let .key(k):
                return Text("\(sentence)\(Text(verbatim: k).font(.system(size: 12.5, weight: .semibold, design: .rounded)))")
            }
        }
    }
}
