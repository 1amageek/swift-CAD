import CADCore

/// Symbolic transport between intrinsic labels and authored physical radians.
public enum OriginalAngularParameterTransport: Hashable, Sendable {
    case intrinsic
    case physicalRadians(gain: ExactRationalCoefficient, offset: ExactRationalCoefficient)
    case physicalRadianArc(start: ExactRationalCoefficient, end: ExactRationalCoefficient, additionalTurns: Int)

    package func orientationSign<B: ExactScalarAdmission & ~Copyable>(usage: inout B) throws -> Int {
        switch self {
        case .intrinsic: return 1
        case .physicalRadians(let gain, _): return gain.isNegative ? -1 : 1
        case .physicalRadianArc(let start, let end, let turns):
            guard turns != 0 || start != end else {
                throw GeometryConversionError.invalidInput("An original physical arc requires distinct phase endpoints or a nonzero full-turn count.")
            }
            let gain = try arcGain(usage: &usage)
            guard gain.lower > 0 || gain.upper < 0 else {
                throw GeometryConversionError.resourceLimitExceeded("Original physical arc direction is not isolated.")
            }
            return gain.lower > 0 ? 1 : -1
        }
    }

    package var isNormalizedArc: Bool { if case .physicalRadianArc = self { return true }; return false }

    private func arcGain<B: ExactScalarAdmission & ~Copyable>(usage: inout B) throws -> OutwardScalarInterval {
        guard case .physicalRadianArc(let start, let end, let turns) = self else {
            throw GeometryConversionError.invalidInput("Original angular source is not a normalized physical arc.")
        }
        let magnitude: ExactRationalCoefficient
        if turns >= 0 { magnitude = try .natural(turns, usage: &usage) }
        else { magnitude = try ExactRationalCoefficient.natural(-(turns + 1), usage: &usage).adding(.one, usage: &usage).negated }
        let difference = try end.subtracting(start, usage: &usage).outwardInterval(usage: &usage)
        if turns == 0 { return difference }
        let factor = try magnitude.adding(magnitude, usage: &usage).outwardInterval(usage: &usage)
        return difference + CanonicalSphereAngularPhase.piBounds * factor
    }

    package var isIntrinsic: Bool { if case .intrinsic = self { return true }; return false }

    package func validate<B: ExactScalarAdmission & ~Copyable>(usage: inout B) throws {
        try usage.consumeWork(1)
        if case .physicalRadianArc = self { _ = try orientationSign(usage: &usage) }
        if case .physicalRadians(let gain, _) = self, gain.isZero {
            throw GeometryConversionError.invalidInput("Original physical-angle transport requires a nonzero gain.")
        }
    }

    package func phaseAndGain<A: ExactScalarAdmission & ~Copyable>(over range: ScalarInterval, using usage: inout A) throws -> (phase: OutwardScalarInterval, gain: OutwardScalarInterval) {
        try validate(usage: &usage)
            switch self {
            case .intrinsic:
                return (.init(lower: range.lower, upper: range.upper), CanonicalSphereAngularPhase.scaleBounds)
            case .physicalRadianArc(let start, let end, _):
                guard range.lower >= 0, range.upper <= 1 else {
                    throw GeometryConversionError.invalidInput("Original physical trim exceeds its normalized domain.")
                }
                let gain = try arcGain(usage: &usage)
                if range.lower == range.upper, range.lower == 0 || range.lower == 1 {
                    return (try (range.lower == 0 ? start : end).outwardInterval(usage: &usage), gain)
                }
                return (try start.outwardInterval(usage: &usage) + gain * .init(lower: range.lower, upper: range.upper), gain)
            case .physicalRadians(let gain, let offset):
                func station(_ value: Double) throws -> OutwardScalarInterval {
                    let original = try ExactRationalCoefficient.originalDouble(value, usage: &usage)
                    return try gain.multiplied(by: original, usage: &usage)
                        .adding(offset, usage: &usage).outwardInterval(usage: &usage)
                }
                return (try station(range.lower).union(station(range.upper)), try gain.outwardInterval(usage: &usage))
            }
    }

    package func harmonic<A: ExactScalarAdmission & ~Copyable>(over range: ScalarInterval, cosine: Bool, using usage: inout A) throws -> (value: OutwardScalarInterval, gain: OutwardScalarInterval) {
        let original = try phaseAndGain(over: range, using: &usage)
        let argument = SurfaceIntervalJet(value: original.phase, derivativeU: .exact(0), derivativeV: .exact(0),
            secondDerivativeUU: .exact(0), secondDerivativeUV: .exact(0), secondDerivativeVV: .exact(0),
            thirdDerivativeUUU: .exact(0), thirdDerivativeUUV: .exact(0), thirdDerivativeUVV: .exact(0), thirdDerivativeVVV: .exact(0))
        let result: SurfaceIntervalJet
        switch self {
        case .intrinsic: result = try CanonicalSphereAngularPhase.harmonic(of: argument, cosine: cosine, using: &usage)
        case .physicalRadians, .physicalRadianArc:
            result = try cosine ? .cosine(of: argument, using: &usage) : .sine(of: argument, using: &usage)
        }
        return (result.value, original.gain)
    }
}

extension OriginalAngularParameterTransport {
    /// The authored sphere latitude branch is checked in its original coordinate
    /// meaning. Certified containment failure never becomes a clipped latitude.
    package func requireSphereLatitude<A: ExactScalarAdmission & ~Copyable>(over range: ScalarInterval, using usage: inout A) throws {
        guard range.lower.isFinite,range.upper.isFinite,range.lower <= range.upper else {
            throw GeometryConversionError.invalidInput("Original latitude query requires finite ordered endpoints.")
        }
        if isIntrinsic {
            guard range.lower >= -Double.pi * 0.5,range.upper <= Double.pi * 0.5 else {
                throw GeometryConversionError.invalidInput("Original intrinsic latitude exceeds its closed source support.")
            }
            return
        }
        let phase: OutwardScalarInterval
        if case .physicalRadianArc(let start,_,_) = self {
            guard range.lower >= 0,range.upper <= 1 else {
                throw GeometryConversionError.invalidInput("Original normalized latitude exceeds its authored unit interval.")
            }
            // Preserve full turns for latitude support even when the endpoint harmonic repeats.
            phase = try start.outwardInterval(usage:&usage) + arcGain(usage:&usage) * .init(lower:range.lower,upper:range.upper)
        } else { phase = try phaseAndGain(over:range,using:&usage).phase }
        let halfPi = CanonicalSphereAngularPhase.piBounds * .exact(0.5)
        guard phase.lower >= -halfPi.lower,phase.upper <= halfPi.lower else {
            if phase.upper < -halfPi.upper || phase.lower > halfPi.upper {
                throw GeometryConversionError.invalidInput("Original physical latitude exceeds its mathematical pole endpoints.")
            }
            throw GeometryConversionError.resourceLimitExceeded("Original physical latitude support is not separated from a pole endpoint.")
        }
    }
}
