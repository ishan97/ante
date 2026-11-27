// Packages/AnteUI/Sources/AnteUI/Accounts/AccountChip.swift
import AppKit
import SwiftUI
import AnteCore
import AnteTerm

/// "Claude · Work ▾" in the corner of a pane running Claude or Codex, when the agent has more
/// than one account. Its menu continues the conversation on another account.
struct AccountChip: View {
    @Bindable var runtime: WorkspaceRuntime
    let pane: PaneID
    let controller: TerminalSessionController
    @State private var isSwitching = false

    var body: some View {
        if let agent = AccountAgent(agentKind: controller.agent), runtime.accounts.accounts(for: agent).count >= 2 {
            let current = runtime.account(in: pane)
            Menu {
                Section("Continue this conversation on…") {
                    ForEach(runtime.accounts.accounts(for: agent).filter { $0 != current }, id: \.id) { account in
                        AccountMenuItem(account: account) { requestSwitch(to: account, agent: agent) }
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
