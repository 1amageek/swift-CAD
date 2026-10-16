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
        var execution = try OriginalQueryExecution.independentGeometry()
        try validate(tolerance: tolerance, using: &execution)
    }

    public func validate(tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws {
        try execution.consumeWork(1)
        try OriginalParameterImageMap.validate(gain: parameterGain, offset: offset)
        try source.validateOriginalSource(tolerance: tolerance, remainingSourceDepth: execution.limits.remainingSourceDepth, maximumSubdivisionDepth: execution.limits.maximumSubdivisionDepth, using: &execution)
        try parameterDomain.validate(tolerance: tolerance)
    }

    /// Numeric original-ratio evaluation; sourceParameterBounds supplies exact range authority.
    public func sourceParameter(at parameter: Double, tolerance: ModelingTolerance) throws -> Double {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try sourceParameter(at: parameter, tolerance: tolerance, using: &execution)
    }

    public func sourceParameter(at parameter: Double, tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws -> Double {
        try execution.consumeWork(1)
        try validate(tolerance: tolerance, using: &execution)
        let range = try sourceParameterBounds(over: ScalarInterval(lower: parameter, upper: parameter), tolerance: tolerance, using: &execution)
        if range.lower == range.upper { return range.lower }
        return try OriginalParameterImageMap.parameter(parameter, gain: parameterGain, offset: offset)
    }

    package func pointAssumingValid(at parameter: Double,
        tolerance: ModelingTolerance) throws -> Point3D {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try pointAssumingValid(at: parameter, tolerance: tolerance, using: &execution)
    }

    package func pointAssumingValid(at parameter: Double,
        tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws -> Point3D {
        try execution.consumeWork(1)
        return try source.pointAssumingValid(at: OriginalParameterImageMap.parameter(parameter,
            gain: parameterGain, offset: offset), tolerance: tolerance, using: &execution)
    }

    package func differentialGeometryAssumingValid(at parameter: Double,
        tolerance: ModelingTolerance) throws -> Curve3D.DifferentialGeometry {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try differentialGeometryAssumingValid(at: parameter, tolerance: tolerance, using: &execution)
    }

    package func differentialGeometryAssumingValid(at parameter: Double,
        tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws -> Curve3D.DifferentialGeometry {
        try execution.consumeWork(1)
        let native = try OriginalParameterImageMap.parameter(parameter, gain: parameterGain, offset: offset)
        let original = try source.differentialGeometryAssumingValid(at: native, tolerance: tolerance, using: &execution)
        return try Curve3D.differentialGeometry(position: original.position,
            firstDerivative: original.firstDerivative * gain,
            secondDerivative: original.secondDerivative * (gain * gain), tolerance: tolerance)
    }

    /// Encloses the exact original scalar image, retaining proven singleton identities.
    public func sourceParameterBounds(over interval: ScalarInterval,
        tolerance: ModelingTolerance) throws -> ScalarInterval {
        var execution = try OriginalQueryExecution.independentGeometry()
        try validate(tolerance: tolerance)
        return try originalInterval(interval, using: &execution)
    }

    public func sourceParameterBounds(over interval: ScalarInterval, tolerance: ModelingTolerance,
        using execution: inout OriginalQueryExecution) throws -> ScalarInterval {
        try sourceParameterBounds(over: interval, tolerance: tolerance,
            remainingSourceDepth: execution.limits.remainingSourceDepth,
            maximumSubdivisionDepth: execution.limits.maximumSubdivisionDepth, using: &execution)
    }

    /// Caller-admitted source validation and exact original affine endpoint map.
    public func sourceParameterBounds(over interval: ScalarInterval, tolerance: ModelingTolerance,
        remainingSourceDepth: Int, maximumSubdivisionDepth: Int,
        maximumAlgebraicDepth: Int? = nil, using execution: inout OriginalQueryExecution) throws -> ScalarInterval {
        guard remainingSourceDepth > 0, maximumSubdivisionDepth >= 0,
            maximumAlgebraicDepth.map({ (0...32).contains($0) }) ?? true else {
            throw GeometryConversionError.invalidInput("Original parameter image requires independent source, subdivision and algebra capabilities.")
        }
            let gain = try parameterGain.exactCoefficient(usage: &execution)
            guard !gain.isZero, offset.isFinite else {
                throw GeometryConversionError.invalidInput("Original parameter image requires finite offset and nonzero original gain.")
            }
            try source.validateOriginalSource(tolerance: tolerance, remainingSourceDepth: remainingSourceDepth - 1,
                maximumSubdivisionDepth: maximumSubdivisionDepth, maximumAlgebraicDepth: maximumAlgebraicDepth, using: &execution)
            return try OriginalParameterImageMap.interval(interval, gain: parameterGain, offset: offset,
                sourceDomain: source.parameterDomain, usage: &execution)
    }

    /// Requires the enclosing caller's original relation admission; performs no source revalidation.
    package func sourceParameterBoundsAssumingValidatedOriginalRelation<B: ExactScalarAdmission & ~Copyable>(
        over interval: ScalarInterval, usage: inout B) throws -> ScalarInterval {
        try OriginalParameterImageMap.interval(interval, gain: parameterGain, offset: offset,
            sourceDomain: source.parameterDomain, usage: &usage)
    }

    /// The exact inverse ratio image, including represented boundary identities.
    public func foreignParameterBounds(fromSourceInterval interval: ScalarInterval,
        tolerance: ModelingTolerance) throws -> ScalarInterval {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try foreignParameterBounds(fromSourceInterval: interval, tolerance: tolerance, using: &execution)
    }

    public func foreignParameterBounds(fromSourceInterval interval: ScalarInterval,
        tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws -> ScalarInterval {
        try execution.consumeWork(1)
        try validate(tolerance: tolerance, using: &execution)
        return try OriginalParameterImageMap.inverseInterval(interval, gain: parameterGain, offset: offset, using:&execution)
    }

    public func foreignParameter(fromSourceParameter parameter: Double,
        tolerance: ModelingTolerance) throws -> Double {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try foreignParameter(fromSourceParameter: parameter, tolerance: tolerance, using: &execution)
    }

    public func foreignParameter(fromSourceParameter parameter: Double,
        tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws -> Double {
        try execution.consumeWork(1)
        let bounds = try foreignParameterBounds(fromSourceInterval:
            ScalarInterval(lower: parameter, upper: parameter), tolerance: tolerance, using: &execution)
        guard bounds.lower == bounds.upper else {
            // FIXME(INCOMPLETE_IMPLEMENTATION): Exact trim publication for a
            // nonrepresentable foreign endpoint needs a retained native-boundary
            // chart. Exchange must not publish a rounded inverse as that chart.
            throw KernelError(phase: .geometry, code: .unsupportedCapability, tolerance: tolerance,
                message: "Original foreign parameter is not exactly representable as a scalar endpoint.")
        }
        return bounds.lower
    }

    package func originalInterval<A: ExactScalarAdmission & ~Copyable>(_ interval: ScalarInterval, using execution: inout A) throws -> ScalarInterval {
        try OriginalParameterImageMap.interval(interval, gain: parameterGain, offset: offset,
            sourceDomain: source.parameterDomain, using: &execution)
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
