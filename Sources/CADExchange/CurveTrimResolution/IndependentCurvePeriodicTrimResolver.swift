import Foundation
import CADCore
import CADGeometry

/// Proves numeric cyclic representatives against the complete retained source law.
struct IndependentCurvePeriodicTrimResolver {
    func selection(first: Double, last: Double, increasing: Bool, on curve: Curve3D,
                   tolerance: ModelingTolerance, usage: inout IndependentShapeExchangeUsage) throws -> (trim: CurveTrim, traversalSource: Curve3D?) {
        guard increasing ? last <= first : last >= first else {
            return (CurveTrim(startParameter: first, endParameter: last), nil)
        }
        guard let authority = try originalAuthority(curve, usage: &usage, depth: 0) else {
            throw IndependentShapeExchangeError.invalidAssociation("Original directed trim has no positive periodic authority.")
        }
        let originalGain = try authority.gain.exactCoefficient(usage: &usage)
        let period = try ExactRationalCoefficient.originalDouble(authority.period, usage: &usage)
            .divided(by: originalGain.isNegative ? originalGain.negated : originalGain, usage: &usage)
        let firstValue = try ExactRationalCoefficient.originalDouble(first, usage: &usage)
        let lastValue = try ExactRationalCoefficient.originalDouble(last, usage: &usage)
        let distance = increasing ? try firstValue.subtracting(lastValue, usage: &usage)
            : try lastValue.subtracting(firstValue, usage: &usage)
        let positiveNativeTurns = increasing == !originalGain.isNegative
        func translated(_ count: Int64, usage: inout IndependentShapeExchangeUsage) throws -> OriginalParameterPeriodicTranslation {
            try usage.charge(work: 1)
            return try OriginalParameterPeriodicTranslation(originalSourcePeriod: authority.period,
                originalTurnCount: positiveNativeTurns ? count : -count, parameterGain: authority.gain)
        }
        func magnitude(_ count: Int64, usage: inout IndependentShapeExchangeUsage) throws -> ExactRationalCoefficient {
            let displacement = try translated(count, usage: &usage).foreignDisplacement(usage: &usage)
            return displacement.isNegative ? displacement.negated : displacement
        }
        var lower: Int64 = 0, upper = Int64.max
        guard try magnitude(upper, usage: &usage).subtracting(distance, usage: &usage).isPositive else {
            throw IndependentShapeExchangeError.resourceLimitExceeded("Original periodic traversal exceeds the retained integer turn count.")
        }
        while upper - lower > 1 {
            let middle = lower + (upper - lower) / 2
            if try magnitude(middle, usage: &usage).subtracting(distance, usage: &usage).isPositive { upper = middle }
            else { lower = middle }
        }
        let turnMagnitude = upper
        let shift = try magnitude(turnMagnitude, usage: &usage)
        let directed = try shift.subtracting(distance, usage: &usage)
        let predecessor = try directed.subtracting(period, usage: &usage)
        guard directed.isPositive, !predecessor.isPositive else {
            throw IndependentShapeExchangeError.invalidAssociation("Original periodic representative has an unresolved traversal count.")
        }
        let endpoint = increasing ? try lastValue.adding(shift, usage: &usage)
            : try lastValue.subtracting(shift, usage: &usage)
        let interval = try endpoint.outwardInterval(usage: &usage)
        for candidate in [interval.lower, interval.upper] {
            if try endpoint.subtracting(.originalDouble(candidate, usage: &usage), usage: &usage).isZero {
                return (CurveTrim(startParameter: first, endParameter: candidate), nil)
            }
        }
        let translation = try translated(turnMagnitude, usage: &usage)
        let chart = try OriginalPeriodicCurveTraversal.normalized(source: curve, originalStart: first, originalEnd: last,
            translation: translation, remainingSourceDepth: usage.limits.maximumNesting,
            maximumSubdivisionDepth: usage.limits.maximumCurveSubdivisionDepth, tolerance: tolerance, usage: &usage)
        return (CurveTrim(startParameter: 0, endParameter: 1), .parameterImage(chart))
    }

    private func originalAuthority(_ curve: Curve3D, usage: inout IndependentShapeExchangeUsage,
                                   depth: Int) throws -> (period: Double, gain: OriginalParameterGain)? {
        guard depth < usage.limits.maximumNesting else {
            throw IndependentShapeExchangeError.resourceLimitExceeded("Original periodic image depth.")
        }
        try usage.visitSourceCell(depth: depth)
        switch curve {
        case .parameterImage(let image):
            guard let native = try originalAuthority(image.source, usage: &usage, depth: depth + 1) else { return nil }
            return (native.period, try OriginalParameterGain.originalProduct(factors: [native.gain, image.parameterGain], usage: &usage))
        case .originalAffineWord(let image): return try originalAuthority(image.source, usage: &usage, depth: depth + 1)
        case .affineImage(let image): return try originalAuthority(image.source, usage: &usage, depth: depth + 1)
        case .rigidImage(let image): return try originalAuthority(image.source, usage: &usage, depth: depth + 1)
        default:
            guard case .periodic(let period) = curve.parameterDomain else { return nil }
            return (period, .binary(1))
        }
    }
}
