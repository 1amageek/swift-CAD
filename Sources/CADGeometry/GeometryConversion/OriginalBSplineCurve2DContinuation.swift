import CADCore

/// The original endpoint-span law with an oriented, finite native parameter map.
public struct OriginalBSplineCurve2DContinuation: Hashable, Sendable {
    public let original: BSplineCurve2D
    public let startParameter: Double
    public let endParameter: Double
    public let certificationTolerance: ModelingTolerance

    public init(original: BSplineCurve2D, startParameter: Double, endParameter: Double,
        tolerance: ModelingTolerance) throws {
        var execution = OriginalQueryExecution(budget: try OriginalQueryBudget(),
            limits: try OriginalQueryExecutionLimits(maximumValueDepth: 32, maximumCoefficientDepth: 32))
        try self.init(original: original, startParameter: startParameter, endParameter: endParameter,
            tolerance: tolerance, remainingSourceDepth: execution.effectiveLimits.remainingSourceDepth,
            maximumSubdivisionDepth: execution.effectiveLimits.maximumSubdivisionDepth, using: &execution)
    }

    public init(original: BSplineCurve2D, startParameter: Double, endParameter: Double,
        tolerance: ModelingTolerance, remainingSourceDepth: Int, maximumSubdivisionDepth: Int,
        maximumAlgebraicDepth: Int? = nil, using execution: inout OriginalQueryExecution) throws {
        try tolerance.validate(); try execution.consumeWork(1)
        guard remainingSourceDepth > 0, maximumSubdivisionDepth >= 0,
            tolerance.distance.isFinite, startParameter.isFinite, endParameter.isFinite,
            startParameter != endParameter, (endParameter - startParameter).isFinite,
            !original.controlPoints.isEmpty,
            maximumAlgebraicDepth.map({ (0...32).contains($0) }) ?? true else {
            throw GeometryConversionError.invalidInput("Bounded original continuation requires finite directed endpoints and independent caller policies.")
        }
        self.original = original; self.startParameter = startParameter; self.endParameter = endParameter
        certificationTolerance = tolerance
        // The original continuation producer validates raw coefficients and
        // their complete directed value cover under this same execution.
        _ = try originalParameterBounds(over: .init(lower: 0, upper: 1), tolerance: tolerance,
            maximumSpanCount: original.controlPoints.count, maximumSubdivisionDepth: maximumSubdivisionDepth,
            remainingSourceDepth: remainingSourceDepth, maximumAlgebraicDepth: maximumAlgebraicDepth, using: &execution)
    }

    /// Original value cover after the caller has admitted the raw source.
    package func originalParameterBounds(over fractions: ScalarInterval, tolerance: ModelingTolerance,
        maximumSpanCount: Int, maximumSubdivisionDepth: Int, remainingSourceDepth: Int,
        maximumAlgebraicDepth: Int? = nil, using execution: inout OriginalQueryExecution) throws -> SurfaceParameterBox {
        guard tolerance == certificationTolerance else {
            throw GeometryConversionError.invalidInput("Original continuation query changed its retained tolerance.")
        }
        let jet = try OriginalParameterCurveHigherTaylor.enclosure(.originalBSplineContinuation(self),
            over: fractions, order: 0, tolerance: tolerance, maximumSpanCount: maximumSpanCount,
            maximumSubdivisionDepth: maximumSubdivisionDepth, remainingSourceDepth: remainingSourceDepth,
            maximumAlgebraicDepth: maximumAlgebraicDepth, using: &execution)
        let u = try jet.u.coefficient(0,0), v = try jet.v.coefficient(0,0)
        guard u.isFinite, v.isFinite else {
            throw GeometryConversionError.resourceLimitExceeded("Original continuation whole position exceeds finite interval arithmetic.")
        }
        return try .init(u: .init(lower: u.lower, upper: u.upper), v: .init(lower: v.lower, upper: v.upper))
    }

    public func validate(tolerance: ModelingTolerance) throws {
        var execution = OriginalQueryExecution(budget: try OriginalQueryBudget(),
            limits: try OriginalQueryExecutionLimits(maximumValueDepth: 32, maximumCoefficientDepth: 32))
        try validate(tolerance: tolerance, using: &execution)
    }

