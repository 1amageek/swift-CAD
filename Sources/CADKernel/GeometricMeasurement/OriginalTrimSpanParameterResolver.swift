import CADCore
import CADGeometry
import CADTopology

/// Retains exact native trim ratios and scalar stations in the original chart.
enum OriginalTrimSpanParameterResolver {
    static func curve(_ source: Curve3D, from firstParameter: Double, to lastParameter: Double,
        in domain: ParameterDomain, tolerance: ModelingTolerance,
        using execution: inout OriginalQueryExecution) throws -> Curve3D {
        let first = try coefficient(at: firstParameter, in: domain, tolerance: tolerance, using: &execution)
        let last = try coefficient(at: lastParameter, in: domain, tolerance: tolerance, using: &execution)
        let chart = OriginalCurveConstructionParameterSource(source: source,
            startParameter: 0, endParameter: 1, law: .affine,
            firstFraction: first, lastFraction: last)
        return .originalConstructionChart(try OriginalCurveConstructionChartImage(parameterSource: chart,
            tolerance: tolerance, maximumSpanCount: 262_144,
            maximumSubdivisionDepth: execution.effectiveLimits.maximumSubdivisionDepth,
            remainingSourceDepth: execution.effectiveLimits.remainingSourceDepth, maximumAlgebraicDepth: min(execution.effectiveLimits.maximumValueDepth, execution.effectiveLimits.maximumCoefficientDepth), using: &execution))
    }

    private static func coefficient(at nativeParameter: Double, in domain: ParameterDomain,
        tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws -> ExactRationalCoefficient {
        guard case .closed(let lower, let upper) = domain, lower < upper,
            nativeParameter.isFinite, nativeParameter >= lower, nativeParameter <= upper else {
            throw KernelError(phase: .geometry, code: .invalidInput, tolerance: tolerance,
                message: "Original trim station is outside its bounded native chart.")
        }
        let numerator = try ExactRationalCoefficient.originalDouble(nativeParameter, usage: &execution)
            .subtracting(.originalDouble(lower, usage: &execution), usage: &execution)
        let denominator = try ExactRationalCoefficient.originalDouble(upper, usage: &execution)
            .subtracting(.originalDouble(lower, usage: &execution), usage: &execution)
        return try numerator.divided(by: denominator, usage: &execution)
    }

    static func fraction(at nativeParameter: Double, in domain: ParameterDomain,
        tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws -> Double {
        let fraction = try coefficient(at: nativeParameter, in: domain, tolerance: tolerance, using: &execution)
        let bounds = try fraction.outwardInterval(usage: &execution)
        if bounds.isFinite {
            if bounds.lower == bounds.upper { return bounds.lower }
            let first = try ExactRationalCoefficient.originalDouble(bounds.lower, usage: &execution)
            if try fraction.subtracting(first, usage: &execution).isZero { return bounds.lower }
            let last = try ExactRationalCoefficient.originalDouble(bounds.upper, usage: &execution)
            if try fraction.subtracting(last, usage: &execution).isZero { return bounds.upper }
        }
        // FIXME(INCOMPLETE_IMPLEMENTATION): The public trim-knot scalar route
        // still needs a retained constant-station carrier when this exact
        // normalized ratio is not representable. Its original singleton source
        // must not be replaced by a rounded quotient or an epsilon-wide span.
        throw KernelError(phase: .geometry, code: .unsupportedCapability, tolerance: tolerance,
            message: "Original trim station requires a retained nonrepresentable parameter chart.")
    }
}
