import CADCore
import CADGeometry
import CADTopology

/// Proves numeric cyclic representatives against the complete retained source law.
struct IndependentCurvePeriodicTrimResolver {
    func selection(first: Double, last: Double, increasing: Bool, on curve: Curve3D,
                   tolerance: ModelingTolerance, usage: IndependentShapeExchangeOwner, using execution: inout OriginalQueryExecution) throws -> (trim: CurveTrim, traversalSource: Curve3D?) {
        guard execution.budget === usage.originalBudget else {
            throw IndependentShapeExchangeError.invalidAssociation("Periodic trim requires its original exchange invocation.")
        }
        guard increasing ? last <= first : last >= first else {
            return (CurveTrim(startParameter: first, endParameter: last), nil)
        }
        guard let authority = try originalAuthority(curve, usage: usage, using: &execution, depth: 0) else {
            throw IndependentShapeExchangeError.invalidAssociation("Original directed trim has no positive periodic authority.")
        }
        let originalGain = try authority.gain.exactCoefficient(usage: &execution)
        let period = try ExactRationalCoefficient.originalDouble(authority.period, usage: &execution)
            .divided(by: originalGain.isNegative ? originalGain.negated : originalGain, usage: &execution)
        let firstValue = try ExactRationalCoefficient.originalDouble(first, usage: &execution)
        let lastValue = try ExactRationalCoefficient.originalDouble(last, usage: &execution)
        let distance = increasing ? try firstValue.subtracting(lastValue, usage: &execution)
            : try lastValue.subtracting(firstValue, usage: &execution)
        let positiveNativeTurns = increasing == !originalGain.isNegative
        func translated(_ count: Int64, usage: IndependentShapeExchangeOwner, using execution: inout OriginalQueryExecution) throws -> OriginalParameterPeriodicTranslation {
            try execution.consumeWork(1)
            return try OriginalParameterPeriodicTranslation(originalSourcePeriod: authority.period,
                originalTurnCount: positiveNativeTurns ? count : -count, parameterGain: authority.gain)
        }
        func magnitude(_ count: Int64, usage: IndependentShapeExchangeOwner, using execution: inout OriginalQueryExecution) throws -> ExactRationalCoefficient {
            let displacement = try translated(count, usage: usage, using: &execution).foreignDisplacement(usage: &execution)
            return displacement.isNegative ? displacement.negated : displacement
        }
        var lower: Int64 = 0, upper = Int64.max
        guard try magnitude(upper, usage: usage, using: &execution).subtracting(distance, usage: &execution).isPositive else {
            throw IndependentShapeExchangeError.resourceLimitExceeded("Original periodic traversal exceeds the retained integer turn count.")
        }
        while upper - lower > 1 {
            let middle = lower + (upper - lower) / 2
            if try magnitude(middle, usage: usage, using: &execution).subtracting(distance, usage: &execution).isPositive { upper = middle }
            else { lower = middle }
        }
        let turnMagnitude = upper
        let shift = try magnitude(turnMagnitude, usage: usage, using: &execution)
        let directed = try shift.subtracting(distance, usage: &execution)
        let predecessor = try directed.subtracting(period, usage: &execution)
        guard directed.isPositive, !predecessor.isPositive else {
            throw IndependentShapeExchangeError.invalidAssociation("Original periodic representative has an unresolved traversal count.")
        }
        let endpoint = increasing ? try lastValue.adding(shift, usage: &execution)
            : try lastValue.subtracting(shift, usage: &execution)
        let interval = try endpoint.outwardInterval(usage: &execution)
        for candidate in [interval.lower, interval.upper] {
            if try endpoint.subtracting(.originalDouble(candidate, usage: &execution), usage: &execution).isZero {
                return (CurveTrim(startParameter: first, endParameter: candidate), nil)
            }
        }
        let translation = try translated(turnMagnitude, usage: usage, using: &execution)
        let chart = try OriginalPeriodicCurveTraversal.normalized(source: curve, originalStart: first, originalEnd: last,
            translation: translation, remainingSourceDepth: usage.limits.maximumNesting,
            maximumSubdivisionDepth: usage.limits.maximumCurveSubdivisionDepth, tolerance: tolerance, usage: &execution)
        return (CurveTrim(startParameter: 0, endParameter: 1), .parameterImage(chart))
    }

    private func originalAuthority(_ curve: Curve3D, usage: IndependentShapeExchangeOwner, using execution: inout OriginalQueryExecution,
                                   depth: Int) throws -> (period: Double, gain: OriginalParameterGain)? {
        guard depth < usage.limits.maximumNesting else {
            throw IndependentShapeExchangeError.resourceLimitExceeded("Original periodic image depth.")
        }
        try execution.admitSourceDepth(depth)
        try execution.chargeSource(records: 1, work: 1)
        switch curve {
        case .parameterImage(let image):
            guard let native = try originalAuthority(image.source, usage: usage, using: &execution, depth: depth + 1) else { return nil }
            return (native.period, try OriginalParameterGain.originalProduct(factors: [native.gain, image.parameterGain], usage: &execution))
        case .originalAffineWord(let image): return try originalAuthority(image.source, usage: usage, using: &execution, depth: depth + 1)
        case .affineImage(let image): return try originalAuthority(image.source, usage: usage, using: &execution, depth: depth + 1)
        case .rigidImage(let image): return try originalAuthority(image.source, usage: usage, using: &execution, depth: depth + 1)
        default:
            guard case .periodic(let period) = curve.parameterDomain else { return nil }
            return (period, .binary(1))
        }
    }
}
