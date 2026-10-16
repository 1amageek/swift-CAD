import CADCore

public protocol SurfaceSilhouetteTrimPartitionProviding: Sendable {
    func partition(curve: OriginalSurfaceSilhouetteCurve,
        boundary: OriginalSurfaceSilhouetteBoundary,
        using execution: inout OriginalQueryExecution) throws -> SurfaceSilhouetteTrimPartition
}