    public func validate(tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws {
        try original.validate(tolerance: tolerance, using: &execution)
        guard tolerance == certificationTolerance, startParameter.isFinite, endParameter.isFinite,
            (endParameter - startParameter).isFinite, endParameter != startParameter else {
            throw GeometryConversionError.invalidInput("An original 2D continuation requires its exact tolerance and finite oriented endpoints.")
        }
        let source = try OriginalBSplineCurve2DContinuationSource(curve: original, tolerance: tolerance, using: &execution)
        _ = try source.enclosure(over: ScalarInterval(lower: min(startParameter, endParameter),
            upper: max(startParameter, endParameter)), tolerance: tolerance, using: &execution)
    }

    public func parameter(atNormalizedFraction fraction: Double,
        tolerance: ModelingTolerance) throws -> SurfaceParameter {
        var execution = OriginalQueryExecution(budget: try OriginalQueryBudget(), limits: try .init(maximumValueDepth: 32, maximumCoefficientDepth: 32))
        return try parameter(atNormalizedFraction: fraction, tolerance: tolerance, using: &execution)
    }

    public func differential(atNormalizedFraction fraction: Double,
        tolerance: ModelingTolerance) throws -> SurfaceParameterCurveDifferential {
        var execution = OriginalQueryExecution(budget: try OriginalQueryBudget(), limits: try .init(maximumValueDepth: 32, maximumCoefficientDepth: 32))
        return try differential(atNormalizedFraction: fraction, tolerance: tolerance, using: &execution)
    }

    public func subcurve(fromNormalizedFraction lower: Double, toNormalizedFraction upper: Double,
        tolerance: ModelingTolerance) throws -> Self {
        var execution = OriginalQueryExecution(budget: try OriginalQueryBudget(), limits: try .init(maximumValueDepth: 32, maximumCoefficientDepth: 32))
        return try subcurve(fromNormalizedFraction: lower, toNormalizedFraction: upper, tolerance: tolerance, using: &execution)
    }

    public func reversed(tolerance: ModelingTolerance) throws -> Self {
        var execution = OriginalQueryExecution(budget: try OriginalQueryBudget(), limits: try .init(maximumValueDepth: 32, maximumCoefficientDepth: 32))
        return try reversed(tolerance: tolerance, using: &execution)
    }

    public func parameter(atNormalizedFraction fraction: Double,
        tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws -> SurfaceParameter {
        try execution.consumeWork(1)
        let jet = try intervalJet(over: ScalarInterval(lower: fraction, upper: fraction), tolerance: tolerance, using: &execution)
        return SurfaceParameter(u: jet.u.value.midpoint, v: jet.v.value.midpoint)
    }

    public func differential(atNormalizedFraction fraction: Double,
        tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws -> SurfaceParameterCurveDifferential {
        try execution.consumeWork(1)
        let jet = try intervalJet(over: ScalarInterval(lower: fraction, upper: fraction), tolerance: tolerance, using: &execution)
        return .init(parameter: SurfaceParameter(u: jet.u.value.midpoint, v: jet.v.value.midpoint),
            firstDerivative: Point2D(x: jet.u.derivativeU.midpoint, y: jet.v.derivativeU.midpoint),
            secondDerivative: Point2D(x: jet.u.secondDerivativeUU.midpoint, y: jet.v.secondDerivativeUU.midpoint))
    }

    public func subcurve(fromNormalizedFraction lower: Double, toNormalizedFraction upper: Double,
        tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws -> Self {
        try execution.consumeWork(1)
        guard lower.isFinite, upper.isFinite, lower >= 0, upper <= 1, lower < upper else {
            throw GeometryConversionError.invalidInput("An original continuation trim requires a positive fraction interval inside its owner.")
        }
        let span = endParameter - startParameter
        return try Self(original: original, startParameter: startParameter + span * lower,
            endParameter: startParameter + span * upper, tolerance: tolerance,
            remainingSourceDepth: execution.effectiveLimits.remainingSourceDepth,
            maximumSubdivisionDepth: execution.effectiveLimits.maximumSubdivisionDepth, using: &execution)
    }

    public func reversed(tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws -> Self {
        try execution.consumeWork(1)
        return try Self(original: original, startParameter: endParameter, endParameter: startParameter, tolerance: tolerance,
            remainingSourceDepth: execution.effectiveLimits.remainingSourceDepth,
            maximumSubdivisionDepth: execution.effectiveLimits.maximumSubdivisionDepth, using: &execution)
    }

    func intervalJet(over fractions: ScalarInterval, tolerance: ModelingTolerance)
        throws -> (u: SurfaceIntervalJet, v: SurfaceIntervalJet) {
        var execution = OriginalQueryExecution(budget: try OriginalQueryBudget(),
            limits: try OriginalQueryExecutionLimits(maximumValueDepth: 32, maximumCoefficientDepth: 32))
        return try intervalJet(over: fractions, tolerance: tolerance, using: &execution)
    }

    func intervalJet(over fractions: ScalarInterval, tolerance: ModelingTolerance,
        using execution: inout OriginalQueryExecution)
        throws -> (u: SurfaceIntervalJet, v: SurfaceIntervalJet) {
        let source = try OriginalBSplineCurve2DContinuationSource(curve: original, tolerance: tolerance,
            using: &execution)
        return try intervalJet(over: fractions, source: source, tolerance: tolerance, using: &execution)
    }

    func intervalJet(over fractions: ScalarInterval, source: OriginalBSplineCurve2DContinuationSource,
        tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution)
        throws -> (u: SurfaceIntervalJet, v: SurfaceIntervalJet) {
        try GeometryStructuralComparisonWork.charge(parameterCurve: .bSpline(original), using: &execution)
        try GeometryStructuralComparisonWork.charge(parameterCurve: .bSpline(source.curve), using: &execution)
        guard source.curve == original else {
            throw GeometryConversionError.invalidInput("A prepared continuation belongs to another original spline.")
        }
        try CurrentTaskCancellationChecker().checkCancellation()
        guard tolerance == certificationTolerance, fractions.lower.isFinite, fractions.upper.isFinite,
            fractions.lower >= 0, fractions.upper <= 1 else {
            throw GeometryConversionError.invalidInput("Original continuation fractions lie outside their retained owner or tolerance.")
        }
        try execution.consumeWork(1)
        let slope = OutwardScalarInterval.exact(endParameter) - .exact(startParameter)
        let nativeParameter = SurfaceIntervalJet.constant(startParameter)
            + .parameterU(fractions) * SurfaceIntervalJet(value: slope,
                derivativeU: .exact(0), derivativeV: .exact(0),
                secondDerivativeUU: .exact(0), secondDerivativeUV: .exact(0), secondDerivativeVV: .exact(0),
                thirdDerivativeUUU: .exact(0), thirdDerivativeUUV: .exact(0),
                thirdDerivativeUVV: .exact(0), thirdDerivativeVVV: .exact(0))
        let native = try source.originalJet(over: ScalarInterval(lower: nativeParameter.value.lower,
            upper: nativeParameter.value.upper), tolerance: tolerance, using: &execution)
        let composed = SurfaceParameterThirdOrderChainRule.intervalJet(surface: native,
            u: nativeParameter, v: .constant(0))
        return (composed.x, composed.y)
    }
}

#if !hasFeature(Embedded)
extension OriginalBSplineCurve2DContinuation: Codable {
    private enum CodingKeys: String, CodingKey {
        case original, startParameter, endParameter, certificationTolerance
    }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try values.validateOnlyExpectedKeys([.original, .startParameter, .endParameter, .certificationTolerance], in: decoder)
        try self.init(original: values.decode(BSplineCurve2D.self, forKey: .original),
            startParameter: values.decode(Double.self, forKey: .startParameter),
            endParameter: values.decode(Double.self, forKey: .endParameter),
            tolerance: values.decode(ModelingTolerance.self, forKey: .certificationTolerance))
    }
}
#endif
