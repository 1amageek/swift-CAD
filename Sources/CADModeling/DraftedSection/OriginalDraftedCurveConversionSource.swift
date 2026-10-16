import CADCore
import CADGeometry

/// Conversion adapter for the persistent original draft, without duplicated ruling math.
package struct OriginalDraftedCurveConversionSource: GeometryCurveConversionSource {
    package let source: OriginalDraftedCurve3D
    private let budget: OriginalQueryBudget
    private let limits: OriginalQueryExecutionLimits
    private let contributions: [OriginalQueryContributionHandle]

    package init(source: OriginalDraftedCurve3D, using execution: inout OriginalQueryExecution) throws {
        self.source = source; budget = execution.budget; limits = execution.effectiveLimits; contributions = try execution.retainActiveContributionHandles()
    }
    package func validate(over parameters: ScalarInterval, tolerance: ModelingTolerance) throws {
        var execution = try OriginalQueryExecution(budget: budget, limits: limits, contributions: contributions)
        try validate(over: parameters, tolerance: tolerance, using: &execution)
    }
    package func validate(over parameters: ScalarInterval, tolerance: ModelingTolerance,
        using execution: inout OriginalQueryExecution) throws {
        try execution.consumeWork(1)
        try source.validate(tolerance: tolerance, using: &execution)
        guard parameters.lower >= 0, parameters.upper <= 1 else {
            throw GeometryConversionError.invalidInput("Original drafted candidate must use its retained normalized chart.")
        }
    }
    package func enclosure(over parameters: ScalarInterval, tolerance: ModelingTolerance) throws -> CurveDifferentialEnclosure {
        var execution = try OriginalQueryExecution(budget: budget, limits: limits, contributions: contributions)
        return try enclosure(over: parameters, tolerance: tolerance, using: &execution)
    }
    package func enclosure(over parameters: ScalarInterval, tolerance: ModelingTolerance,
        using execution: inout OriginalQueryExecution) throws -> CurveDifferentialEnclosure {
        try validate(over: parameters, tolerance: tolerance, using: &execution)
        let q = try source.intervalTaylorJet(over: parameters, throughOrder: 2,
            tolerance: tolerance, maximumSpanCount: execution.effectiveLimits.maximumSpans,
            maximumSubdivisionDepth: execution.effectiveLimits.maximumSubdivisionDepth,
            remainingSourceDepth: execution.effectiveLimits.remainingSourceDepth, using: &execution)
        func field(_ order: Int) throws -> CoordinateEnclosure3D {
            let scale = OutwardScalarInterval.exact(order == 2 ? 2 : 1)
            let x = try q.x.coefficient(order, 0) * scale
            let y = try q.y.coefficient(order, 0) * scale
            let z = try q.z.coefficient(order, 0) * scale
            return try .init(x: .init(lower: x.lower, upper: x.upper),
                y: .init(lower: y.lower, upper: y.upper), z: .init(lower: z.lower, upper: z.upper))
        }
        return try .init(position: field(0), firstDerivative: field(1), secondDerivative: field(2))
    }
    package func pointAndDerivative(at parameter: Double, tolerance: ModelingTolerance)
        throws -> (point: Point3D, derivative: Vector3D) {
        var execution = try OriginalQueryExecution(budget: budget, limits: limits, contributions: contributions)
        return try pointAndDerivative(at: parameter, tolerance: tolerance, using: &execution)
    }
    package func pointAndDerivative(at parameter: Double, tolerance: ModelingTolerance,
        using execution: inout OriginalQueryExecution) throws -> (point: Point3D, derivative: Vector3D) {
        let e = try enclosure(over: .init(lower: parameter, upper: parameter),
            tolerance: tolerance, using: &execution)
        return (.init(x: e.position.x.midpoint, y: e.position.y.midpoint, z: e.position.z.midpoint),
            .init(x: e.firstDerivative.x.midpoint, y: e.firstDerivative.y.midpoint, z: e.firstDerivative.z.midpoint))
    }
}
