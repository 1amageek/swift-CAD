import CADCore

/// Retains the original cyclic law without rounding a foreign period.
public struct OriginalParameterPeriodicTranslation: Hashable, Sendable {
    public let originalSourcePeriod: Double
    public let originalTurnCount: Int64
    public let parameterGain: OriginalParameterGain

    public init(originalSourcePeriod: Double, originalTurnCount: Int64,
        parameterGain: OriginalParameterGain) throws {
        self.originalSourcePeriod = originalSourcePeriod
        self.originalTurnCount = originalTurnCount
        self.parameterGain = parameterGain
        try validate()
    }

    public func validate() throws {
        guard originalSourcePeriod.isFinite, originalSourcePeriod > 0 else {
            throw GeometryConversionError.invalidInput("An original periodic translation needs a finite positive native period.")
        }
        try parameterGain.validate()
    }

    public func nativeDisplacement<B: ExactScalarAdmission & ~Copyable>(usage: inout B) throws -> ExactRationalCoefficient {
        try validate(); try CurrentTaskCancellationChecker().checkCancellation(); try usage.consumeWork(1)
        guard originalTurnCount != 0 else { return .zero }
        let magnitude = originalTurnCount.magnitude
        try usage.retainStorage(bytes: exactScalarPayloadBytes(count: 3, of: UInt32.self))
        let low = UInt32(truncatingIfNeeded: magnitude)
        let high = UInt32(magnitude >> 32)
        let words: [UInt32] = high == 0 ? [low] : [low, high]
        let turns = try ExactRationalCoefficient(canonicalSign: originalTurnCount < 0 ? -1 : 1,
            numeratorWords: words, denominatorWords: [1], usage: &usage)
        return try ExactRationalCoefficient.originalDouble(originalSourcePeriod, usage: &usage)
            .multiplied(by: turns, usage: &usage)
    }

    public func foreignDisplacement<B: ExactScalarAdmission & ~Copyable>(usage: inout B) throws -> ExactRationalCoefficient {
        try nativeDisplacement(usage: &usage)
            .divided(by: parameterGain.exactCoefficient(usage: &usage), usage: &usage)
    }

    public func translatedForeignEndpoint<B: ExactScalarAdmission & ~Copyable>(
        _ original: ExactRationalCoefficient, usage: inout B) throws -> ExactRationalCoefficient {
        try original.adding(foreignDisplacement(usage: &usage), usage: &usage)
    }

    public func translatedNativeEndpoint<B: ExactScalarAdmission & ~Copyable>(
        _ original: ExactRationalCoefficient, usage: inout B) throws -> ExactRationalCoefficient {
        try original.adding(nativeDisplacement(usage: &usage), usage: &usage)
    }

    public func nativeImage<B: ExactScalarAdmission & ~Copyable>(of foreign: ExactRationalCoefficient,
        originalNativeOffset: Double, usage: inout B) throws -> ExactRationalCoefficient {
        try validate()
        return try foreign.multiplied(by: parameterGain.exactCoefficient(usage: &usage), usage: &usage)
            .adding(.originalDouble(originalNativeOffset, usage: &usage), usage: &usage)
    }

    public func foreignImage<B: ExactScalarAdmission & ~Copyable>(of native: ExactRationalCoefficient,
        originalNativeOffset: Double, usage: inout B) throws -> ExactRationalCoefficient {
        try validate()
        return try native.subtracting(.originalDouble(originalNativeOffset, usage: &usage), usage: &usage)
            .divided(by: parameterGain.exactCoefficient(usage: &usage), usage: &usage)
    }
}

#if !hasFeature(Embedded)
extension OriginalParameterPeriodicTranslation: Codable {
    private enum CodingKeys: String, CodingKey {
        case originalSourcePeriod, originalTurnCount, parameterGain
    }
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys([.originalSourcePeriod, .originalTurnCount, .parameterGain], in: decoder)
        try self.init(originalSourcePeriod: container.decode(Double.self, forKey: .originalSourcePeriod),
            originalTurnCount: container.decode(Int64.self, forKey: .originalTurnCount),
            parameterGain: container.decode(OriginalParameterGain.self, forKey: .parameterGain))
    }
    public func encode(to encoder: Encoder) throws {
        try validate()
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(originalSourcePeriod, forKey: .originalSourcePeriod)
        try container.encode(originalTurnCount, forKey: .originalTurnCount)
        try container.encode(parameterGain, forKey: .parameterGain)
    }
}
#endif
