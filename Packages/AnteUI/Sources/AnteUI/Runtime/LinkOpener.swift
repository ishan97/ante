// Packages/AnteUI/Sources/AnteUI/Runtime/LinkOpener.swift
import AppKit
import UniformTypeIdentifiers
import AnteTerm

/// Decides what a ⌘-click does. Files open in the text editor, directories are revealed in Finder,
/// URLs go to the browser. Nothing is ever *executed*: `NSWorkspace.open` on a script or binary
/// would run it, so paths never take that route.
public enum LinkOpener {
    public enum Plan: Equatable, Sendable {
        case browse(URL)
        case editFile(String)
        case revealDirectory(String)
        case ignore
    }

    public static func plan(for match: LinkDetector.Match, isDirectory: (String) -> Bool = { path in
        var dir: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &dir) && dir.boolValue
    }) -> Plan {
        switch match.kind {
        case let .url(url):
            guard let scheme = url.scheme?.lowercased(), LinkDetector.allowedSchemes.contains(scheme) else { return .ignore }
            if scheme == "file" {
                let path = url.path
                return isDirectory(path) ? .revealDirectory(path) : .editFile(path)
            }
            return .browse(url)
        case let .path(path, _):
            return isDirectory(path) ? .revealDirectory(path) : .editFile(path)
        }
    }

    @MainActor
    public static func perform(_ plan: Plan) {
        switch plan {
        case let .browse(url):
            NSWorkspace.shared.open(url)
        case let .editFile(path):
            let url = URL(fileURLWithPath: path)
            if let editor = NSWorkspace.shared.urlForApplication(toOpen: UTType.plainText) {
                NSWorkspace.shared.open([url], withApplicationAt: editor, configuration: NSWorkspace.OpenConfiguration())
            } else {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }
        case let .revealDirectory(path):
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
        case .ignore:
            break
        }
    }
}
