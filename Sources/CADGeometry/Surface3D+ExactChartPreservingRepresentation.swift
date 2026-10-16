import CADCore

extension Surface3D {
    /// Returns an exact representation that preserves this surface's
    /// parameter chart, or `nil` when no such representation is available.
    package func exactChartPreservingRepresentation(
        tolerance: ModelingTolerance
    ) throws -> Surface3D? {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try exactChartPreservingRepresentation(tolerance: tolerance, using: &execution)
    }

    package func exactChartPreservingRepresentation(tolerance: ModelingTolerance,
        using execution: inout OriginalQueryExecution) throws -> Surface3D? {
        try execution.checkpoint()
        try execution.consumeWork(1)
        switch self {
        case .plane, .cylinder, .analytic, .bSpline:
            return self
        case let .procedural(surface):
            return try surface.exactChartPreservingSurface(
                tolerance: tolerance, using: &execution
            )
        }
    }
}
