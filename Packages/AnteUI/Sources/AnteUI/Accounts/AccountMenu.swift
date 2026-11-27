// Packages/AnteUI/Sources/AnteUI/Accounts/AccountMenu.swift
import SwiftUI
import AnteCore

/// One account as a menu item: its name, then email and plan.
struct AccountMenuItem: View {
    let account: AgentAccount
    var isCurrent = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            if isCurrent {
                Label(title, systemImage: "checkmark")
            } else {
                Text(title)
            }
        }
    }

    private var title: String { AccountMenuItem.title(for: account) }

    /// "Work — me@work.com · Pro"; the email is left out when it is the name.
    static func title(for account: AgentAccount) -> String {
        let detail = [account.email == account.name ? nil : account.email, account.plan].compactMap { $0 }.joined(separator: " · ")
        return detail.isEmpty ? account.name : "\(account.name) — \(detail)"
    }
}

/// The accounts of one agent, the one used last first, each starting `pick`.
struct AccountMenuItems: View {
    let accounts: [AgentAccount]
    var lastUsedID: String?
    var currentID: String?
    let pick: (AgentAccount) -> Void

    var body: some View {
        ForEach(ordered, id: \.id) { account in
            AccountMenuItem(account: account, isCurrent: account.id == currentID) { pick(account) }
        }
    }

    private var ordered: [AgentAccount] {
        guard let lastUsedID, let index = accounts.firstIndex(where: { $0.id == lastUsedID }) else { return accounts }
        var list = accounts
        list.insert(list.remove(at: index), at: 0)
        return list
    }
}

/// The toolbar's "New agent session" menu: one entry per agent, or per account when the agent
/// has a choice to make (no default set). Antigravity has one Google sign-in and no accounts in
/// Ante, so it is a single entry.
struct NewAgentSessionMenu: View {
    @Bindable var runtime: WorkspaceRuntime

    var body: some View {
        Menu {
            ForEach(AccountAgent.allCases, id: \.self) { agent in
                let accounts = runtime.accounts.accounts(for: agent)
                if runtime.accounts.needsAsking(agent) {
                    Section("New \(agent.displayName) session") {
                        AccountMenuItems(accounts: accounts) { start(agent, as: $0) }
                    }
                } else {
                    let account = runtime.accounts.automaticAccount(for: agent)
                    Button(account.map { "New \(agent.displayName) session as \($0.name)" } ?? "New \(agent.displayName) session") {
                        start(agent, as: account)
                    }
                }
            }
            Divider()
            if let command = AgentKind.antigravity.pickerCommand {
                Button("New \(AgentKind.antigravity.displayName) session") { start(command) }
            }
        } label: {
            Image(systemName: "sparkles.rectangle.stack")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(AnteStyle.textSecondary)
                .frame(width: 24, height: 22)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("New Claude, Codex or Antigravity session")
    }

    private func start(_ agent: AccountAgent, as account: AgentAccount?) {
        guard let project else { return }
        runtime.startAgent(agent, account: account, inNewSessionOf: project)
    }

    private func start(_ command: String) {
        guard let project else { return }
        runtime.start(command, inNewSessionOf: project)
    }

    /// The focused session's project, else the first one.
    private var project: ProjectID? {
        runtime.store.focusedSession?.projectID ?? runtime.store.state.orderedProjects.first?.id
    }
}

/// After a relaunch: which account each restored Claude/Codex pane comes back as.
struct RestoreAccountsSheet: View {
    @Bindable var runtime: WorkspaceRuntime
    @State private var choices: [PaneID: String] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Resume your agent sessions as…")
                .font(.system(size: 15, weight: .semibold))
            Text("Pick the account each conversation continues on. Set a default in Settings › Agents to skip this.")
                .font(AnteStyle.captionFont)
                .foregroundStyle(AnteStyle.textSecondary)
            if Set(runtime.pendingRestores.map(\.agent)).count == 1, let agent = runtime.pendingRestores.first?.agent,
               runtime.pendingRestores.count > 1 {
                HStack {
                    Text("Use the same account for all")
                    Spacer()
                    Menu("Choose…") {
                        AccountMenuItems(accounts: runtime.accounts.accounts(for: agent)) { account in
                            for item in runtime.pendingRestores { choices[item.pane] = account.id }
                        }
                    }
                    .fixedSize()
                }
                Divider()
            }
            ForEach(runtime.pendingRestores) { item in
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title).font(AnteStyle.uiFont).lineLimit(1)
                        Text("\(item.agent.displayName) · \(item.folder)").font(AnteStyle.captionFont).foregroundStyle(AnteStyle.textSecondary)
                    }
                    Spacer()
                    Picker("", selection: binding(for: item)) {
                        ForEach(runtime.accounts.accounts(for: item.agent), id: \.id) { account in
                            Text(AccountMenuItem.title(for: account)).tag(account.id)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 260)
                }
            }
            HStack {
                Button("Skip agents") { runtime.skipRestoreAgents() }
                Spacer()
                Button("Resume") {
                    var picked: [PaneID: AgentAccount?] = [:]
                    for item in runtime.pendingRestores {
                        picked[item.pane] = runtime.accounts.account(id: choices[item.pane], agent: item.agent)
                    }
                    runtime.confirmRestore(picked)
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 520)
        .onAppear {
            for item in runtime.pendingRestores where choices[item.pane] == nil {
                choices[item.pane] = (item.preselected ?? runtime.accounts.accounts(for: item.agent).first)?.id
            }
        }
    }

    private func binding(for item: RestoreItem) -> Binding<String> {
        Binding(get: { choices[item.pane] ?? "" }, set: { choices[item.pane] = $0 })
    }
}
