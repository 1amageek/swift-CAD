import CADCore

/// An oriented wire edge use; face-local pcurves remain owned by face coedges.
public struct ShapeEdgeUse: Hashable, Sendable {
    public let edgeID: EdgeID
    public let orientation: Orientation

    public init(edgeID: EdgeID, orientation: Orientation = .forward) {
        self.edgeID = edgeID
        self.orientation = orientation
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(edgeID)
        hasher.combine(orientation.rawValue)
    }
}
