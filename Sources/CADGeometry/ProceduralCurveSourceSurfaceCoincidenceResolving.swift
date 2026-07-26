import CADCore

protocol ProceduralCurveSourceSurfaceCoincidenceResolving: Sendable {
    func isSourceSurface(
        _ surface: Surface3D,
        of curve: Curve3D,
        tolerance: ModelingTolerance
    ) throws -> Bool
}
