import CADCore

/// Exact cyclic outgoing sectors; each group contains coincident directed germs.
public struct OriginalPlanarCurveGermOrder: Sendable {
    public let plane: Plane3D
    public let germs: [OriginalPlanarCurveOutgoingGerm]
    public let sectors: [[Int]]

    package init(plane: Plane3D, germs: [OriginalPlanarCurveOutgoingGerm], sectors: [[Int]]) {
        self.plane = plane; self.germs = germs; self.sectors = sectors
    }
}
