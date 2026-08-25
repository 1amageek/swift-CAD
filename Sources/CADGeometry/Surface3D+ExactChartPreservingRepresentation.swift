import CADCore

extension Surface3D {
    /// Returns an exact representation that preserves this surface's
    /// parameter chart, or `nil` when no such representation is available.
    package func exactChartPreservingRepresentation(
        tolerance: ModelingTolerance
    ) throws -> Surface3D? {
        switch self {
        case .plane, .cylinder, .analytic, .bSpline:
            return self
        case let .procedural(surface):
            return try surface.exactChartPreservingSurface(
                tolerance: tolerance
            )
        }
    }
}
