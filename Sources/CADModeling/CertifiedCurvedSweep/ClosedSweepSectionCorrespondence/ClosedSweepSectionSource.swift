import CADCore
import CADGeometry

/// Original directed section law composed with a closed interval endpoint action.
package struct ClosedSweepSectionSource: GeometryCurveConversionSource {
    private let original: OriginalCurveConstructionSource
    private let action: ClosedSweepIntervalFrameAction
    private let budget: OriginalQueryBudget
    private let limits: OriginalQueryExecutionLimits
    private let contributions: [OriginalQueryContributionHandle]

    package init(chart: OriginalCurveSpanParameterChart, domain: ScalarInterval,
        action: ClosedSweepIntervalFrameAction, tolerance: ModelingTolerance,
        using execution: inout OriginalQueryExecution) throws {
        original = try OriginalCurveConstructionSource(chart: chart, domain: domain,
            tolerance: tolerance, using: &execution)
        self.action = action; budget = execution.budget; limits = execution.effectiveLimits; contributions = try execution.retainActiveContributionHandles()
    }

    package func validate(over parameters: ScalarInterval, tolerance: ModelingTolerance) throws {
        var execution = try OriginalQueryExecution(budget: budget, limits: limits, contributions: contributions)
        try validate(over: parameters, tolerance: tolerance, using: &execution)
    }
    package func validate(over parameters: ScalarInterval, tolerance: ModelingTolerance,
        using execution: inout OriginalQueryExecution) throws {
        try original.validate(over: parameters, tolerance: tolerance, using: &execution)
    }
    package func enclosure(over parameters: ScalarInterval, tolerance: ModelingTolerance) throws -> CurveDifferentialEnclosure {
        var execution = try OriginalQueryExecution(budget: budget, limits: limits, contributions: contributions)
        return try enclosure(over: parameters, tolerance: tolerance, using: &execution)
    }
    package func enclosure(over parameters: ScalarInterval, tolerance: ModelingTolerance,
        using execution: inout OriginalQueryExecution) throws -> CurveDifferentialEnclosure {
        let raw = try original.enclosure(over: parameters, tolerance: tolerance, using: &execution)
        return CurveDifferentialEnclosure(
            position: try action.apply(raw.position, isPosition: true, using: &execution),
            firstDerivative: try action.apply(raw.firstDerivative, isPosition: false, using: &execution),
            secondDerivative: try action.apply(raw.secondDerivative, isPosition: false, using: &execution))
    }
    package func pointAndDerivative(at parameter: Double, tolerance: ModelingTolerance) throws -> (point: Point3D, derivative: Vector3D) {
        var execution = try OriginalQueryExecution(budget: budget, limits: limits, contributions: contributions)
        return try pointAndDerivative(at: parameter, tolerance: tolerance, using: &execution)
    }
    package func pointAndDerivative(at parameter: Double, tolerance: ModelingTolerance,
        using execution: inout OriginalQueryExecution) throws -> (point: Point3D, derivative: Vector3D) {
        let raw = try enclosure(over: ScalarInterval(lower: parameter, upper: parameter), tolerance: tolerance, using: &execution)
        guard raw.position.x.width == 0, raw.position.y.width == 0, raw.position.z.width == 0,
              raw.firstDerivative.x.width == 0, raw.firstDerivative.y.width == 0, raw.firstDerivative.z.width == 0 else {
            throw GeometryConversionError.resourceLimitExceeded("An interval endpoint action cannot publish a rounded exact section point.")
        }
        return (Point3D(x: raw.position.x.lower, y: raw.position.y.lower, z: raw.position.z.lower),
            Vector3D(x: raw.firstDerivative.x.lower, y: raw.firstDerivative.y.lower, z: raw.firstDerivative.z.lower))
    }
}
