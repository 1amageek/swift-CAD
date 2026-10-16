import CADCore
import CADGeometry

/// The original coedge lift in the unchanged directed model-edge chart.
struct ExchangeHostedCurveConversionSource: GeometryCurveConversionSource {
    let original: NativeCurveConversionSource
    let start: Double
    let end: Double
    let reversed: Bool
    let originalStart: ExactRationalCoefficient
    let originalSpan: ExactRationalCoefficient
    let derivativeGain: OutwardScalarInterval
    let originalBudget: OriginalQueryBudget
    let originalLimits: OriginalQueryExecutionLimits
    private let originalContext: OriginalQueryFailureContext
    private let originalContributions: [OriginalQueryContributionHandle]

    init(surface: Surface3D, parameterCurve: SurfaceParameterCurve, start: Double, end: Double,
        reversed: Bool, tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws {
        guard start.isFinite, end.isFinite, start != end else {
            throw GeometryConversionError.invalidInput("Hosted chart requires distinct finite original edge labels.")
        }
        originalStart = try .originalDouble(start, usage: &execution)
        originalSpan = try ExactRationalCoefficient.originalDouble(end, usage: &execution)
            .subtracting(originalStart, usage: &execution)
        let numerator = try ExactRationalCoefficient.originalDouble(reversed ? -1 : 1, usage: &execution)
        derivativeGain = try numerator.divided(by: originalSpan, usage: &execution).outwardInterval(usage: &execution)
        self.start = start; self.end = end; self.reversed = reversed; originalBudget = execution.budget; originalLimits = execution.limits
        original = try NativeCurveConversionSource(.surfaceLift(SurfaceLiftCurve3D(surface: surface,
            parameterCurve: parameterCurve)), tolerance: tolerance, using: &execution)
        originalContributions = try execution.retainActiveContributionHandles()
        originalContext = execution.context
    }

    func validate(over parameters: ScalarInterval, tolerance: ModelingTolerance) throws {
        var execution = try OriginalQueryExecution(budget: originalBudget, limits: originalLimits,
            context: originalContext, contributions: originalContributions)
        try validate(over: parameters, tolerance: tolerance, using: &execution)
    }
    func validate(over parameters: ScalarInterval, tolerance: ModelingTolerance,
        using execution: inout OriginalQueryExecution) throws {
        try withOriginalExecution(using: &execution) { execution in
            let chart = try normalized(parameters, using: &execution)
            try original.validate(over: chart, tolerance: tolerance, using: &execution)
        }
    }
    func pointAndDerivative(at parameter: Double, tolerance: ModelingTolerance) throws -> (point: Point3D, derivative: Vector3D) {
        // Numeric proposals are representatives of the retained bounded source, never acceptance witnesses.
        var execution = try OriginalQueryExecution(budget: originalBudget, limits: originalLimits,
            context: originalContext, contributions: originalContributions)
        return try pointAndDerivative(at: parameter, tolerance: tolerance, using: &execution)
    }
    func pointAndDerivative(at parameter: Double, tolerance: ModelingTolerance,
        using execution: inout OriginalQueryExecution) throws -> (point: Point3D, derivative: Vector3D) {
        return try withOriginalExecution(using: &execution) { execution in
            let value = try enclosure(over: ScalarInterval(lower: parameter, upper: parameter),
                tolerance: tolerance, using: &execution)
            try execution.consumeWork(6)
            return (Point3D(x: value.position.x.midpoint, y: value.position.y.midpoint, z: value.position.z.midpoint),
                Vector3D(x: value.firstDerivative.x.midpoint, y: value.firstDerivative.y.midpoint, z: value.firstDerivative.z.midpoint))
        }
    }
    func enclosure(over parameters: ScalarInterval, tolerance: ModelingTolerance) throws -> CurveDifferentialEnclosure {
        var execution = try OriginalQueryExecution(budget: originalBudget, limits: originalLimits,
            context: originalContext, contributions: originalContributions)
        return try enclosure(over: parameters, tolerance: tolerance, using: &execution)
    }
    func enclosure(over parameters: ScalarInterval, tolerance: ModelingTolerance,
        using execution: inout OriginalQueryExecution) throws -> CurveDifferentialEnclosure {
        return try withOriginalExecution(using: &execution) { execution in
            let chart = try normalized(parameters, using: &execution)
            let value = try original.enclosure(over: chart, tolerance: tolerance, using: &execution)
            try execution.consumeWork(6)
            return .init(position: value.position,
                firstDerivative: try multiply(value.firstDerivative, by: derivativeGain),
                secondDerivative: try multiply(value.secondDerivative, by: derivativeGain * derivativeGain))
        }
    }
    private func withOriginalExecution<Result>(using execution: inout OriginalQueryExecution,
        _ body: (inout OriginalQueryExecution) throws -> Result) throws -> Result {
        guard execution.budget === originalBudget, execution.limits == originalLimits else {
            throw GeometryConversionError.invalidInput("Hosted chart requires its original invocation owner and policy.")
        }
        return try execution.withContributionScopes(originalContributions) { execution in
            try execution.checkpoint()
            let result = try body(&execution)
            try execution.checkpoint()
            return result
        }
    }
    private func normalized(_ parameters: ScalarInterval, using execution: inout OriginalQueryExecution) throws -> ScalarInterval {
        guard parameters.lower >= min(start, end), parameters.upper <= max(start, end) else {
            throw GeometryConversionError.invalidInput("Hosted query is outside its original directed edge selection.")
        }
        func fraction(_ parameter: Double, using execution: inout OriginalQueryExecution) throws -> ExactRationalCoefficient {
            var q = try ExactRationalCoefficient.originalDouble(parameter, usage: &execution)
                .subtracting(originalStart, usage: &execution).divided(by: originalSpan, usage: &execution)
            if reversed { q = try ExactRationalCoefficient.one.subtracting(q, usage: &execution) }
            guard q.canonicalSign >= 0,
                try q.subtracting(.one, usage: &execution).canonicalSign <= 0 else {
                throw GeometryConversionError.invalidInput("Original hosted station is outside its normalized source chart.")
            }
            return q
        }
        let a = try fraction(parameters.lower, using: &execution), b = try fraction(parameters.upper, using: &execution)
        let ascending = try b.subtracting(a, usage: &execution).canonicalSign >= 0
        let lower = try (ascending ? a : b).outwardInterval(usage: &execution)
        let upper = try (ascending ? b : a).outwardInterval(usage: &execution)
        // Exact rational membership above proves that outward overshoot is rounding only.
        return try .init(lower: max(0, lower.lower), upper: min(1, upper.upper))
    }
    private func multiply(_ value: CoordinateEnclosure3D, by scale: OutwardScalarInterval) throws -> CoordinateEnclosure3D {
        func component(_ interval: ScalarInterval) throws -> ScalarInterval {
            let result = OutwardScalarInterval(lower: interval.lower, upper: interval.upper) * scale
            return try .init(lower: result.lower, upper: result.upper)
        }
        return try .init(x: component(value.x), y: component(value.y), z: component(value.z))
    }
}
