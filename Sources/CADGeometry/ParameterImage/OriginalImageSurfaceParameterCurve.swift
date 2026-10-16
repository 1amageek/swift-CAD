import CADCore

/// Persistent foreign UV image of an original face-local source law.
public struct OriginalImageSurfaceParameterCurve: Hashable, Sendable {
    public let source: SurfaceLiftCurve3D
    public let targetImage: OriginalImageSurface3D
    public let startFraction: Double
    public let endFraction: Double

    public init(source: SurfaceLiftCurve3D, targetImage: OriginalImageSurface3D,
        startFraction: Double = 0, endFraction: Double = 1,
        tolerance: ModelingTolerance) throws {
        var execution = try OriginalQueryExecution.independentGeometry()
        try self.init(source: source, targetImage: targetImage, startFraction: startFraction,
            endFraction: endFraction, tolerance: tolerance, using: &execution)
    }
    public init(source: SurfaceLiftCurve3D, targetImage: OriginalImageSurface3D,
        startFraction: Double = 0, endFraction: Double = 1,
        tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws {
        self.source = source; self.targetImage = targetImage
        self.startFraction = startFraction; self.endFraction = endFraction
        try validate(on: .parameterImage(targetImage), tolerance: tolerance, using: &execution)
    }

    public func validate(on surface: Surface3D, tolerance: ModelingTolerance) throws {
        var execution = try OriginalQueryExecution.independentGeometry()
        try validate(on: surface, tolerance: tolerance, using: &execution)
    }

    public func validate(on surface: Surface3D, tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws {
        try execution.consumeWork(1)
        try Curve3D.surfaceLift(source).validateOriginalSource(tolerance: tolerance,
            remainingSourceDepth: execution.limits.remainingSourceDepth,
            maximumSubdivisionDepth: execution.limits.maximumSubdivisionDepth, using: &execution)
        try Surface3D.parameterImage(targetImage).validateOriginalSource(tolerance: tolerance,
            remainingSourceDepth: execution.limits.remainingSourceDepth,
            maximumSubdivisionDepth: execution.limits.maximumSubdivisionDepth, using: &execution)
        try GeometryStructuralComparisonWork.charge(surface: source.surface, using: &execution)
        try GeometryStructuralComparisonWork.charge(surface: targetImage.source, using: &execution)
        guard source.surface == targetImage.source, surface == .parameterImage(targetImage),
            startFraction.isFinite, endFraction.isFinite, startFraction >= 0, startFraction <= 1,
            endFraction >= 0, endFraction <= 1, startFraction != endFraction else {
            throw GeometryConversionError.invalidInput("Original image pcurve needs its exact source/target chart binding and directed source fractions.")
        }
    }

    public func parameter(atNormalizedFraction fraction: Double,
        tolerance: ModelingTolerance) throws -> SurfaceParameter {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try parameter(atNormalizedFraction: fraction, tolerance: tolerance, using: &execution)
    }

    public func parameter(atNormalizedFraction fraction: Double,
        tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws -> SurfaceParameter {
        try execution.consumeWork(1)
        let parameter = try source.parameterCurve.parameter(atNormalizedFraction:
            mappedFraction(fraction), tolerance: tolerance, using: &execution)
        let nativeU = targetImage.swapAxes ? parameter.v : parameter.u
        let nativeV = targetImage.swapAxes ? parameter.u : parameter.v
        func foreign(_ native: Double, gain: OriginalParameterGain, offset: Double) throws -> Double {
            let pair = gain.coefficients
            let candidate = ((native - offset) / pair.numerator) * pair.denominator
            guard candidate.isFinite else { throw GeometryConversionError.resourceLimitExceeded("Original image UV evaluation is nonfinite.") }
            return candidate
        }
        // These scalar values are evaluation candidates. The stored original
        // chart and interval inverse supply identity and enclosure authority.
        return try .init(u: foreign(nativeU, gain: targetImage.uParameterGain, offset: targetImage.uOffset),
            v: foreign(nativeV, gain: targetImage.vParameterGain, offset: targetImage.vOffset))
    }

    public func differential(atNormalizedFraction fraction: Double,
        tolerance: ModelingTolerance) throws -> SurfaceParameterCurveDifferential {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try differential(atNormalizedFraction: fraction, tolerance: tolerance, using: &execution)
    }

    public func differential(atNormalizedFraction fraction: Double,
        tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws -> SurfaceParameterCurveDifferential {
        try execution.consumeWork(1)
        let original = try source.parameterCurve.differentialGeometry(
            atNormalizedFraction: mappedFraction(fraction), tolerance: tolerance, using: &execution)
        let scale = endFraction - startFraction
        func mapped(_ value: Point2D, _ order: Int) -> Point2D {
            let factor = order == 1 ? scale : scale * scale
            return Point2D(x: (targetImage.swapAxes ? value.y : value.x) * factor / targetImage.uGain,
                y: (targetImage.swapAxes ? value.x : value.y) * factor / targetImage.vGain)
        }
        return try .init(parameter: parameter(atNormalizedFraction: fraction, tolerance: tolerance, using: &execution),
            firstDerivative: mapped(original.firstDerivative, 1), secondDerivative: mapped(original.secondDerivative, 2))
    }

    package func modelSpaceDifferential(atNormalizedFraction fraction: Double,
        tolerance: ModelingTolerance) throws -> SurfaceLiftCurve3D.DifferentialGeometry {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try modelSpaceDifferential(atNormalizedFraction: fraction, tolerance: tolerance, using: &execution)
    }

    package func modelSpaceDifferential(atNormalizedFraction fraction: Double,
        tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws -> SurfaceLiftCurve3D.DifferentialGeometry {
        try execution.consumeWork(1)
        let original = try source.differentialGeometry(atNormalizedFraction: mappedFraction(fraction), tolerance: tolerance, using: &execution)
        let scale = endFraction - startFraction
        return .init(position: targetImage.transform.applying(to: original.position),
            firstDerivative: targetImage.transform.applying(to: original.firstDerivative) * scale,
            secondDerivative: targetImage.transform.applying(to: original.secondDerivative) * (scale * scale))
    }

    func modelSpaceThirdOrder(atNormalizedFraction fraction: Double,
        tolerance: ModelingTolerance) throws -> CurveParameterThirdOrderDerivatives {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try modelSpaceThirdOrder(atNormalizedFraction: fraction, tolerance: tolerance, using: &execution)
    }

    func modelSpaceThirdOrder(atNormalizedFraction fraction: Double,
        tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws -> CurveParameterThirdOrderDerivatives {
        try execution.consumeWork(1)
        let original = try Curve3D.surfaceLift(source).parameterDerivativesThroughThirdOrder(
            at: mappedFraction(fraction), tolerance: tolerance, using: &execution)
        let scale = endFraction - startFraction
        return .init(position: targetImage.transform.applying(to: original.position),
            firstDerivative: targetImage.transform.applying(to: original.firstDerivative) * scale,
            secondDerivative: targetImage.transform.applying(to: original.secondDerivative) * (scale * scale),
            thirdDerivative: targetImage.transform.applying(to: original.thirdDerivative) * (scale * scale * scale))
    }

    func thirdDerivative(atNormalizedFraction fraction: Double,
        tolerance: ModelingTolerance) throws -> Point2D {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try thirdDerivative(atNormalizedFraction: fraction, tolerance: tolerance, using: &execution)
    }

    func thirdDerivative(atNormalizedFraction fraction: Double,
        tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws -> Point2D {
        try execution.consumeWork(1)
        let original = try source.parameterCurve.thirdOrderDifferential(
            atNormalizedFraction: mappedFraction(fraction), on: source.surface, tolerance: tolerance, using: &execution)
        let scale = endFraction - startFraction
        let cube = scale * scale * scale
        return Point2D(x: (targetImage.swapAxes ? original.thirdDerivative.y : original.thirdDerivative.x)
            * cube / targetImage.uGain,
            y: (targetImage.swapAxes ? original.thirdDerivative.x : original.thirdDerivative.y)
                * cube / targetImage.vGain)
    }

    public func reversed(tolerance: ModelingTolerance) throws -> Self {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try reversed(tolerance: tolerance, using: &execution)
    }

    public func reversed(tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws -> Self {
        try execution.consumeWork(1)
        return try .init(source: source, targetImage: targetImage, startFraction: endFraction,
            endFraction: startFraction, tolerance: tolerance, using: &execution)
    }

    public func subcurve(fromNormalizedFraction lower: Double, toNormalizedFraction upper: Double,
        tolerance: ModelingTolerance) throws -> Self {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try subcurve(fromNormalizedFraction: lower, toNormalizedFraction: upper, tolerance: tolerance, using: &execution)
    }

    public func subcurve(fromNormalizedFraction lower: Double, toNormalizedFraction upper: Double,
        tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws -> Self {
        try execution.consumeWork(1)
        return try .init(source: source, targetImage: targetImage,
            startFraction: mappedFraction(lower), endFraction: mappedFraction(upper), tolerance: tolerance, using: &execution)
    }

    /// Original foreign UV enclosure with caller-owned source work and depth.
    package func parameterBounds(over range: ScalarInterval, tolerance: ModelingTolerance,
        maximumSpanCount: Int, maximumSubdivisionDepth: Int, remainingSourceDepth: Int,
        maximumAlgebraicDepth: Int? = nil, using execution: inout OriginalQueryExecution) throws -> SurfaceParameterBox {
        let query = try mappedRange(range, maximumAlgebraicDepth: maximumAlgebraicDepth, using: &execution)
        let original = try OriginalParameterCurveHigherTaylor.enclosure(source.parameterCurve,
            over: query, order: 0, tolerance: tolerance, maximumSpanCount: maximumSpanCount,
            maximumSubdivisionDepth: maximumSubdivisionDepth, remainingSourceDepth: remainingSourceDepth,
            maximumAlgebraicDepth: maximumAlgebraicDepth, using: &execution)
        let u = try original.u.coefficient(0, 0), v = try original.v.coefficient(0, 0)
        return try SurfaceParameterBox(
            u: inverseParameterInterval(ScalarInterval(lower: targetImage.swapAxes ? v.lower : u.lower,
                upper: targetImage.swapAxes ? v.upper : u.upper), gain: targetImage.uParameterGain,
                offset: targetImage.uOffset, maximumAlgebraicDepth: maximumAlgebraicDepth, using: &execution),
            v: inverseParameterInterval(ScalarInterval(lower: targetImage.swapAxes ? u.lower : v.lower,
                upper: targetImage.swapAxes ? u.upper : v.upper), gain: targetImage.vParameterGain,
                offset: targetImage.vOffset, maximumAlgebraicDepth: maximumAlgebraicDepth, using: &execution))
    }

    package func inverseParameterInterval(_ range: ScalarInterval, gain: OriginalParameterGain,
        offset: Double, maximumAlgebraicDepth: Int? = nil, using execution: inout OriginalQueryExecution) throws -> ScalarInterval {
        let maximum = try maximumAlgebraicDepth.map { try ExactScalarDepth(value: $0, coefficient: $0) }
        return try execution.withProofScope(maximum: maximum) { usage in
            try OriginalParameterImageMap.inverseInterval(range, gain: gain, offset: offset, usage: &usage)
        }
    }

    package func mappedRange(_ range: ScalarInterval, maximumAlgebraicDepth: Int? = nil, using execution: inout OriginalQueryExecution) throws -> ScalarInterval {
        guard range.lower.isFinite, range.upper.isFinite,
            range.lower >= 0, range.upper <= 1, range.lower <= range.upper else {
            throw GeometryConversionError.invalidInput("Original hosted UV range must belong to its normalized chart.")
        }
        let maximum = try maximumAlgebraicDepth.map { try ExactScalarDepth(value: $0, coefficient: $0) }
        return try execution.withProofScope(maximum: maximum) { usage in
            let first = try ExactRationalCoefficient.originalDouble(startFraction, usage: &usage)
            let gain = try ExactRationalCoefficient.originalDouble(endFraction, usage: &usage)
                .subtracting(first, usage: &usage)
            func endpoint(_ value: Double, usage: inout OriginalQueryExecution)
                throws -> OutwardScalarInterval {
                try first.adding(gain.multiplied(by: .originalDouble(value, usage: &usage),
                    usage: &usage), usage: &usage).outwardInterval(usage: &usage)
            }
            let a = try endpoint(range.lower, usage: &usage)
            let b = try endpoint(range.upper, usage: &usage)
            return try ScalarInterval(lower: max(min(startFraction, endFraction), min(a.lower, b.lower)),
                upper: min(max(startFraction, endFraction), max(a.upper, b.upper)))
        }
    }

    package func mappedRange(_ range: ScalarInterval) throws -> ScalarInterval {
        guard range.lower >= 0, range.upper <= 1 else {
            throw GeometryConversionError.invalidInput("Original image pcurve range must belong to its normalized chart.")
        }
        if range.lower == range.upper, range.lower == 0 || range.lower == 1 {
            let exact = range.lower == 0 ? startFraction : endFraction
            return try .init(lower: exact, upper: exact)
        }
        let scale = OutwardScalarInterval.exact(endFraction) - .exact(startFraction)
        let image = .exact(startFraction) + scale * OutwardScalarInterval(lower: range.lower, upper: range.upper)
        guard let contained = image.intersection(with: .init(lower: min(startFraction, endFraction), upper: max(startFraction, endFraction))) else {
            throw GeometryConversionError.invalidInput("Original image pcurve directed range is empty.")
        }
        return try .init(lower: contained.lower, upper: contained.upper)
    }

    func intervalJet(over range: ScalarInterval, tolerance: ModelingTolerance,
        preparedImplicit: ImplicitCurveIntervalJetEncloser? = nil)
        throws -> (u: SurfaceIntervalJet, v: SurfaceIntervalJet)? {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try intervalJet(over: range, tolerance: tolerance, preparedImplicit: preparedImplicit, using: &execution)
    }

    func intervalJet(over range: ScalarInterval, tolerance: ModelingTolerance,
        preparedImplicit: ImplicitCurveIntervalJetEncloser? = nil, using execution: inout OriginalQueryExecution)
        throws -> (u: SurfaceIntervalJet, v: SurfaceIntervalJet)? {
        try execution.consumeWork(1)
        guard let original = try DefaultCurveDifferentialEncloser().parameterJets(source.parameterCurve,
            over: mappedRange(range), tolerance: tolerance, preparedImplicit: preparedImplicit, using: &execution) else { return nil }
        return try mappedParameterJets(u: original.u, v: original.v, using: &execution)
    }

    func mappedParameterJets(u nativeU: SurfaceIntervalJet, v nativeV: SurfaceIntervalJet)
        throws -> (u: SurfaceIntervalJet, v: SurfaceIntervalJet) {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try mappedParameterJets(u: nativeU, v: nativeV, using: &execution)
    }

    package func mappedParameterJets(u nativeU: SurfaceIntervalJet, v nativeV: SurfaceIntervalJet,
        maximumAlgebraicDepth: Int? = nil, using execution: inout OriginalQueryExecution) throws -> (u: SurfaceIntervalJet, v: SurfaceIntervalJet) {
        let scale = OutwardScalarInterval.exact(endFraction) - .exact(startFraction)
        func inverse(_ field: SurfaceIntervalJet, gain: OriginalParameterGain, offset: Double)
            throws -> SurfaceIntervalJet {
            func derivative(_ bound: OutwardScalarInterval) throws -> OutwardScalarInterval {
                let mapped = try inverseParameterInterval(ScalarInterval(lower: bound.lower, upper: bound.upper),
                    gain: gain, offset: 0, maximumAlgebraicDepth: maximumAlgebraicDepth, using: &execution)
                return .init(lower: mapped.lower, upper: mapped.upper)
            }
            let value = try inverseParameterInterval(ScalarInterval(lower: field.value.lower,
                upper: field.value.upper), gain: gain, offset: offset, maximumAlgebraicDepth: maximumAlgebraicDepth, using: &execution)
            try execution.consumeWork(1)
            let zero = OutwardScalarInterval.exact(0)
            return .init(value: .init(lower: value.lower, upper: value.upper),
                derivativeU: try derivative(field.derivativeU * scale), derivativeV: zero,
                secondDerivativeUU: try derivative(field.secondDerivativeUU * scale * scale),
                secondDerivativeUV: zero, secondDerivativeVV: zero,
                thirdDerivativeUUU: try derivative(field.thirdDerivativeUUU * scale * scale * scale),
                thirdDerivativeUUV: zero, thirdDerivativeUVV: zero, thirdDerivativeVVV: zero)
        }
        return try (inverse(targetImage.swapAxes ? nativeV : nativeU,
            gain: targetImage.uParameterGain, offset: targetImage.uOffset),
            inverse(targetImage.swapAxes ? nativeU : nativeV,
                gain: targetImage.vParameterGain, offset: targetImage.vOffset))
    }

    func modelSpaceIntervalJet(over range: ScalarInterval, tolerance: ModelingTolerance,
        preparedImplicit: ImplicitCurveIntervalJetEncloser? = nil) throws -> SurfaceIntervalVectorJet? {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try modelSpaceIntervalJet(over: range, tolerance: tolerance, preparedImplicit: preparedImplicit, using: &execution)
    }

    func modelSpaceIntervalJet(over range: ScalarInterval, tolerance: ModelingTolerance,
        preparedImplicit: ImplicitCurveIntervalJetEncloser? = nil, using execution: inout OriginalQueryExecution) throws -> SurfaceIntervalVectorJet? {
        try execution.consumeWork(1)
        guard let original = try DefaultCurveDifferentialEncloser().directJet(.surfaceLift(source),
            parameters: mappedRange(range), tolerance: tolerance, preparedImplicit: preparedImplicit, using: &execution) else { return nil }
        let scale = OutwardScalarInterval.exact(endFraction) - .exact(startFraction)
        func component(_ field: SurfaceIntervalJet) -> SurfaceIntervalJet {
            let zero = OutwardScalarInterval.exact(0)
            return .init(value: field.value, derivativeU: field.derivativeU * scale, derivativeV: zero,
                secondDerivativeUU: field.secondDerivativeUU * scale * scale,
                secondDerivativeUV: zero, secondDerivativeVV: zero,
                thirdDerivativeUUU: field.thirdDerivativeUUU * scale * scale * scale,
                thirdDerivativeUUV: zero, thirdDerivativeUVV: zero, thirdDerivativeVVV: zero)
        }
        let mapped = SurfaceIntervalVectorJet(x: component(original.x), y: component(original.y), z: component(original.z))
        let transform = targetImage.transform
        return .constant(transform.translation) + .constant(transform.basisX) * mapped.x
            + .constant(transform.basisY) * mapped.y + .constant(transform.basisZ) * mapped.z
    }

    private func mappedFraction(_ fraction: Double) throws -> Double {
        guard fraction.isFinite, fraction >= 0, fraction <= 1 else {
            throw GeometryConversionError.invalidInput("Original image pcurve fraction must lie in its closed normalized chart.")
        }
        if fraction == 0 { return startFraction }
        if fraction == 1 { return endFraction }
        return startFraction + (endFraction - startFraction) * fraction
    }
}

#if !hasFeature(Embedded)
extension OriginalImageSurfaceParameterCurve: Codable {
    private enum CodingKeys: String, CodingKey { case source, targetImage, startFraction, endFraction }
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys([.source, .targetImage, .startFraction, .endFraction], in: decoder)
        source = try container.decode(SurfaceLiftCurve3D.self, forKey: .source)
        targetImage = try container.decode(OriginalImageSurface3D.self, forKey: .targetImage)
        startFraction = try container.decode(Double.self, forKey: .startFraction)
        endFraction = try container.decode(Double.self, forKey: .endFraction)
        guard source.surface == targetImage.source, startFraction.isFinite, endFraction.isFinite,
            startFraction >= 0, startFraction <= 1, endFraction >= 0, endFraction <= 1,
            startFraction != endFraction else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                debugDescription: "Original image pcurve has inconsistent source/target chart binding."))
        }
    }
}
#endif
