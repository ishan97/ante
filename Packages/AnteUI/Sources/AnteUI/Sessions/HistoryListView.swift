// Packages/AnteUI/Sources/AnteUI/Sessions/HistoryListView.swift
import SwiftUI
import AnteCore

/// Past sessions from every source, newest first, grouped by day. Click a row to resume.
struct HistoryListView: View {
    @Environment(\.anteChrome) private var chrome
    @Bindable var board: SessionBoardModel
    let onResume: (PastSession) -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Text("History")
                    .font(AnteStyle.uiFontSemibold)
                    .foregroundStyle(AnteStyle.textPrimary)
                if board.isLoadingHistory {
                    ProgressView().controlSize(.small)
                } else {
                    Text("\(board.filteredHistory.count)")
                        .font(AnteStyle.captionFont).monospacedDigit()
                        .foregroundStyle(AnteStyle.textSecondary)
                }
                Spacer()
                Picker("", selection: $board.agentFilter) {
                    Text("All agents").tag(AgentKind?.none)
                    ForEach(board.historyAgents, id: \.self) { agent in
                        Text(agent.displayName).tag(AgentKind?.some(agent))
                    }
                }
                .labelsHidden()
                .frame(width: 150)
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").foregroundStyle(AnteStyle.textSecondary)
                    TextField("", text: $board.query, prompt: Text("Search sessions"))
                        .textFieldStyle(.plain)
                        .font(AnteStyle.uiFont)
                }
                .padding(.horizontal, 8).padding(.vertical, 5)
                .background(AnteStyle.rowHover, in: RoundedRectangle(cornerRadius: AnteStyle.radius, style: .continuous))
                .frame(width: 240)
                Button {
                    Task { await board.reloadHistory() }
                } label: {
                    Image(systemName: "arrow.clockwise").foregroundStyle(AnteStyle.textSecondary)
                }
                .buttonStyle(.plain)
                .help("Rescan")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2, pinnedViews: [.sectionHeaders]) {
                    ForEach(groups, id: \.title) { group in
                        Section {
                            ForEach(group.rows) { row in
                                HistoryRow(session: row).onTapGesture { onResume(row) }
                            }
                        } header: {
                            Text(group.title.uppercased())
                                .font(AnteStyle.captionFont).tracking(0.6)
                                .foregroundStyle(AnteStyle.textSecondary)
                                .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 4)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(chrome.pane(AnteStyle.paneBackground))
                        }
                    }
                    if groups.isEmpty, !board.isLoadingHistory {
                        Text(board.query.isEmpty ? "No past sessions found" : "No matches")
                            .font(AnteStyle.uiFont)
                            .foregroundStyle(AnteStyle.textSecondary)
                            .padding(24)
                            .frame(maxWidth: .infinity)
                    } else if board.query.isEmpty, board.agentFilter == nil, !board.isLoadingHistory {
                        // The list is everything on disk; say so, and why it stops where it does.
                        Text("All \(board.history.count) sessions on this Mac. Claude Code deletes transcripts after \(board.claudeRetentionDays) days — change that in Settings › Agents.")
                            .font(AnteStyle.captionFont)
                            .foregroundStyle(AnteStyle.textSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24).padding(.vertical, 16)
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(.bottom, 12)
            }
        }
    }

    private struct Group { let title: String; let rows: [PastSession] }

    private var groups: [Group] {
        let calendar = Calendar.current
        var buckets: [(Date, [PastSession])] = []
        for row in board.filteredHistory {
            let day = calendar.startOfDay(for: row.modifiedAt)
            if let index = buckets.firstIndex(where: { $0.0 == day }) {
                buckets[index].1.append(row)
            } else {
                buckets.append((day, [row]))
            }
        }
        return buckets.map { day, rows in
            let title: String
            if calendar.isDateInToday(day) { title = "Today" }
            else if calendar.isDateInYesterday(day) { title = "Yesterday" }
            else { title = day.formatted(date: .abbreviated, time: .omitted) }
            return Group(title: title, rows: rows)
        }
    }
}

private struct HistoryRow: View {

    @Environment(\.anteAccent) private var accent
    let session: PastSession
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .frame(width: 16)
                .foregroundStyle(AnteStyle.textSecondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(session.title)
                    .font(AnteStyle.uiFont)
                    .foregroundStyle(AnteStyle.textPrimary)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(session.agent.displayName)
                    Text("·")
                    Text(session.projectName)
                    if let detail = session.detail, !detail.isEmpty {
                        Text("·")
                        Text(detail).lineLimit(1)
                    }
                }
                .font(AnteStyle.captionFont)
                .foregroundStyle(AnteStyle.textSecondary)
            }
            Spacer()
            Text(session.modifiedAt.formatted(.relative(presentation: .named)))
                .font(AnteStyle.captionFont)
                .foregroundStyle(AnteStyle.textSecondary)
            Text(session.resumeCommand == nil ? "Reopen" : "Resume")
                .font(AnteStyle.captionFont)
                .foregroundStyle(accent)
                .opacity(hovering ? 1 : 0)
        }
        .padding(.horizontal, 12)
        .frame(height: 40)
        .background(RoundedRectangle(cornerRadius: AnteStyle.radius, style: .continuous).fill(hovering ? AnteStyle.rowHover : .clear))
        .padding(.horizontal, 8)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }

    private var symbol: String {
        switch session.agent {
        case .claude: return "sparkles"
        case .codex: return "cpu"
        case .pi: return "function"
        case .shell, .command: return "terminal"
        default: return "wand.and.stars"
        }
    }
}
