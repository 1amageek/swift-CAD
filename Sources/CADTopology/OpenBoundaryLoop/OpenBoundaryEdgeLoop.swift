import CADCore

public struct OpenBoundaryEdgeLoop: Equatable, Sendable {
    public struct Traversal: Equatable, Sendable {
        public let edgeID: EdgeID
        public let followsStoredDirection: Bool

        init(edgeID: EdgeID, followsStoredDirection: Bool) {
            self.edgeID = edgeID
            self.followsStoredDirection = followsStoredDirection
        }
    }

    public let traversals: [Traversal]

    init(traversals: [Traversal]) {
        self.traversals = traversals
    }
}
