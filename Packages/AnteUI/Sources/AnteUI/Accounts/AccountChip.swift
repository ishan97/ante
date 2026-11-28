// Packages/AnteUI/Sources/AnteUI/Accounts/AccountChip.swift
import AppKit
import SwiftUI
import AnteCore
import AnteTerm

/// "Claude · Work ▾" in the corner of a pane running Claude or Codex, when the agent has more
/// than one account. Its menu continues the conversation on another account. A pane running
/// Antigravity CLI shows the Google account it signs in as, without a menu.
struct AccountChip: View {
    @Bindable var runtime: WorkspaceRuntime
    let pane: PaneID
    let controller: TerminalSessionController
    @State private var isSwitching = false

    var body: some View {
        // The chip itself may be empty (agy has never signed in yet), and a task on an empty view
        // never runs, so the refresh hangs off a zero-size view that is always there.
        HStack(spacing: 0) {
            Color.clear.frame(width: 0, height: 0)
                .task(id: controller.agent == .antigravity ? controller.foreground?.pid : nil) { await refreshSignIn() }
            chip
        }
    }

    /// A new agy run logs its sign-in a moment after it starts: read it then, and again a little
    /// later, so the chip shows this run's account rather than the previous run's.
    private func refreshSignIn() async {
        guard controller.agent == .antigravity else { return }
        for delay in [2.0, 6.0] {
            try? await Task.sleep(for: .seconds(delay))
            if Task.isCancelled { return }
            await runtime.accounts.refreshAntigravitySignIn()
        }
    }

    @ViewBuilder
    private var chip: some View {
        if controller.agent == .antigravity, let signIn = runtime.accounts.antigravitySignIn {
            // One sign-in, shared with the Antigravity app: shown, never switched from here.
            Text("Antigravity · \(signIn.email)")
                .font(AnteStyle.captionFont)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: 240)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(AnteStyle.hairline))
                .help("The Google account agy last signed in as. Run /logout and /login inside agy to change it.")
        } else if let agent = AccountAgent(agentKind: controller.agent), runtime.accounts.accounts(for: agent).count >= 2 {
            let current = runtime.account(in: pane)
            Menu {
                Section("Continue this conversation on…") {
                    ForEach(runtime.accounts.accounts(for: agent).filter { $0 != current }, id: \.id) { account in
                        AccountMenuItem(account: account, limits: runtime.accounts.limitsLine(for: account)) { requestSwitch(to: account, agent: agent) }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    if isSwitching { ProgressView().controlSize(.mini) }
                    Text("\(agent.displayName) · \(current?.name ?? "other sign-in")")
                        .font(AnteStyle.captionFont)
                        .lineLimit(1)
                }
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(AnteStyle.hairline))
            .disabled(isSwitching)
            .help("Its history is sent to the account you pick with your next message.")
        }
    }

    private func requestSwitch(to account: AgentAccount, agent: AccountAgent) {
        if runtime.liveConversation(in: pane).isBusy {
            let alert = NSAlert()
            alert.messageText = "\(agent.displayName) is working. Stop it and switch to \(account.name)?"
            alert.informativeText = "The reply in progress stops, and text you haven't sent is lost. The conversation continues on \(account.name)."
            alert.addButton(withTitle: "Stop and Switch")
            alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        isSwitching = true
        Task { @MainActor in
            let outcome = await runtime.switchAccount(pane: pane, to: account)
            isSwitching = false
            if outcome == .cancelled {
                let alert = NSAlert()
                alert.messageText = "Couldn't switch to \(account.name)"
                alert.informativeText = "\(agent.displayName) didn't exit, so nothing was started. Quit it yourself, then resume as \(account.name)."
                alert.runModal()
            }
        }
    }
}
