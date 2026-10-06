import CADCore

/// The original endpoint-span law with an oriented, finite native parameter map.
public struct OriginalBSplineCurve2DContinuation: Hashable, Sendable {
    public let original: BSplineCurve2D
    public let startParameter: Double
    public let endParameter: Double
    public let certificationTolerance: ModelingTolerance

    public init(original: BSplineCurve2D, startParameter: Double, endParameter: Double,
        tolerance: ModelingTolerance) throws {
        self.original = original
        self.startParameter = startParameter
        self.endParameter = endParameter
        certificationTolerance = tolerance
        try validate(tolerance: tolerance)
    }

    public init(original: BSplineCurve2D, startParameter: Double, endParameter: Double,
        tolerance: ModelingTolerance, remainingSourceDepth: Int, maximumSubdivisionDepth: Int,
        maximumAlgebraicDepth: Int? = nil, consumeWork: () throws -> Void,
        consumeStorage: ((Int) throws -> Void)? = nil) throws {
        try tolerance.validate(); try consumeWork()
        guard remainingSourceDepth > 0, maximumSubdivisionDepth >= 0,
            tolerance.distance.isFinite, startParameter.isFinite, endParameter.isFinite,
            startParameter != endParameter, (endParameter - startParameter).isFinite,
            !original.controlPoints.isEmpty,
            maximumAlgebraicDepth.map({ (0...32).contains($0) }) ?? true else {
            throw GeometryConversionError.invalidInput("Bounded original continuation requires finite directed endpoints and independent caller policies.")
        }
        self.original = original; self.startParameter = startParameter; self.endParameter = endParameter
        certificationTolerance = tolerance
        // This original native producer validates the complete raw spline and
        // meters its real coefficient preparation before continuation queries.
        _ = try OriginalParameterCurveHigherTaylor.enclosure(.bSpline(original),
            over: .init(lower: 0, upper: 1), order: 0, tolerance: tolerance,
            maximumSpanCount: original.controlPoints.count, maximumSubdivisionDepth: maximumSubdivisionDepth,
            remainingSourceDepth: remainingSourceDepth, consumeWork: consumeWork, consumeStorage: consumeStorage,
            maximumAlgebraicDepth: maximumAlgebraicDepth)
        _ = try originalParameterBounds(over: .init(lower: 0, upper: 1), tolerance: tolerance,
            maximumSpanCount: original.controlPoints.count, maximumSubdivisionDepth: maximumSubdivisionDepth,
            remainingSourceDepth: remainingSourceDepth, consumeWork: consumeWork, consumeStorage: consumeStorage,
            maximumAlgebraicDepth: maximumAlgebraicDepth)
    }

    /// Original value cover after the caller has admitted the raw source.
    package func originalParameterBounds(over fractions: ScalarInterval, tolerance: ModelingTolerance,
        maximumSpanCount: Int, maximumSubdivisionDepth: Int, remainingSourceDepth: Int,
        consumeWork: () throws -> Void, consumeStorage: ((Int) throws -> Void)? = nil,
        maximumAlgebraicDepth: Int? = nil) throws -> SurfaceParameterBox {
        guard tolerance == certificationTolerance else {
            throw GeometryConversionError.invalidInput("Original continuation query changed its retained tolerance.")
        }
        let jet = try OriginalParameterCurveHigherTaylor.enclosure(.originalBSplineContinuation(self),
            over: fractions, order: 0, tolerance: tolerance, maximumSpanCount: maximumSpanCount,
            maximumSubdivisionDepth: maximumSubdivisionDepth, remainingSourceDepth: remainingSourceDepth,
            consumeWork: consumeWork, consumeStorage: consumeStorage, maximumAlgebraicDepth: maximumAlgebraicDepth)
        let u = try jet.u.coefficient(0,0), v = try jet.v.coefficient(0,0)
        guard u.isFinite, v.isFinite else {
            throw GeometryConversionError.resourceLimitExceeded("Original continuation whole position exceeds finite interval arithmetic.")
        }
        return try .init(u: .init(lower: u.lower, upper: u.upper), v: .init(lower: v.lower, upper: v.upper))
    }

    public func validate(tolerance: ModelingTolerance) throws {
        try original.validate(tolerance: tolerance)
        guard tolerance == certificationTolerance, startParameter.isFinite, endParameter.isFinite,
            (endParameter - startParameter).isFinite, endParameter != startParameter else {
            throw GeometryConversionError.invalidInput("An original 2D continuation requires its exact tolerance and finite oriented endpoints.")
        }
        let source = try OriginalBSplineCurve2DContinuationSource(curve: original, tolerance: tolerance)
        _ = try source.enclosure(over: ScalarInterval(lower: min(startParameter, endParameter),
            upper: max(startParameter, endParameter)), tolerance: tolerance)
    }

