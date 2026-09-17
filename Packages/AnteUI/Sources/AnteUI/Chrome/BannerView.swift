// Packages/AnteUI/Sources/AnteUI/Chrome/BannerView.swift
import SwiftUI

/// A non-blocking, dismissible notice: config problems, state recovery. Never a modal.
struct BannerView: View {
    @Environment(\.anteAccent) private var accent
    let text: String
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(accent)
            Text(text)
                .font(AnteStyle.uiFont)
                .foregroundStyle(AnteStyle.textPrimary)
                .lineLimit(2)
            Spacer()
            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(AnteStyle.textSecondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: AnteStyle.radius, style: .continuous))
        .padding(.horizontal, AnteStyle.paneInset)
        .padding(.top, 6)
    }
}
