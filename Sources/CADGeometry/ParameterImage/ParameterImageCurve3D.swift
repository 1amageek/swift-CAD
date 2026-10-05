import CADCore

/// The original curve law evaluated in a retained foreign parameter unit.
public struct ParameterImageCurve3D: Hashable, Sendable {
    public let source: Curve3D
    public let parameterGain: OriginalParameterGain
    public var gain: Double { parameterGain.value }
    public let offset: Double

    public init(source: Curve3D, gain: Double, offset: Double = 0,
        tolerance: ModelingTolerance) throws {
        try self.init(source: source, parameterGain: .binary(gain), offset: offset, tolerance: tolerance)
    }

    public init(source: Curve3D, parameterGain: OriginalParameterGain, offset: Double = 0,
        tolerance: ModelingTolerance) throws {
        self.source = source; self.parameterGain = parameterGain; self.offset = offset
        try validate(tolerance: tolerance)
    }

    package init(validatedSource source: Curve3D, parameterGain: OriginalParameterGain, offset: Double) {
        self.source = source; self.parameterGain = parameterGain; self.offset = offset
    }

    public var parameterDomain: ParameterDomain {
        OriginalParameterImageMap.domain(source.parameterDomain, gain: parameterGain, offset: offset)
    }

    public func validate(tolerance: ModelingTolerance) throws {
        try OriginalParameterImageMap.validate(gain: parameterGain, offset: offset)
        try source.validate(tolerance: tolerance)
        try parameterDomain.validate(tolerance: tolerance)
    }

    /// Numeric original-ratio evaluation; sourceParameterBounds supplies exact range authority.
    public func sourceParameter(at parameter: Double, tolerance: ModelingTolerance) throws -> Double {
        try validate(tolerance: tolerance)
        let range = try sourceParameterBounds(over: ScalarInterval(lower: parameter, upper: parameter), tolerance: tolerance)
        if range.lower == range.upper { return range.lower }
        return try OriginalParameterImageMap.parameter(parameter, gain: parameterGain, offset: offset)
    }

    package func pointAssumingValid(at parameter: Double,
        tolerance: ModelingTolerance) throws -> Point3D {
        try source.pointAssumingValid(at: OriginalParameterImageMap.parameter(parameter,
            gain: parameterGain, offset: offset), tolerance: tolerance)
    }

    package func differentialGeometryAssumingValid(at parameter: Double,
        tolerance: ModelingTolerance) throws -> Curve3D.DifferentialGeometry {
        let native = try OriginalParameterImageMap.parameter(parameter, gain: parameterGain, offset: offset)
        let original = try source.differentialGeometryAssumingValid(at: native, tolerance: tolerance)
        return try Curve3D.differentialGeometry(position: original.position,
            firstDerivative: original.firstDerivative * gain,
            secondDerivative: original.secondDerivative * (gain * gain), tolerance: tolerance)
    }

    /// Encloses the exact original scalar image, retaining proven singleton identities.
    public func sourceParameterBounds(over interval: ScalarInterval,
        tolerance: ModelingTolerance, consumeWork: () throws -> Void = {}) throws -> ScalarInterval {
        try validate(tolerance: tolerance)
        return try originalInterval(interval, consumeWork:consumeWork)
    }

    /// Caller-admitted source validation and exact original affine endpoint map.
    public func sourceParameterBounds(over interval: ScalarInterval, tolerance: ModelingTolerance,
        remainingSourceDepth: Int, maximumSubdivisionDepth: Int,
        consumeWork: (Int) throws -> Void, consumeStorage: ((Int) throws -> Void)? = nil,
        maximumAlgebraicDepth: Int? = nil) throws -> ScalarInterval {
        guard remainingSourceDepth > 0, maximumSubdivisionDepth >= 0,
            maximumAlgebraicDepth.map({ (0...32).contains($0) }) ?? true else {
            throw GeometryConversionError.invalidInput("Original parameter image requires independent source, subdivision and algebra capabilities.")
        }
        return try withoutActuallyEscaping(consumeWork) { work in
            var usage = OriginalGeometryValidationAdmission(consumeWork: work,
                consumeStorage: consumeStorage, maximumAlgebraicDepth: maximumAlgebraicDepth)
            let gain = try parameterGain.exactCoefficient(usage: &usage)
            guard !gain.isZero, offset.isFinite else {
                throw GeometryConversionError.invalidInput("Original parameter image requires finite offset and nonzero original gain.")
            }
            try source.validateOriginalSource(tolerance: tolerance, remainingSourceDepth: remainingSourceDepth - 1,
                maximumSubdivisionDepth: maximumSubdivisionDepth, consumeWork: work,
                consumeStorage: consumeStorage, maximumAlgebraicDepth: maximumAlgebraicDepth)
            return try OriginalParameterImageMap.interval(interval, gain: parameterGain, offset: offset,
                sourceDomain: source.parameterDomain, usage: &usage)
        }
    }

