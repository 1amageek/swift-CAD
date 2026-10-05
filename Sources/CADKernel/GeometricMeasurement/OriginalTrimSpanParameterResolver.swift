import CADCore
import CADGeometry
import CADTopology

/// Retains exact native trim ratios and scalar stations in the original chart.
enum OriginalTrimSpanParameterResolver {
    static func curve(_ source: Curve3D, from firstParameter: Double, to lastParameter: Double,
        in domain: ParameterDomain, tolerance: ModelingTolerance,
        budget: BRepDistanceProofBudget) throws -> Curve3D {
        let first = try coefficient(at: firstParameter, in: domain, tolerance: tolerance, budget: budget)
        let last = try coefficient(at: lastParameter, in: domain, tolerance: tolerance, budget: budget)
        var usage = OriginalSourceProofAdmission(consumeWork: { try budget.charge(depth: $0) },
            consumeStorage: budget.storageAdmission, maximumAlgebraicDepth: budget.maximumAlgebraicDepth)
        let chart = OriginalCurveConstructionParameterSource(source: source,
            startParameter: 0, endParameter: 1, law: .affine,
            firstFraction: first, lastFraction: last)
        return .originalConstructionChart(try OriginalCurveConstructionChartImage(parameterSource: chart,
            tolerance: tolerance, maximumSpanCount: 262_144,
            maximumSubdivisionDepth: budget.maximumDepth,
            remainingSourceDepth: budget.maximumSourceDepth, storageByteStride: MemoryLayout<UInt32>.stride,
            usage: &usage, maximumAlgebraicDepth: budget.maximumAlgebraicDepth))
    }

    private static func coefficient(at nativeParameter: Double, in domain: ParameterDomain,
        tolerance: ModelingTolerance, budget: BRepDistanceProofBudget) throws -> ExactRationalCoefficient {
        guard case .closed(let lower, let upper) = domain, lower < upper,
            nativeParameter.isFinite, nativeParameter >= lower, nativeParameter <= upper else {
            throw KernelError(phase: .geometry, code: .invalidInput, tolerance: tolerance,
                message: "Original trim station is outside its bounded native chart.")
        }
        var usage = OriginalSourceProofAdmission(consumeWork: { try budget.charge(depth: $0) },
            consumeStorage: budget.storageAdmission, maximumAlgebraicDepth: budget.maximumAlgebraicDepth)
        let numerator = try ExactRationalCoefficient.originalDouble(nativeParameter, usage: &usage)
            .subtracting(.originalDouble(lower, usage: &usage), usage: &usage)
        let denominator = try ExactRationalCoefficient.originalDouble(upper, usage: &usage)
            .subtracting(.originalDouble(lower, usage: &usage), usage: &usage)
        return try numerator.divided(by: denominator, usage: &usage)
    }

    static func fraction(at nativeParameter: Double, in domain: ParameterDomain,
        tolerance: ModelingTolerance, budget: BRepDistanceProofBudget) throws -> Double {
        let fraction = try coefficient(at: nativeParameter, in: domain, tolerance: tolerance, budget: budget)
        var usage = OriginalSourceProofAdmission(consumeWork: { try budget.charge(depth: $0) },
            consumeStorage: budget.storageAdmission, maximumAlgebraicDepth: budget.maximumAlgebraicDepth)
        let bounds = try fraction.outwardInterval(usage: &usage)
        if bounds.isFinite {
            if bounds.lower == bounds.upper { return bounds.lower }
            let first = try ExactRationalCoefficient.originalDouble(bounds.lower, usage: &usage)
            if try fraction.subtracting(first, usage: &usage).isZero { return bounds.lower }
            let last = try ExactRationalCoefficient.originalDouble(bounds.upper, usage: &usage)
            if try fraction.subtracting(last, usage: &usage).isZero { return bounds.upper }
        }
        // FIXME(INCOMPLETE_IMPLEMENTATION): The public trim-knot scalar route
        // still needs a retained constant-station carrier when this exact
        // normalized ratio is not representable. Its original singleton source
        // must not be replaced by a rounded quotient or an epsilon-wide span.
        throw KernelError(phase: .geometry, code: .unsupportedCapability, tolerance: tolerance,
            message: "Original trim station requires a retained nonrepresentable parameter chart.")
    }
}
