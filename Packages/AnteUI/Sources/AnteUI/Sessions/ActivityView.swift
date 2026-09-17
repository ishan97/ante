// Packages/AnteUI/Sources/AnteUI/Sessions/ActivityView.swift
import SwiftUI
import AppKit
import AnteCore

/// A year of agent activity at a glance: a few numbers and a contribution-graph heat strip of
/// prompts per day. Purely for the pleasure of seeing the work pile up.
struct ActivityView: View {
    let stats: ActivityStats
    @State private var hovered: ActivityStats.Day?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 18) {
                Text("Activity")
                    .font(AnteStyle.uiFontSemibold)
                    .foregroundStyle(AnteStyle.textPrimary)
                stat(stats.totalPrompts.formatted(), "prompts")
                stat(stats.totalSessions.formatted(), "sessions")
                stat("\(stats.activeDays)", "active days")
                stat("\(stats.currentStreak)", stats.currentStreak == 1 ? "day streak" : "day streak", detail: stats.longestStreak > stats.currentStreak ? "best \(stats.longestStreak)" : nil)
                if let hour = stats.busiestHour {
                    stat(Self.hourLabel(hour), "busiest hour")
                }
                Spacer()
                if let day = hovered {
                    Text("\(day.prompts) prompt\(day.prompts == 1 ? "" : "s") · \(day.sessions) session\(day.sessions == 1 ? "" : "s") · \(day.date.formatted(date: .abbreviated, time: .omitted))")
                        .font(AnteStyle.captionFont).monospacedDigit()
                        .foregroundStyle(AnteStyle.textSecondary)
                } else if let best = stats.busiestDay {
                    Text("busiest day \(best.date.formatted(date: .abbreviated, time: .omitted)) · \(best.prompts) prompts")
                        .font(AnteStyle.captionFont).monospacedDigit()
                        .foregroundStyle(AnteStyle.textSecondary.opacity(0.8))
                }
            }
            heatmap
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func stat(_ value: String, _ label: String, detail: String? = nil) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(value).font(AnteStyle.uiFontSemibold).monospacedDigit().foregroundStyle(AnteStyle.textPrimary)
            Text(label).font(AnteStyle.captionFont).foregroundStyle(AnteStyle.textSecondary)
            if let detail {
                Text("(\(detail))").font(AnteStyle.captionFont).foregroundStyle(AnteStyle.textSecondary.opacity(0.7))
            }
        }
    }

    // MARK: - Heat strip

    /// Contribution-graph greens, quietest to busiest, for dark and light chrome.
    private static let greens: [Color] = [
        dynamicGreen(dark: 0x0E4429, light: 0x9BE9A8), dynamicGreen(dark: 0x006D32, light: 0x40C463),
        dynamicGreen(dark: 0x26A641, light: 0x30A14E), dynamicGreen(dark: 0x39D353, light: 0x216E39),
    ]

    private static func dynamicGreen(dark: Int, light: Int) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let hex = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
        })
    }

    /// Which green a day gets: quartiles of the active days' counts, like GitHub.
    private static func level(for prompts: Int, thresholds: [Int]) -> Int {
        thresholds.lastIndex { prompts >= $0 } ?? 0
    }

    private static let rows = 7
    private static let gap: CGFloat = 2
    private static let labelWidth: CGFloat = 26
    private static let monthRow: CGFloat = 20   // month labels sit here, clear of the top row

    private var weeks: [[ActivityStats.Day?]] {
        // Columns are weeks, rows Sunday…Saturday; the first column is padded so weekdays line up.
        let calendar = Calendar.current
        var columns: [[ActivityStats.Day?]] = []
        var column: [ActivityStats.Day?] = []
        if let first = stats.days.first {
            let weekday = calendar.component(.weekday, from: first.date) - 1
            column = Array(repeating: nil, count: weekday)
        }
        for day in stats.days {
            column.append(day)
            if column.count == Self.rows { columns.append(column); column = [] }
        }
        if !column.isEmpty { columns.append(column + Array(repeating: nil, count: Self.rows - column.count)) }
        return columns
    }

    private var heatmap: some View {
        let columns = weeks
        let active = stats.days.map(\.prompts).filter { $0 > 0 }.sorted()
        let thresholds = active.isEmpty ? [1, 2, 3, 4]
            : [1, active[active.count / 4], active[active.count / 2], active[active.count * 3 / 4]].enumerated().map { i, v in max(v, i + 1) }
        return GeometryReader { proxy in
            let cell = max(5, min(16, floor((proxy.size.width - Self.labelWidth) / CGFloat(max(columns.count, 1)) - Self.gap)))
            let step = cell + Self.gap
            let calendar = Calendar.current
            Canvas { context, _ in
                var lastMonth = -1
                var lastLabelColumn = -10
                for (c, column) in columns.enumerated() {
                    let x = Self.labelWidth + CGFloat(c) * step
                    // A month label where a month begins, but never on the first column (it would be
                    // a partial month) and never closer than three weeks to the previous label.
                    if let firstDay = column.compactMap({ $0 }).first {
                        let month = calendar.component(.month, from: firstDay.date)
                        if month != lastMonth {
                            if c > 0, c - lastLabelColumn >= 3 {
                                let name = firstDay.date.formatted(.dateTime.month(.abbreviated))
                                context.draw(Text(name).font(AnteStyle.captionFont).foregroundStyle(AnteStyle.textSecondary),
                                             at: CGPoint(x: x, y: 2), anchor: .topLeading)
                                lastLabelColumn = c
                            }
                            lastMonth = month
                        }
                    }
                    for (r, day) in column.enumerated() {
                        guard let day else { continue }
                        let rect = CGRect(x: x, y: Self.monthRow + CGFloat(r) * step, width: cell, height: cell)
                        let path = Path(roundedRect: rect, cornerRadius: 2)
                        if day.prompts == 0 {
                            context.fill(path, with: .color(AnteStyle.rowHover))
                        } else {
                            context.fill(path, with: .color(Self.greens[Self.level(for: day.prompts, thresholds: thresholds)]))
                        }
                        if let hovered, hovered == day {
                            context.stroke(path, with: .color(AnteStyle.textPrimary), lineWidth: 1)
                        }
                    }
                }
                for (r, label) in [(1, "Mon"), (3, "Wed"), (5, "Fri")] {
                    context.draw(Text(label).font(.system(size: 8.5)).foregroundStyle(AnteStyle.textSecondary),
                                 at: CGPoint(x: 0, y: Self.monthRow + CGFloat(r) * step + cell / 2), anchor: .leading)
                }
            }
            .onContinuousHover { phase in
                switch phase {
                case let .active(point):
                    let c = Int((point.x - Self.labelWidth) / step), r = Int((point.y - Self.monthRow) / step)
                    hovered = (columns.indices.contains(c) && (0..<Self.rows).contains(r)) ? columns[c][r] : nil
                case .ended:
                    hovered = nil
                }
            }
        }
        .frame(height: Self.monthRow + CGFloat(Self.rows) * 18 + 4)
    }

    static func hourLabel(_ hour: Int) -> String {
        var c = DateComponents(); c.hour = hour
        return Calendar.current.date(from: c)?.formatted(.dateTime.hour(.defaultDigits(amPM: .abbreviated))) ?? "\(hour):00"
    }
}
