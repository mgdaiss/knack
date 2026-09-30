import KnackCore
import SwiftUI

/// One large step at a time, readable from the stove, with built-in timers.
struct CookModeView: View {
    let recipe: Recipe
    let accent: Color
    let onTimerDone: (String) -> Void
    let onClose: () -> Void

    @State private var index = 0
    @State private var timerEnd: Date?
    @State private var timerStep: Int?

    private var step: RecipeStep { recipe.steps[index] }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack {
                Text(recipe.title).font(Theme.Fonts.sectionTitle)
                Spacer()
                Text("Step \(index + 1) of \(recipe.steps.count)").font(Theme.Fonts.bodyBold).foregroundStyle(Theme.Colors.muted)
                Button("Done", action: onClose).buttonStyle(SoftPillButtonStyle()).keyboardShortcut(.cancelAction)
            }
            if index == 0 {
                Text(recipe.ingredients.map { [$0.amount, $0.name].compactMap { $0 }.joined(separator: " ") }.joined(separator: " · "))
                    .font(Theme.Fonts.body)
                    .foregroundStyle(Theme.Colors.muted)
            }
            Text(step.text)
                .font(Theme.Fonts.nunito(40, .black, relativeTo: .largeTitle))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            timerView
            HStack {
                Button("Back") { move(-1) }
                    .buttonStyle(SoftPillButtonStyle())
                    .keyboardShortcut(.leftArrow, modifiers: [])
                    .disabled(index == 0)
                Spacer()
                if index < recipe.steps.count - 1 {
                    Button("Next") { move(1) }
                        .buttonStyle(PillButtonStyle(fill: accent, pressedFill: accent.opacity(0.85)))
                        .keyboardShortcut(.rightArrow, modifiers: [])
                } else {
                    Button("Enjoy!", action: onClose).buttonStyle(PillButtonStyle(fill: accent, pressedFill: accent.opacity(0.85)))
                }
            }
        }
        .padding(36)
        .frame(width: 820, height: 560)
        .background(Theme.Colors.bg)
        .font(Theme.Fonts.body)
        .foregroundStyle(Theme.Colors.ink)
    }

    @ViewBuilder
    private var timerView: some View {
        if let end = timerEnd, let timerStep {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let remaining = max(0, Int(end.timeIntervalSince(context.date).rounded(.up)))
                HStack(spacing: 12) {
                    Image(systemName: "timer").accessibilityHidden(true)
                    Text(remaining == 0 ? "Time's up!" : String(format: "%d:%02d", remaining / 60, remaining % 60))
                        .font(Theme.Fonts.nunito(28, .black))
                        .monospacedDigit()
                    if timerStep != index { Text("(step \(timerStep + 1))").foregroundStyle(Theme.Colors.muted) }
                    Button("Cancel") { timerEnd = nil; self.timerStep = nil }.buttonStyle(SoftPillButtonStyle())
                }
                .foregroundStyle(accent)
            }
        } else if let seconds = step.timerSeconds {
            Button("Start \(seconds / 60 > 0 ? "\(seconds / 60) min" : "\(seconds) sec") timer") { startTimer(seconds) }
                .buttonStyle(PillButtonStyle(fill: accent, pressedFill: accent.opacity(0.85)))
        }
    }

    private func move(_ delta: Int) {
        index = min(max(0, index + delta), recipe.steps.count - 1)
    }

    private func startTimer(_ seconds: Int) {
        let end = Date().addingTimeInterval(TimeInterval(seconds))
        timerEnd = end
        timerStep = index
        let text = step.text
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(seconds) * 1_000_000_000)
            guard timerEnd == end else { return }
            onTimerDone(text)
        }
    }
}
