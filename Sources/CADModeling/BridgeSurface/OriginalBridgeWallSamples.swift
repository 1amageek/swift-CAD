import CADCore
import CADGeometry

/// Supplies candidates from retained original wall bounds, not projection samples.
package struct OriginalBridgeWallSamples {
    private let chart: SurfaceAreaParameterChartEncloser
    private let surface: PreparedSurfaceDifferentialEncloser
    private let tolerance: ModelingTolerance
    private let sourceDepth: Int

    package struct Candidate {
        package let position: Point3D
        package let normal: Vector3D
        package let tangentU: Vector3D
        package let tangentV: Vector3D
        package let secondDerivativeUU: Vector3D
        package let secondDerivativeUV: Vector3D
        package let secondDerivativeVV: Vector3D
    }

    package init(surface: Surface3D, boundary: SurfaceParameterCurve,
        tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws {
        self.tolerance = tolerance
        sourceDepth = min(16, execution.effectiveLimits.remainingSourceDepth)
        self.surface = try PreparedSurfaceDifferentialEncloser(surface: surface, tolerance: tolerance,
            remainingSourceDepth: sourceDepth, maximumSubdivisionDepth: min(20, execution.effectiveLimits.maximumSubdivisionDepth),
            maximumAlgebraicDepth: execution.effectiveLimits.maximumValueDepth, using: &execution)
        chart = try SurfaceAreaParameterChartEncloser(curve: boundary, on: surface,
            tolerance: tolerance, maximumSubdivisionDepth: min(20, execution.effectiveLimits.maximumSubdivisionDepth),
            remainingSourceDepth: sourceDepth, maximumAlgebraicDepth: execution.effectiveLimits.maximumValueDepth,
            using: &execution)
    }

    package func candidate(atFraction fraction: Double, using execution: inout OriginalQueryExecution) throws -> Candidate {
        try execution.consumeWork(1)
        let values = try chart.intervalProof(over: .init(lower: fraction, upper: fraction),
            tolerance: tolerance, using: &execution).values
        let field = try surface.enclosure(over: .init(
            u: .init(lower: values.u.lower, upper: values.u.upper),
            v: .init(lower: values.v.lower, upper: values.v.upper)),
            tolerance: tolerance, maximumSpanCount: min(4096, execution.effectiveLimits.maximumSpans),
            maximumSubdivisionDepth: min(20, execution.effectiveLimits.maximumSubdivisionDepth), remainingSourceDepth: sourceDepth,
            using: &execution)
        func middle(_ value: ScalarInterval) throws -> Double {
            try execution.consumeWork(1)
            let candidate = value.lower * 0.5 + value.upper * 0.5
            guard candidate.isFinite else {
                throw GeometryConversionError.resourceLimitExceeded("Original bridge candidate exceeded finite arithmetic.")
            }
            return candidate
        }
        func vector(_ value: CoordinateEnclosure3D) throws -> Vector3D {
            try Vector3D(x: middle(value.x), y: middle(value.y), z: middle(value.z))
        }
        let u = try vector(field.tangentU), v = try vector(field.tangentV)
        let cross = u.cross(v)
        let normal = try OriginalDraftDirectionInputs.normalized(cross)
        return try Candidate(position: Point3D(x: middle(field.position.x),
            y: middle(field.position.y), z: middle(field.position.z)), normal: normal,
            tangentU: u, tangentV: v, secondDerivativeUU: vector(field.secondDerivativeUU),
            secondDerivativeUV: vector(field.secondDerivativeUV), secondDerivativeVV: vector(field.secondDerivativeVV))
    }
}
