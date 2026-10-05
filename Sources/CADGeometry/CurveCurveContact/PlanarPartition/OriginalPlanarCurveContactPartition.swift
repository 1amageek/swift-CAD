import CADCore

/// Immutable complete exact incidence partition, distinct from tolerance contact.
public struct OriginalPlanarCurveContactPartition: Sendable {
    public let first: BSplineCurve3D
    public let firstParameters: ScalarInterval
    public let second: BSplineCurve3D
    public let secondParameters: ScalarInterval
    public let plane: Plane3D
    public let tolerance: ModelingTolerance
    public let events: [OriginalPlanarCurveContactEvent]
    public let overlaps: [OriginalPlanarCurveContactOverlap]
    public let firstCuts: [OriginalPlanarCurveContactCut]
    public let secondCuts: [OriginalPlanarCurveContactCut]
    public let firstSegments: [OriginalPlanarCurveContactSegment]
    public let secondSegments: [OriginalPlanarCurveContactSegment]

    package init(first: BSplineCurve3D, firstParameters: ScalarInterval,
        second: BSplineCurve3D, secondParameters: ScalarInterval, plane: Plane3D,
        tolerance: ModelingTolerance, events: [OriginalPlanarCurveContactEvent],
        overlaps: [OriginalPlanarCurveContactOverlap],
        firstCuts: [OriginalPlanarCurveContactCut], secondCuts: [OriginalPlanarCurveContactCut],
        firstSegments: [OriginalPlanarCurveContactSegment], secondSegments: [OriginalPlanarCurveContactSegment]) {
        self.first = first; self.firstParameters = firstParameters
        self.second = second; self.secondParameters = secondParameters
        self.plane = plane; self.tolerance = tolerance
        self.events = events; self.overlaps = overlaps
        self.firstCuts = firstCuts; self.secondCuts = secondCuts
        self.firstSegments = firstSegments; self.secondSegments = secondSegments
    }
}
