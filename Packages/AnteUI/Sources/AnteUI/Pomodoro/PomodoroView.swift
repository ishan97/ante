// Packages/AnteUI/Sources/AnteUI/Pomodoro/PomodoroView.swift
import SwiftUI

/// The popover behind the toolbar's timer: a ring with the time left, start/pause, and the
/// lengths of a focus block and a break.
struct PomodoroView: View {
    @Bindable var model: PomodoroModel
    @Environment(\.anteAccent) private var accent

    private var phaseColor: Color { model.phase == .focus ? accent : AnteStyle.statusOK }

    var body: some View {
        VStack(spacing: 14) {
            HStack {
                Text(model.phase.label)
                    .font(AnteStyle.uiFontSemibold)
                    .foregroundStyle(AnteStyle.textPrimary)
                Spacer()
                Text(model.completedToday == 0 ? "No focus blocks yet today" : "\(model.completedToday) focus block\(model.completedToday == 1 ? "" : "s") today")
                    .font(AnteStyle.captionFont)
                    .foregroundStyle(AnteStyle.textSecondary)
            }
            ZStack {
                Circle().stroke(AnteStyle.rowHover, lineWidth: 8)
                Circle()
                    .trim(from: 0, to: model.progress)
                    .stroke(phaseColor, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 0.5), value: model.progress)
                VStack(spacing: 2) {
                    Text(model.display)
                        .font(.system(size: 34, weight: .medium, design: .rounded)).monospacedDigit()
                        .foregroundStyle(AnteStyle.textPrimary)
                    Text(model.state == .paused ? "paused" : (model.isRunning ? "running" : "ready"))
                        .font(AnteStyle.captionFont)
                        .foregroundStyle(AnteStyle.textSecondary)
                }
            }
            .frame(width: 150, height: 150)
            HStack(spacing: 8) {
                Button(model.isRunning ? "Pause" : (model.state == .paused ? "Resume" : "Start")) { model.toggle() }
                    .keyboardShortcut(.space, modifiers: [])
                    .buttonStyle(.borderedProminent)
                    .tint(phaseColor)
                Button("Reset") { model.reset() }.disabled(!model.isActive)
                Button("Skip") { model.skip() }
            }
            .controlSize(.regular)
            Divider().overlay(AnteStyle.hairline)
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                GridRow {
                    Text("Focus").font(AnteStyle.captionFont).foregroundStyle(AnteStyle.textSecondary)
                    DurationField(minutes: $model.focusMinutes, range: 1...120)
                }
                GridRow {
                    Text("Break").font(AnteStyle.captionFont).foregroundStyle(AnteStyle.textSecondary)
                    DurationField(minutes: $model.breakMinutes, range: 1...60)
                }
                GridRow {
                    Text("Long break").font(AnteStyle.captionFont).foregroundStyle(AnteStyle.textSecondary)
                    DurationField(minutes: $model.longBreakMinutes, range: 1...90, suffix: "min, every \(model.blocksPerLongBreak)th")
                }
            }
            .disabled(model.isActive)
        }
        .padding(16)
        .frame(width: 280)
        .background(AnteStyle.paneBackground)
    }
}

/// A minutes value you can type directly or nudge one minute at a time.
/// Typed text is applied when you press Return or leave the field, and is
/// clamped to `range`; anything that is not a number reverts to the current value.
struct DurationField: View {
    @Binding var minutes: Int
    let range: ClosedRange<Int>
    var suffix: String = "min"
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 6) {
            TextField("", text: $text)
                .textFieldStyle(.roundedBorder)
                .font(AnteStyle.uiFont)
                .monospacedDigit()
                .multilineTextAlignment(.trailing)
                .frame(width: 44)
                .focused($focused)
                .onSubmit(commit)
                .onChange(of: focused) { _, isFocused in if !isFocused { commit() } }
            Stepper("", value: $minutes, in: range, step: 1).labelsHidden()
            Text(suffix).font(AnteStyle.uiFont).monospacedDigit()
        }
        .onAppear { text = String(minutes) }
        .onChange(of: minutes) { _, value in
            if !focused { text = String(value) }
        }
    }

    private func commit() {
        minutes = Self.parse(text, in: range, fallback: minutes)
        text = String(minutes)
    }

    /// Whole minutes typed by the user, clamped to `range`; anything that is not a
    /// number (empty, "abc", "1.5") keeps `fallback`.
    static func parse(_ text: String, in range: ClosedRange<Int>, fallback: Int) -> Int {
        guard let value = Int(text.trimmingCharacters(in: .whitespacesAndNewlines)) else { return fallback }
        return min(range.upperBound, max(range.lowerBound, value))
    }
}
