// Packages/AnteUI/Sources/AnteUI/Accounts/AccountsSettingsSection.swift
import AppKit
import SwiftUI
import AnteCore

/// Settings › Agents › Accounts: every signed-in Claude and Codex account, adding and removing
/// them, and which one starts without asking.
struct AccountsSettingsSection: View {
    @Bindable var runtime: WorkspaceRuntime
    @State private var message: String?
    @State private var adding: AccountAgent?

    private var accounts: AccountsModel { runtime.accounts }

    var body: some View {
        ForEach(AccountAgent.allCases, id: \.self) { agent in
            Section("\(agent.displayName) accounts") {
                let list = accounts.accounts(for: agent)
                if list.isEmpty {
                    Text("No accounts yet. Your existing \(agent.displayName) sign-in shows up here on its own.")
                        .font(AnteStyle.captionFont).foregroundStyle(AnteStyle.textSecondary)
                }
                ForEach(list, id: \.id) { account in
                    AccountRow(account: account, accounts: accounts)
                }
                HStack {
                    Button(adding == agent ? "Signing in…" : "Add \(agent.displayName) Account…") { add(agent) }
                        .disabled(adding != nil || accounts.loginPin(for: agent) != nil)
                    Spacer()
                }
                if let pin = accounts.loginPin(for: agent) {
                    Text("Your Claude settings pin every session to one sign-in (\(pin) in ~/.claude/settings.json), so other accounts would have no effect. Remove it to add accounts.")
                        .font(AnteStyle.captionFont).foregroundStyle(AnteStyle.statusFailed)
                }
                if list.count >= 2 {
                    Picker("When starting \(agent.displayName)", selection: defaultBinding(agent)) {
                        Text("Ask every time").tag("")
                        ForEach(list, id: \.id) { Text("Always use \($0.name)").tag($0.id) }
                    }
                    Text("Typing \(agent.executable) in a pane asks which account, as do Resume and reopening sessions. A default skips the question. The account chip on a running pane moves its conversation to another account.")
                        .font(AnteStyle.captionFont).foregroundStyle(AnteStyle.textSecondary)
                }
            }
        }
        Section("\(AgentKind.antigravity.displayName) account") {
            if let signIn = accounts.antigravitySignIn {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Last seen signed in as \(signIn.email)")
                    Text("When agy started \(signIn.at.formatted(.relative(presentation: .named)))\(signIn.method == "consumer" ? " · personal Google account" : "")")
                        .font(AnteStyle.captionFont).foregroundStyle(AnteStyle.textSecondary)
                }
            } else {
                Text("Not signed in yet. Run agy in a pane and sign in with Google; it shows up here.")
                    .font(AnteStyle.captionFont).foregroundStyle(AnteStyle.textSecondary)
            }
            Text("Antigravity keeps one Google sign-in, shared with the Antigravity app, so every agy session and resume uses it. To change it, run /logout and then /login inside agy. Ante reads it from agy's log, so a sign-out shows here only once agy runs again.")
                .font(AnteStyle.captionFont).foregroundStyle(AnteStyle.textSecondary)
        }
        .task { await accounts.refreshAntigravitySignIn() }
        if let warning = accounts.retentionWarning() {
            Text(warning).font(AnteStyle.captionFont).foregroundStyle(AnteStyle.statusFailed)
        }
        if let message {
            Text(message).font(AnteStyle.captionFont).foregroundStyle(AnteStyle.textSecondary)
        }
    }

    private func defaultBinding(_ agent: AccountAgent) -> Binding<String> {
        Binding(get: { accounts.defaultAccount(for: agent)?.id ?? "" },
                set: { id in accounts.setDefault(accounts.account(id: id.isEmpty ? nil : id, agent: agent), for: agent) })
    }

    private func add(_ agent: AccountAgent) {
        adding = agent
        message = "Sign in in the \"Sign in to \(agent.displayName)\" session in Ante's window; your browser opens."
        NSApp.activate()
        Task { @MainActor in
            let outcome = await runtime.addAccount(agent)
            adding = nil
            switch outcome {
            case let .added(account):
                message = "Added \(account.name). Conversations, skills and settings are shared with your other accounts; MCP servers that sign in with OAuth need signing in again on it."
            case let .duplicate(existing):
                message = "That's the same sign-in as \(existing.name), so it wasn't added again."
            case .failed:
                message = "The sign-in didn't finish, so no account was added."
            }
        }
    }
}

/// One account: its name (renamable), email and plan, state, and Remove.
private struct AccountRow: View {
    let account: AgentAccount
    let accounts: AccountsModel
    @State private var name = ""
    @State private var confirmRemove = false

    var body: some View {
        HStack(spacing: 10) {
            Circle().fill(color).frame(width: 7, height: 7).help(stateHelp)
            VStack(alignment: .leading, spacing: 2) {
                TextField("Name", text: $name)
                    .textFieldStyle(.plain)
                    .labelsHidden()   // in a grouped Form the label would take the left column
                    .onSubmit { accounts.rename(account, to: name) }
                Text([account.email, account.org, account.plan, account.isDefaultFolder ? "your original sign-in" : nil]
                    .compactMap { $0 }.joined(separator: " · "))
                    .font(AnteStyle.captionFont).foregroundStyle(AnteStyle.textSecondary)
                if !problems.isEmpty {
                    Text("Not shared with your other accounts: \(problems.map(\.name).joined(separator: ", ")). Ante leaves these alone; move them yourself if you want them shared.")
                        .font(AnteStyle.captionFont).foregroundStyle(AnteStyle.statusFailed)
                }
            }
            Spacer()
            if !account.isDefaultFolder {
                Button("Remove…") { confirmRemove = true }
                    .confirmationDialog("Remove \(account.name)?", isPresented: $confirmRemove) {
                        Button("Sign Out and Remove", role: .destructive) { Task { await accounts.remove(account) } }
                    } message: {
                        Text("Ante signs this account out. Your conversations stay, and any other account can resume them.")
                    }
            }
        }
        .onAppear { name = account.name }
        .onChange(of: account.name) { name = $1 }
    }

    private var problems: [AccountFolderProblem] { accounts.problems(for: account) }

    private var color: Color {
        if !problems.isEmpty { return .orange }
        return accounts.isSignedIn(account) == false ? AnteStyle.statusFailed : .green
    }

    private var stateHelp: String {
        if !problems.isEmpty { return "Needs attention" }
        return accounts.isSignedIn(account) == false ? "Signed out: start the agent as this account and sign in" : "Signed in"
    }
}
