import Foundation

/// A folder the user works in. Sessions are grouped under projects in the sidebar.
public struct Project: Hashable, Codable, Sendable, Identifiable {
    public let id: ProjectID
    public var name: String
    public var rootDirectory: URL
    /// Sidebar ordering; lower comes first.
    public var order: Int

    public init(id: ProjectID = ProjectID(), name: String, rootDirectory: URL, order: Int = 0) {
        self.id = id
        self.name = name
        self.rootDirectory = rootDirectory
        self.order = order
    }
}
