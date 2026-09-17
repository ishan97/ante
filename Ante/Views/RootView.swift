// Ante/Views/RootView.swift
import SwiftUI
import AnteUI

struct RootView: View {
    @Environment(AppRuntime.self) private var app

    var body: some View {
        WorkspaceView(runtime: app.workspace, toggleWindow: { app.hotkey?.toggle() })
            .frame(minWidth: 720, minHeight: 420)
    }
}