    public func parameter(atNormalizedFraction fraction: Double,
        tolerance: ModelingTolerance) throws -> SurfaceParameter {
        let jet = try intervalJet(over: ScalarInterval(lower: fraction, upper: fraction), tolerance: tolerance)
        return SurfaceParameter(u: jet.u.value.midpoint, v: jet.v.value.midpoint)
    }

    public func differential(atNormalizedFraction fraction: Double,
        tolerance: ModelingTolerance) throws -> SurfaceParameterCurveDifferential {
        let jet = try intervalJet(over: ScalarInterval(lower: fraction, upper: fraction), tolerance: tolerance)
        return .init(parameter: SurfaceParameter(u: jet.u.value.midpoint, v: jet.v.value.midpoint),
            firstDerivative: Point2D(x: jet.u.derivativeU.midpoint, y: jet.v.derivativeU.midpoint),
            secondDerivative: Point2D(x: jet.u.secondDerivativeUU.midpoint, y: jet.v.secondDerivativeUU.midpoint))
    }

    public func subcurve(fromNormalizedFraction lower: Double, toNormalizedFraction upper: Double,
        tolerance: ModelingTolerance) throws -> Self {
        guard lower.isFinite, upper.isFinite, lower >= 0, upper <= 1, lower < upper else {
            throw GeometryConversionError.invalidInput("An original continuation trim requires a positive fraction interval inside its owner.")
        }
        let span = endParameter - startParameter
        return try Self(original: original, startParameter: startParameter + span * lower,
            endParameter: startParameter + span * upper, tolerance: tolerance)
    }

    public func reversed(tolerance: ModelingTolerance) throws -> Self {
        try Self(original: original, startParameter: endParameter, endParameter: startParameter, tolerance: tolerance)
    }

    func intervalJet(over fractions: ScalarInterval, tolerance: ModelingTolerance,
        consumeWork: () throws -> Void = { try CurrentTaskCancellationChecker().checkCancellation() })
        throws -> (u: SurfaceIntervalJet, v: SurfaceIntervalJet) {
        let source = try OriginalBSplineCurve2DContinuationSource(curve: original, tolerance: tolerance,
            consumeWork: consumeWork)
        return try intervalJet(over: fractions, source: source, tolerance: tolerance, consumeWork: consumeWork)
    }

    func intervalJet(over fractions: ScalarInterval, source: OriginalBSplineCurve2DContinuationSource,
        tolerance: ModelingTolerance, consumeWork: () throws -> Void = { try CurrentTaskCancellationChecker().checkCancellation() })
        throws -> (u: SurfaceIntervalJet, v: SurfaceIntervalJet) {
        try GeometryStructuralComparisonWork.charge(parameterCurve: .bSpline(original), using: { count in
            for _ in 0..<count { try consumeWork() }
        })
        try GeometryStructuralComparisonWork.charge(parameterCurve: .bSpline(source.curve), using: { count in
            for _ in 0..<count { try consumeWork() }
        })
        guard source.curve == original else {
            throw GeometryConversionError.invalidInput("A prepared continuation belongs to another original spline.")
        }
        try CurrentTaskCancellationChecker().checkCancellation()
        guard tolerance == certificationTolerance, fractions.lower.isFinite, fractions.upper.isFinite,
            fractions.lower >= 0, fractions.upper <= 1 else {
            throw GeometryConversionError.invalidInput("Original continuation fractions lie outside their retained owner or tolerance.")
        }
        try consumeWork()
        let slope = OutwardScalarInterval.exact(endParameter) - .exact(startParameter)
        let nativeParameter = SurfaceIntervalJet.constant(startParameter)
            + .parameterU(fractions) * SurfaceIntervalJet(value: slope,
                derivativeU: .exact(0), derivativeV: .exact(0),
                secondDerivativeUU: .exact(0), secondDerivativeUV: .exact(0), secondDerivativeVV: .exact(0),
                thirdDerivativeUUU: .exact(0), thirdDerivativeUUV: .exact(0),
                thirdDerivativeUVV: .exact(0), thirdDerivativeVVV: .exact(0))
        let native = try source.originalJet(over: ScalarInterval(lower: nativeParameter.value.lower,
            upper: nativeParameter.value.upper), tolerance: tolerance, consumeWork: consumeWork)
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
