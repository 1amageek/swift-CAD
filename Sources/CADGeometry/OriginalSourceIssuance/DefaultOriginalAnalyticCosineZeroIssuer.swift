#if ORIGINAL_SOURCE_ISOLATED_VERIFICATION
import L0
import L1
#endif

/// Exact finite-window reduction of the actual issued physical C/S coordinate law.
public struct DefaultOriginalAnalyticCosineZeroIssuer<S: OriginalAnalyticCoordinateReading,
    F: OriginalPiGenerating>: OriginalAnalyticCosineZeroIssuing {
    public typealias Source = S
    public typealias Field = F
    public init() {}

    public func issue<A: ExactScalarAdmission & ~Copyable>(
        law: borrowing OriginalAnalyticCoordinateLawReceipt<S,F>,
        limits: OriginalSourceIssuanceLimits, using admission: inout A
    ) throws(OriginalSourceIssuanceFailure) -> OriginalAnalyticCosineZeroReceipt<S,F> {
        let law = copy law
        do {
            return try OriginalSourceProofAdmission<A>.withBorrow(&admission) { a in
                try a.checkpoint(); try law.admitProof(limits: limits, using: &a)
                // FIXME(INCOMPLETE_IMPLEMENTATION): The public source issuer supports only
                // finite physical circle C/S laws in the proved window below. General
                // trigonometric families/windows require their complete zero-set authority.
                guard law.source.original.coordinateKind == .circle,
                    law.axes.count == 1, law.functions.count == 2,
                    law.position.count == 3, law.polynomials.variableCount == 2,
                    let lower = law.axes[0].lower, let upper = law.axes[0].upper,
                    case .physicalCosine(axis: 0, gain: let gain, offset: let offset) = law.functions[0],
                    case .physicalSine(axis: 0, gain: let sineGain, offset: let sineOffset) = law.functions[1]
                else { throw OriginalSourceIssuanceFailure.unsupportedRepresentation }
                let f = law.field, ring = law.polynomials
                guard try f.compare(gain, sineGain, using: &a) == .equal,
                    try f.compare(offset, sineOffset, using: &a) == .equal,
                    try f.compare(lower, upper, using: &a) != .greater,
                    try f.sign(of: gain, using: &a) != .zero
                else { throw OriginalSourceIssuanceFailure.invalidSource }
                let zero = try f.integer(0, using: &a), one = try f.integer(1, using: &a)
                let two = try f.integer(2, using: &a), three = try f.integer(3, using: &a)
                let four = try f.integer(4, using: &a), five = try f.integer(5, using: &a)
                let pi = try f.pi(using: &a), halfPi = try f.dividing(pi, two, using: &a)
                let outsideLower = try f.negated(halfPi, using: &a)
                let outsideUpper = try f.multiplying(five, halfPi, using: &a)
                let firstPhase = try f.adding(f.multiplying(gain, lower, using: &a), offset, using: &a)
                let lastPhase = try f.adding(f.multiplying(gain, upper, using: &a), offset, using: &a)
                let positive = try f.sign(of: gain, using: &a) == .positive
                let phaseLower = positive ? firstPhase : lastPhase
                let phaseUpper = positive ? lastPhase : firstPhase
                // FIXME(INCOMPLETE_IMPLEMENTATION): This finite source reduction admits
                // only the two possible zeros between the retained outside neighbours.
                // A wider phase image must not publish an empty or partial complete set.
                guard try f.compare(outsideLower, phaseLower, using: &a) == .less,
                    try f.compare(phaseUpper, outsideUpper, using: &a) == .less
                else { throw OriginalSourceIssuanceFailure.unsupportedRepresentation }
                let labelPeriod = try f.binary64(exactly: 2 * Double.pi, using: &a)
                let quarterLabel = try f.dividing(labelPeriod, four, using: &a)
                try a.retainStorage(bytes: exactScalarPayloadBytes(count: 2, of: OriginalAnalyticCosineZeroRoot<F.Value>.self))
                var roots: [OriginalAnalyticCosineZeroRoot<F.Value>] = []; roots.reserveCapacity(2)
                for index in 0..<2 {
                    try a.consumeWork(1)
                    let phase = index == 0 ? halfPi : try f.multiplying(three, halfPi, using: &a)
                    let parameter = try f.dividing(f.subtracting(phase, offset, using: &a), gain, using: &a)
                    if try f.compare(parameter, lower, using: &a) == .less { continue }
                    if try f.compare(parameter, upper, using: &a) == .greater { continue }
                    let sine = index == 0 ? one : try f.negated(one, using: &a)
                    let childLabel = index == 0 ? quarterLabel : try f.multiplying(three, quarterLabel, using: &a)
                    try a.retainStorage(bytes: exactScalarPayloadBytes(count: 2, of: F.Value.self))
                    let coordinates = [zero, sine]
                    try a.retainStorage(bytes: exactScalarPayloadBytes(count: 6, of: F.Value.self))
                    var position: [F.Value] = [], derivative: [F.Value] = []
                    position.reserveCapacity(3); derivative.reserveCapacity(3)
                    let cosineDerivative = try f.negated(f.multiplying(gain, sine, using: &a), using: &a)
                    for polynomial in law.position {
                        try a.consumeWork(1)
                        let point = try ring.evaluated(polynomial, at: coordinates, using: &a)
                        let dc = try ring.evaluated(ring.differentiated(polynomial, in: 0, using: &a), at: coordinates, using: &a)
                        let ds = try ring.evaluated(ring.differentiated(polynomial, in: 1, using: &a), at: coordinates, using: &a)
                        try a.admitDepth(value: point.depth.value, coefficient: point.depth.coefficient)
                        try a.admitDepth(value: dc.depth.value, coefficient: dc.depth.coefficient)
                        try a.admitDepth(value: ds.depth.value, coefficient: ds.depth.coefficient)
                        position.append(point.value)
                        // C'=-gain*S and S'=gain*C=0 at this proved zero.
                        derivative.append(try f.adding(f.multiplying(dc.value, cosineDerivative, using: &a),
                            f.multiplying(ds.value, zero, using: &a), using: &a))
                    }
                    roots.append(.init(parameter: parameter, phase: phase, sine: sine,
                        childLabel: childLabel, position: position, derivative: derivative))
                }
                if roots.count == 2 {
                    try a.consumeWork(1)
                    if try f.compare(roots[0].parameter, roots[1].parameter, using: &a) == .greater { roots.swapAt(0, 1) }
                }
                let depth = try a.depth
                try a.retainStorage(bytes: exactScalarPayloadBytes(count: 1, of: OriginalAnalyticCosineZeroReceipt<S,F>.self))
                let result = OriginalAnalyticCosineZeroReceipt(law: law, supportLower: lower, supportUpper: upper,
                    gain: gain, offset: offset, phaseLower: phaseLower, phaseUpper: phaseUpper,
                    outsideLowerPhase: outsideLower, outsideUpperPhase: outsideUpper,
                    labelPeriod: labelPeriod, roots: roots, proofDepth: depth)
                try a.checkpoint(); return result
            }
        } catch { throw .init(preserving: error) }
    }
}
