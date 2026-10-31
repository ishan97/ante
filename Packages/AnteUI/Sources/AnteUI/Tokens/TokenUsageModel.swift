// Packages/AnteUI/Sources/AnteUI/Tokens/TokenUsageModel.swift
import Foundation
import Observation
import SwiftUI
import AnteCore

/// Behind the toolbar's token chip: the latest report, refreshed in the background. The ledger
/// remembers what it has read, so after the first scan a refresh only reads what agents appended.
@MainActor
@Observable
public final class TokenUsageModel {
    public internal(set) var report: TokenUsageReport?
    public private(set) var isRefreshing = false
    /// The window the popover is showing.
    public var selected: TokenUsageReport.Window = .day
    /// While the popover is open, a report that would change its shape waits here until it
    /// closes: a toolbar popover that resizes while shown animates the resize, which can crash
    /// AppKit. Reports that keep the shape apply at once.
    public var isPresented: Bool { presentations > 0 }
    /// Open popovers showing this model. A count, not a flag: reopening from the chip can show
    /// the new popover before the old one has said it is gone.
    @ObservationIgnored private var presentations = 0

    func popoverAppeared() { presentations += 1 }

    func popoverDisappeared() {
        presentations = max(0, presentations - 1)
        guard presentations == 0, heldReport != nil else { return }
        // A tick later, not while the popover is still closing.
        Task { @MainActor [weak self] in
            guard let self, !self.isPresented, let held = self.heldReport else { return }
            self.heldReport = nil
            self.report = held
        }
    }
    @ObservationIgnored private(set) var heldReport: TokenUsageReport?

    @ObservationIgnored private let ledger: TokenLedger
    @ObservationIgnored private var refreshTask: Task<Void, Never>?

    public init(ledger: TokenLedger = TokenLedger()) {
        self.ledger = ledger
    }

    /// Starts a scan unless one is already running; returns when the report is in.
    public func refresh() async {
        if let refreshTask { return await refreshTask.value }
        isRefreshing = true
        let task = Task { [ledger] in
            // Not inside `withAnimation`: the popover may be open, and an animated resize of a
            // toolbar popover can crash AppKit. The chip animates its own number.
            self.receive(await ledger.report())
        }
        refreshTask = task
        await task.value
        refreshTask = nil
        isRefreshing = false
    }

    /// Applies a fresh report now, or holds it until the popover closes when it would change the
    /// popover's height (see `isPresented`).
    func receive(_ next: TokenUsageReport) {
        if isPresented, let current = report, Self.shape(of: current) != Self.shape(of: next) {
            heldReport = next
        } else {
            heldReport = nil
            report = next
        }
    }

    /// What the popover's height depends on: whether there is anything to show, how many agents
    /// the legend lists and how many model lines there are. Never the selected window.
    nonisolated static func shape(of report: TokenUsageReport) -> [Int] {
        let year = report.slice(.year)
        return [report.isEmpty ? 0 : 1, year.byAgent.count, min(year.byModel.count, 5)]
    }

    /// Refreshes now and then every `interval` until the calling task is cancelled (the chip's
    /// `.task`, so nothing scans while there is no window to show it in).
    public func keepFresh(every interval: Duration = .seconds(300)) async {
        while !Task.isCancelled {
            await refresh()
            try? await Task.sleep(for: interval)
        }
    }

    /// `1,234` → "1.2K", `5_600_000` → "5.6M"; below a thousand the number itself.
    public nonisolated static func compact(_ tokens: Int) -> String {
        let units: [(Int, String)] = [(1_000_000_000_000, "T"), (1_000_000_000, "B"), (1_000_000, "M"), (1_000, "K")]
        for (scale, suffix) in units where tokens >= scale {
            // Three significant digits at most (1.24M, 12.4M, 124M), truncated so it never rounds
            // up past what was used. Integer maths: binary doubles would turn 1130 into "1.12K".
            let whole = tokens / scale
            let digits = whole >= 100 ? 0 : (whole >= 10 ? 1 : 2)
            let factor = [1, 10, 100][digits]
            let fraction = (tokens % scale) / (scale / factor)
            var decimals = digits == 0 ? "" : String(String(fraction + factor).dropFirst())   // zero-padded
            while decimals.hasSuffix("0") { decimals.removeLast() }
            return "\(whole)\(decimals.isEmpty ? "" : ".\(decimals)")\(suffix)"
        }
        return "\(max(0, tokens))"
    }
}
