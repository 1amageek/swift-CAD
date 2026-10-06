import CADCore

/// Produces screen coincidence coverage using original source parameters and one live allowance.
public protocol SurfaceSilhouetteProjectedContactProducing: Sendable {
    func partition(edge: Curve3D, spanIndex: Int, over: ScalarInterval,
        silhouette: OriginalSurfaceSilhouetteTrimmedCurve, frame: OrthographicProjectionFrame,
        usage: inout SurfaceSilhouetteUsage) throws -> SurfaceSilhouetteProjectedPartition
}
