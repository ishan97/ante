// Packages/AnteUI/Sources/AnteUI/Tokens/TokenUsageView.swift
import SwiftUI
import AppKit
import AnteCore

/// The popover behind the toolbar's token chip: one big number for the chosen window, who
/// spent it, and every window from a day to a year to pick from.
struct TokenUsageView: View {
    @Bindable var model: TokenUsageModel
    @Environment(\.anteAccent) private var accent
    @State private var hoveredWindow: TokenUsageReport.Window?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            if let report = model.report {
                if report.isEmpty {
                    emptyState
                } else {
                    content(report)
                }
            } else {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Reading your agents' logs…").font(AnteStyle.uiFont).foregroundStyle(AnteStyle.textSecondary)
                }
                .frame(maxWidth: .infinity, minHeight: 120)
            }
            footer
        }
        .padding(16)
        .frame(width: 320)
        .background(AnteStyle.paneBackground)
    }

    private var header: some View {
        HStack(spacing: 6) {
            Text("Token usage")
                .font(AnteStyle.uiFontSemibold)
                .foregroundStyle(AnteStyle.textPrimary)
            Spacer()
            if model.isRefreshing && model.report != nil {
                ProgressView().controlSize(.mini)
            }
            Text("All agents")
                .font(AnteStyle.captionFont)
                .foregroundStyle(AnteStyle.textSecondary)
        }
    }

    @ViewBuilder
    private func content(_ report: TokenUsageReport) -> some View {
        let slice = report.slice(model.selected)
        VStack(alignment: .leading, spacing: 2) {
            Text("Last \(model.selected.label)".uppercased())
                .font(.system(size: 10, weight: .semibold)).tracking(0.6)
                .foregroundStyle(AnteStyle.textSecondary)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(TokenUsageModel.compact(slice.total))
                    .font(.system(size: 34, weight: .medium, design: .rounded)).monospacedDigit()
                    .foregroundStyle(AnteStyle.textPrimary)
                    .contentTransition(.numericText())
                Text("tokens")
                    .font(AnteStyle.uiFont)
                    .foregroundStyle(AnteStyle.textSecondary)
            }
            Text(slice.total.formatted())
                .font(AnteStyle.captionFont).monospacedDigit()
                .foregroundStyle(AnteStyle.textSecondary.opacity(0.8))
                .textSelection(.enabled)
        }
        .accessibilityElement(children: .combine)

        if slice.total > 0 {
            agentBar(slice)
        }

        Divider().overlay(AnteStyle.hairline)

        VStack(spacing: 1) {
            let year = max(report.slice(.year).total, 1)
            ForEach(TokenUsageReport.Window.allCases) { window in
                windowRow(window, total: report.slice(window).total, of: year)
            }
        }

        if slice.total > 0 {
            Divider().overlay(AnteStyle.hairline)
            kinds(slice.count)
            models(slice)
        }
    }

    // MARK: - Pieces

    /// One bar split by agent, with a legend underneath.
    private func agentBar(_ slice: TokenUsageReport.Slice) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            GeometryReader { proxy in
                let gaps = CGFloat(max(slice.byAgent.count - 1, 0)) * 2
                HStack(spacing: 2) {
                    ForEach(slice.byAgent) { share in
                        Rectangle()
                            .fill(share.agent.tokenColor)
                            .frame(width: max(2, (proxy.size.width - gaps) * CGFloat(share.tokens) / CGFloat(max(slice.total, 1))))
                    }
                }
                .clipShape(Capsule())
            }
            .frame(height: 6)
            VStack(spacing: 4) {
                ForEach(slice.byAgent) { share in
                    HStack(spacing: 6) {
                        Circle().fill(share.agent.tokenColor).frame(width: 7, height: 7)
                        Text(share.agent.displayName)
                            .font(AnteStyle.uiFont)
                            .foregroundStyle(AnteStyle.textPrimary)
                        Spacer()
                        Text(TokenUsageModel.compact(share.tokens))
                            .font(AnteStyle.uiFont).monospacedDigit()
                            .foregroundStyle(AnteStyle.textPrimary)
                        Text(Self.percent(share.tokens, of: slice.total))
                            .font(AnteStyle.captionFont).monospacedDigit()
                            .foregroundStyle(AnteStyle.textSecondary)
                            .frame(width: 34, alignment: .trailing)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    private func windowRow(_ window: TokenUsageReport.Window, total: Int, of year: Int) -> some View {
        let isSelected = model.selected == window
        return Button {
            withAnimation(.easeOut(duration: 0.15)) { model.selected = window }
        } label: {
            HStack(spacing: 10) {
                Text(window.label)
                    .font(isSelected ? AnteStyle.uiFontSemibold : AnteStyle.uiFont)
                    .foregroundStyle(isSelected ? AnteStyle.textPrimary : AnteStyle.textSecondary)
                    .frame(width: 66, alignment: .leading)
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(AnteStyle.rowHover)
                        Capsule()
                            .fill(accent.opacity(isSelected ? 1 : 0.55))
                            .frame(width: total > 0 ? max(4, proxy.size.width * CGFloat(total) / CGFloat(year)) : 0)
                    }
                }
                .frame(height: 4)
                Text(TokenUsageModel.compact(total))
                    .font(isSelected ? AnteStyle.uiFontSemibold : AnteStyle.uiFont).monospacedDigit()
                    .foregroundStyle(isSelected ? AnteStyle.textPrimary : AnteStyle.textSecondary)
                    .frame(width: 50, alignment: .trailing)
            }
            .padding(.horizontal, 8)
            .frame(height: 26)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(isSelected ? AnteStyle.rowSelected.opacity(0.6) : (hoveredWindow == window ? AnteStyle.rowHover : .clear))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hoveredWindow = $0 ? window : (hoveredWindow == window ? nil : hoveredWindow) }
        .accessibilityLabel("Last \(window.label): \(total.formatted()) tokens")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// Fresh input, output and the two kinds of cache traffic. Cache reads are usually most of it.
    private func kinds(_ count: TokenCount) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
            GridRow {
                kind("Input", count.input)
                kind("Output", count.output)
            }
            GridRow {
                kind("Cache read", count.cacheRead)
                kind("Cache write", count.cacheWrite)
            }
        }
    }

    private func kind(_ label: String, _ tokens: Int) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(TokenUsageModel.compact(tokens))
                .font(AnteStyle.uiFontSemibold).monospacedDigit()
                .foregroundStyle(AnteStyle.textPrimary)
            Text(label)
                .font(AnteStyle.captionFont)
                .foregroundStyle(AnteStyle.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func models(_ slice: TokenUsageReport.Slice) -> some View {
        let top = Array(slice.byModel.prefix(4))
        let rest = slice.byModel.dropFirst(4).reduce(0) { $0 + $1.tokens }
        VStack(alignment: .leading, spacing: 4) {
            Text("MODELS")
                .font(.system(size: 10, weight: .semibold)).tracking(0.6)
                .foregroundStyle(AnteStyle.textSecondary)
            ForEach(top) { share in
                modelRow(share.name, share.tokens, of: slice.total)
            }
            if rest > 0 {
                modelRow("\(slice.byModel.count - 4) more", rest, of: slice.total, isSummary: true)
            }
        }
    }

    private func modelRow(_ name: String, _ tokens: Int, of total: Int, isSummary: Bool = false) -> some View {
        HStack(spacing: 6) {
            Text(name)
                .font(isSummary ? AnteStyle.captionFont : AnteStyle.monoCaption)
                .foregroundStyle(isSummary ? AnteStyle.textSecondary : AnteStyle.textPrimary)
                .lineLimit(1).truncationMode(.middle)
            Spacer(minLength: 8)
            Text(TokenUsageModel.compact(tokens))
                .font(AnteStyle.captionFont).monospacedDigit()
                .foregroundStyle(AnteStyle.textPrimary)
            Text(Self.percent(tokens, of: total))
                .font(AnteStyle.captionFont).monospacedDigit()
                .foregroundStyle(AnteStyle.textSecondary)
                .frame(width: 34, alignment: .trailing)
        }
        .accessibilityElement(children: .combine)
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "flame")
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(AnteStyle.textSecondary)
            Text("No tokens yet")
                .font(AnteStyle.uiFontSemibold)
                .foregroundStyle(AnteStyle.textPrimary)
            Text("Once an agent runs, its usage shows up here.")
                .font(AnteStyle.captionFont)
                .foregroundStyle(AnteStyle.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 120)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Claude Code, Codex, OpenCode, Pi and Gemini CLI, read from their own logs on this Mac. Nothing is sent anywhere.")
                .font(AnteStyle.captionFont)
                .foregroundStyle(AnteStyle.textSecondary.opacity(0.8))
                .fixedSize(horizontal: false, vertical: true)
            if let report = model.report {
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    Text("Updated \(report.generatedAt.formatted(.relative(presentation: .named, unitsStyle: .wide).locale(.current)))")
                        .font(AnteStyle.captionFont)
                        .foregroundStyle(AnteStyle.textSecondary.opacity(0.6))
                        .id(context.date)
                }
            }
        }
    }

    static func percent(_ part: Int, of whole: Int) -> String {
        guard whole > 0 else { return "" }
        let share = Double(part) / Double(whole) * 100
        return share < 1 ? "<1%" : "\(Int(share.rounded()))%"
    }
}

extension AgentKind {
    /// One colour per agent in the token breakdown, readable on light and dark chrome.
    var tokenColor: Color {
        let rgb: (Double, Double, Double)
        switch self {
        case .claude: rgb = (0.85, 0.47, 0.34)     // clay
        case .codex: rgb = (0.20, 0.72, 0.56)      // green
        case .gemini: rgb = (0.30, 0.55, 0.96)     // blue
        case .opencode: rgb = (0.66, 0.55, 0.98)   // violet
        case .pi: rgb = (0.95, 0.45, 0.71)         // pink
        default: rgb = (0.55, 0.58, 0.64)
        }
        return Color(nsColor: NSColor(srgbRed: rgb.0, green: rgb.1, blue: rgb.2, alpha: 1))
    }
}
