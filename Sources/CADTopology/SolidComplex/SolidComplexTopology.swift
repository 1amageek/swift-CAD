import CADCore

/// Face-connected solid cells with explicit, independently owned interface uses.
public struct SolidComplexTopology: Equatable, Sendable {
    public let bodyIDs: [BodyID]
    public let interfaces: [SolidInterface]

    public init(bodyIDs: [BodyID], interfaces: [SolidInterface] = []) {
        self.bodyIDs = bodyIDs
        self.interfaces = interfaces
    }
}