    /// Requires the enclosing caller's original relation admission; performs no source revalidation.
    package func sourceParameterBoundsAssumingValidatedOriginalRelation<B: RationalAlgebraAdmitting>(
        over interval: ScalarInterval, usage: inout B) throws -> ScalarInterval {
        try OriginalParameterImageMap.interval(interval, gain: parameterGain, offset: offset,
            sourceDomain: source.parameterDomain, usage: &usage)
    }

    /// The exact inverse ratio image, including represented boundary identities.
    public func foreignParameterBounds(fromSourceInterval interval: ScalarInterval,
        tolerance: ModelingTolerance, consumeWork: () throws -> Void = {}) throws -> ScalarInterval {
        try validate(tolerance: tolerance)
        return try OriginalParameterImageMap.inverseInterval(interval, gain: parameterGain, offset: offset, consumeWork:consumeWork)
    }

    public func foreignParameter(fromSourceParameter parameter: Double,
        tolerance: ModelingTolerance) throws -> Double {
        let bounds = try foreignParameterBounds(fromSourceInterval:
            ScalarInterval(lower: parameter, upper: parameter), tolerance: tolerance)
        guard bounds.lower == bounds.upper else {
            // FIXME(INCOMPLETE_IMPLEMENTATION): Exact trim publication for a
            // nonrepresentable foreign endpoint needs a retained native-boundary
            // chart. Exchange must not publish a rounded inverse as that chart.
            throw KernelError(phase: .geometry, code: .unsupportedCapability, tolerance: tolerance,
                message: "Original foreign parameter is not exactly representable as a scalar endpoint.")
        }
        return bounds.lower
    }

    package func originalInterval(_ interval: ScalarInterval, consumeWork: () throws -> Void = {}) throws -> ScalarInterval {
        try OriginalParameterImageMap.interval(interval, gain: parameterGain, offset: offset,
            sourceDomain: source.parameterDomain, consumeWork: consumeWork)
    }

    func mappedJet(_ original: SurfaceIntervalVectorJet) throws -> SurfaceIntervalVectorJet {
        let zero = OutwardScalarInterval.exact(0), scale = try parameterGain.interval()
        func coordinate(_ source: SurfaceIntervalJet) -> SurfaceIntervalJet {
            .init(value: source.value, derivativeU: source.derivativeU * scale,
                derivativeV: zero, secondDerivativeUU: source.secondDerivativeUU * scale * scale,
                secondDerivativeUV: zero, secondDerivativeVV: zero,
                thirdDerivativeUUU: source.thirdDerivativeUUU * scale * scale * scale,
                thirdDerivativeUUV: zero, thirdDerivativeUVV: zero, thirdDerivativeVVV: zero)
        }
        return .init(x: coordinate(original.x), y: coordinate(original.y), z: coordinate(original.z))
    }
}

#if !hasFeature(Embedded)
extension ParameterImageCurve3D: Codable {
    private enum CodingKeys: String, CodingKey { case source, parameterGain, offset }
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys([.source, .parameterGain, .offset], in: decoder)
        source = try container.decode(Curve3D.self, forKey: .source)
        parameterGain = try container.decode(OriginalParameterGain.self, forKey: .parameterGain)
        offset = try container.decode(Double.self, forKey: .offset)
        try OriginalParameterImageMap.validate(gain: parameterGain, offset: offset)
    }
}
#endif
