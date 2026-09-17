// Packages/AnteUI/Sources/AnteUI/Panes/WallpaperView.swift
import SwiftUI
import AppKit
import AnteCore

/// The configured wallpaper behind every pane. Missing or unreadable images fall back to nothing,
/// silently: this is cosmetic.
struct WallpaperView: View {
    let config: AnteConfig.Wallpaper

    var body: some View {
        if let image = Self.load(config.path) {
            // The image must never drive layout: an unconstrained `scaledToFill` proposes the
            // photo's own size to the ZStack and the whole pane area grows to match (the toolbar
            // ends up above the window). `Color.clear` takes the container's size; the image is
            // only an overlay, clipped to it.
            Color.clear
                .overlay(
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                        .blur(radius: config.blur)
                )
                .clipped()
                .ignoresSafeArea()
        }
    }

    @MainActor private static var cache: [String: NSImage] = [:]

    /// Decoding a photo is tens of milliseconds; `body` runs far more often than that.
    @MainActor
    static func load(_ path: String) -> NSImage? {
        guard !path.isEmpty else { return nil }
        let expanded = (path as NSString).expandingTildeInPath
        if let cached = cache[expanded] { return cached }
        guard let image = NSImage(contentsOfFile: expanded) else { return nil }
        if cache.count > 4 { cache.removeAll() }
        cache[expanded] = image
        return image
    }
}
