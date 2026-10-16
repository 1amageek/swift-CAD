import CADCore

public protocol RuledBSplineSurfaceBuilding: Sendable {
    func build(
        startBoundary: BSplineCurve3D,
        endBoundary: BSplineCurve3D,
        tolerance: ModelingTolerance
    ) throws -> BSplineSurface3D
    func build(startBoundary: BSplineCurve3D, endBoundary: BSplineCurve3D,
        tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws -> BSplineSurface3D
}
