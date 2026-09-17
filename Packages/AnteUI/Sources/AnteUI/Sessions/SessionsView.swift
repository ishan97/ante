// Packages/AnteUI/Sources/AnteUI/Sessions/SessionsView.swift
import SwiftUI
import AnteCore

/// The Sessions view: a kanban of live panes on top, history below.
public struct SessionsView: View {
    @Environment(\.anteChrome) private var chrome
    @Environment(\.anteAccent) private var accent
    @Bindable var runtime: WorkspaceRuntime

    public init(runtime: WorkspaceRuntime) {
        self.runtime = runtime
    }

    public var body: some View {
        let board = runtime.board!
        VStack(spacing: 0) {
            header(board)
            HStack(alignment: .top, spacing: 12) {
                ForEach(BoardColumn.allCases, id: \.self) { column in
                    BoardColumnView(column: column, cards: board.cards(in: column)) { card in
                        runtime.isSessionsViewerVisible = false
                        runtime.focusPane(card.id)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
            .frame(maxHeight: 260)
            if let activity = board.activity, activity.totalPrompts > 0 {
                Divider().overlay(AnteStyle.hairline)
                ActivityView(stats: activity)
            }
            Divider().overlay(AnteStyle.hairline)
            HistoryListView(board: board) { past in
                runtime.resume(past)
            }
        }
        .background(chrome.pane(AnteStyle.paneBackground))
        .onAppear {
            board.start()   // idempotent; AppRuntime starts it at launch so the sidebar is live too
            Task { await board.reloadHistory() }
        }
        .onExitCommand { runtime.isSessionsViewerVisible = false }
    }

    private func header(_ board: SessionBoardModel) -> some View {
        HStack(spacing: 10) {
            Text("Sessions")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(AnteStyle.textPrimary)
            if board.waitingCount > 0 {
                Text("\(board.waitingCount) waiting for you")
                    .font(AnteStyle.captionFont)
                    .foregroundStyle(.black.opacity(0.85))
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(accent, in: Capsule())
            }
            Spacer()
            Button {
                runtime.isSessionsViewerVisible = false
            } label: {
                Text("Back to terminal")
                    .font(AnteStyle.uiFont)
                    .foregroundStyle(AnteStyle.textSecondary)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.escape, modifiers: [])
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }
}

struct BoardColumnView: View {

    @Environment(\.anteAccent) private var accent
    let column: BoardColumn
    let cards: [SessionBoardModel.Card]
    let onSelect: (SessionBoardModel.Card) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Circle().fill(color).frame(width: 7, height: 7)
                Text(column.title.uppercased())
                    .font(AnteStyle.captionFont).tracking(0.6)
                    .foregroundStyle(AnteStyle.textSecondary)
                Text("\(cards.count)")
                    .font(AnteStyle.captionFont).monospacedDigit()
                    .foregroundStyle(AnteStyle.textSecondary)
                Spacer()
            }
            .padding(.horizontal, 4)
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(cards) { card in
                        SessionCardView(card: card).onTapGesture { onSelect(card) }
                    }
                    if cards.isEmpty {
                        Text(emptyText)
                            .font(AnteStyle.captionFont)
                            .foregroundStyle(AnteStyle.textSecondary.opacity(0.7))
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                }
                .padding(2)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(
            RoundedRectangle(cornerRadius: AnteStyle.radius + 3, style: .continuous)
                .fill(column == .waiting ? accent.opacity(0.06) : AnteStyle.rowHover)
        )
    }

    private var color: Color {
        switch column {
        case .working: return AnteStyle.statusRunning
        case .waiting: return accent
        case .idle: return AnteStyle.statusExited
        }
    }

    private var emptyText: String {
        switch column {
        case .working: return "Nothing running"
        case .waiting: return "No sessions waiting"
        case .idle: return "No idle shells"
        }
    }
}

struct SessionCardView: View {

    @Environment(\.anteChrome) private var chrome

    @Environment(\.anteAccent) private var accent
    let card: SessionBoardModel.Card

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(card.state.column == .waiting ? accent : AnteStyle.textSecondary)
                Text(card.agent.displayName)
                    .font(AnteStyle.captionFont)
                    .foregroundStyle(AnteStyle.textSecondary)
                Spacer()
                Text(elapsed)
                    .font(AnteStyle.captionFont).monospacedDigit()
                    .foregroundStyle(AnteStyle.textSecondary)
            }
            Text(card.sessionName)
                .font(AnteStyle.uiFontSemibold)
                .foregroundStyle(AnteStyle.textPrimary)
                .lineLimit(1)
            if !card.subtitle.isEmpty {
                Text(card.subtitle)
                    .font(AnteStyle.captionFont)
                    .foregroundStyle(AnteStyle.textSecondary)
                    .lineLimit(2)
            }
            badge
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: AnteStyle.radius, style: .continuous).fill(chrome.pane(AnteStyle.paneBackground)))
        .overlay(RoundedRectangle(cornerRadius: AnteStyle.radius, style: .continuous)
            .strokeBorder(card.state.column == .waiting ? accent.opacity(0.7) : AnteStyle.hairline))
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var badge: some View {
        switch card.state {
        case let .waitingDefinite(reason):
            Text("Waiting for you — \(reason)")
                .font(AnteStyle.captionFont)
                .foregroundStyle(.black.opacity(0.85))
                .padding(.horizontal, 7).padding(.vertical, 2)
                .background(accent, in: Capsule())
                .lineLimit(1)
        case .waitingProbable:
            Text("Probably waiting for you")
                .font(AnteStyle.captionFont)
                .foregroundStyle(accent)
                .padding(.horizontal, 7).padding(.vertical, 2)
                .overlay(Capsule().strokeBorder(accent.opacity(0.7)))
        case .working:
            Text("Working").font(AnteStyle.captionFont).foregroundStyle(AnteStyle.statusRunning)
        case .idle:
            Text("Idle").font(AnteStyle.captionFont).foregroundStyle(AnteStyle.textSecondary)
        }
    }

    private var symbol: String {
        switch card.agent {
        case .claude: return "sparkles"
        case .codex: return "cpu"
        case .pi: return "function"
        case .shell: return "terminal"
        case .command: return "play.circle"
        default: return "wand.and.stars"
        }
    }

    private var elapsed: String {
        let seconds = Int(Date().timeIntervalSince(card.since))
        if seconds < 60 { return "\(seconds)s" }
        if seconds < 3600 { return "\(seconds / 60)m" }
        return "\(seconds / 3600)h \(seconds % 3600 / 60)m"
    }
}
