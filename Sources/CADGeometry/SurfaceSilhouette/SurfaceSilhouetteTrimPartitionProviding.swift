import CADCore

public protocol SurfaceSilhouetteTrimPartitionProviding: Sendable {
    func partition(curve: OriginalSurfaceSilhouetteCurve,
        boundary: OriginalSurfaceSilhouetteBoundary,
        usage: inout SurfaceSilhouetteUsage) throws -> SurfaceSilhouetteTrimPartition
}
