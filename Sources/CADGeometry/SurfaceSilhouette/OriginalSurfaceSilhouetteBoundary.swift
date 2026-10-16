import CADCore

/// Retains a source face-loop pcurve with the same extraction/query work owner.
public struct OriginalSurfaceSilhouetteBoundary: Sendable {
    public let curve: SurfaceParameterCurve
    public let surface: Surface3D
    public let tolerance: ModelingTolerance
    private let queryContext: SurfaceSilhouetteQueryContext
    private let prepared: SurfaceAreaParameterChartEncloser

    public init(curve: SurfaceParameterCurve, on surface: Surface3D,
                maximumControlPointCount: Int, maximumBoundaryCurveCount: Int,
                tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws {
        queryContext = try .init(retaining: &execution)
        self.curve = curve; self.surface = surface; self.tolerance = tolerance
        try GeometryStructuralComparisonWork.charge(parameterCurve: curve, using: &execution)
        try GeometryStructuralComparisonWork.charge(surface: surface, using: &execution)
        // FIXME(INCOMPLETE_IMPLEMENTATION): The original chart provider used by
        // production drawing clipping still lacks projected/spherical and some
        // unsplit source chart authorities. Its typed refusal propagates; a full
        // D1 clipping result requires those exact lower charts and complete
        // critical/coincident boundary-event certification, not a sampled chart.
        prepared = try SurfaceAreaParameterChartEncloser(curve: curve, on: surface,
            maximumControlPointCount: maximumControlPointCount,
            maximumBoundaryCurveCount: maximumBoundaryCurveCount, tolerance: tolerance,
            maximumSubdivisionDepth: execution.effectiveLimits.maximumSubdivisionDepth, remainingSourceDepth: execution.effectiveLimits.remainingSourceDepth,
            maximumAlgebraicDepth: execution.effectiveLimits.maximumCoefficientDepth,
            using: &execution)
        try RationalAlgebraStorage.retain(1, of: Self.self, usage: &execution)
    }

    public func enclosure(overFraction fraction: ScalarInterval,
                          using execution: inout OriginalQueryExecution) throws -> SurfaceSilhouetteBoundaryEnclosure {
        return try queryContext.withExecution(using: &execution) { execution in
        let original = try prepared.intervalProof(over: fraction, tolerance: tolerance,
            using: &execution)
        let values = original.values
        func interval(_ value: OutwardScalarInterval) throws -> ScalarInterval {
            guard value.isFinite else {
                throw KernelError(phase: .geometry, code: .intersectionFailure, tolerance: tolerance,
                    message: "Original silhouette boundary chart has nonfinite value or tangent bounds.")
            }
            return try ScalarInterval(lower: value.lower, upper: value.upper)
        }
        let smooth: Bool
        switch original { case .smooth: smooth = true; case .valueOnly: smooth = false }
        try RationalAlgebraStorage.retain(1, of: SurfaceSilhouetteBoundaryEnclosure.self, usage: &execution)
        return try SurfaceSilhouetteBoundaryEnclosure(
            position: CoordinateEnclosure2D(x: interval(values.u), y: interval(values.v)),
            tangent: CoordinateEnclosure2D(x: interval(values.tangentU), y: interval(values.tangentV)),
            hasSmoothDerivatives: smooth)
    
        }
    }
}
