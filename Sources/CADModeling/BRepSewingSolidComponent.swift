/// Stable shell ownership for one material component before topology IDs exist.
public struct BRepSewingSolidComponent: Equatable, Sendable {
    public let outerShellStableID: String
    public let voidShellStableIDs: [String]

    public init(
        outerShellStableID: String,
        voidShellStableIDs: [String] = []
    ) {
        self.outerShellStableID = outerShellStableID
        self.voidShellStableIDs = voidShellStableIDs
    }

    public var shellStableIDs: [String] {
        [outerShellStableID] + voidShellStableIDs
    }
}
