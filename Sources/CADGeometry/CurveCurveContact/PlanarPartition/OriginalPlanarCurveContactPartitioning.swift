import CADCore

/// Complete original planar degree-one/two/three contact and overlap partition.
public protocol OriginalPlanarCurveContactPartitioning: Sendable {
    func partition(first: BSplineCurve3D, firstParameters: ScalarInterval,
        second: BSplineCurve3D, secondParameters: ScalarInterval, on plane: Plane3D,
        allowance: inout OriginalCurveContactAllowance, tolerance: ModelingTolerance)
        throws -> OriginalPlanarCurveContactPartition

    func mergeCuts(source: BSplineCurve3D, parameters: ScalarInterval,
        endpoints: [OriginalCurveRootEndpoint], allowance: inout OriginalCurveContactAllowance,
        tolerance: ModelingTolerance) throws -> OriginalPlanarCurveMergedPartition

    func orderOutgoingGerms(_ germs: [OriginalPlanarCurveOutgoingGerm], on plane: Plane3D,
        retaining partitions: [OriginalPlanarCurveContactPartition],
        allowance: inout OriginalCurveContactAllowance, tolerance: ModelingTolerance)
        throws -> OriginalPlanarCurveGermOrder

    func monotoneOverlaps(retaining partition: OriginalPlanarCurveContactPartition,
        firstMerged: OriginalPlanarCurveMergedPartition, secondMerged: OriginalPlanarCurveMergedPartition,
        allowance: inout OriginalCurveContactAllowance, tolerance: ModelingTolerance)
        throws -> [OriginalPlanarCurveMonotoneOverlap]
    func sideWinding(of span: OriginalCurveRootSpan3D, forward: Bool,
        contours: [[OriginalPlanarDirectedCurve]], on plane: Plane3D,
        retaining partitions: [OriginalPlanarCurveContactPartition],
        allowance: inout OriginalCurveContactAllowance, tolerance: ModelingTolerance)
        throws -> OriginalPlanarCurveSideWinding
    func prepareWinding(contours: [[OriginalPlanarDirectedCurve]], on plane: Plane3D,
        allowance: inout OriginalCurveContactAllowance, tolerance: ModelingTolerance)
        throws -> OriginalPlanarCurveWindingSource

    func sideWinding(of span: OriginalCurveRootSpan3D, forward: Bool,
        retainingSource: OriginalPlanarCurveWindingSource,
        retaining partitions: [OriginalPlanarCurveContactPartition],
        allowance: inout OriginalCurveContactAllowance, tolerance: ModelingTolerance)
        throws -> OriginalPlanarCurveSideWinding
}
