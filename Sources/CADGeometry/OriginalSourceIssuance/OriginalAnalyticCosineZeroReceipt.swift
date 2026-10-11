#if ORIGINAL_SOURCE_ISOLATED_VERIFICATION
import L0
import L1
#endif

/// Whole supported phase-window theorem retaining the original law and all its zeros.
public struct OriginalAnalyticCosineZeroReceipt<S: OriginalAnalyticCoordinateReading,
    F: OriginalPiGenerating>: Sendable {
    public let law: OriginalAnalyticCoordinateLawReceipt<S,F>
    public let supportLower: F.Value
    public let supportUpper: F.Value
    public let gain: F.Value
    public let offset: F.Value
    public let phaseLower: F.Value
    public let phaseUpper: F.Value
    public let outsideLowerPhase: F.Value
    public let outsideUpperPhase: F.Value
    public let labelPeriod: F.Value
    /// All and only the supported zeros, ordered by the original authored parameter.
    public let roots: [OriginalAnalyticCosineZeroRoot<F.Value>]
    public let proofDepth: ExactScalarDepth

    init(law: OriginalAnalyticCoordinateLawReceipt<S,F>, supportLower: F.Value,
        supportUpper: F.Value, gain: F.Value, offset: F.Value, phaseLower: F.Value,
        phaseUpper: F.Value, outsideLowerPhase: F.Value, outsideUpperPhase: F.Value,
        labelPeriod: F.Value, roots: [OriginalAnalyticCosineZeroRoot<F.Value>],
        proofDepth: ExactScalarDepth) {
        self.law = law; self.supportLower = supportLower; self.supportUpper = supportUpper
        self.gain = gain; self.offset = offset; self.phaseLower = phaseLower; self.phaseUpper = phaseUpper
        self.outsideLowerPhase = outsideLowerPhase; self.outsideUpperPhase = outsideUpperPhase
        self.labelPeriod = labelPeriod; self.roots = roots; self.proofDepth = proofDepth
    }

    /// Readmits the retained theorem and every coefficient without decomposing roots again.
    public func admitProof<A: ExactScalarAdmission & ~Copyable>(
        limits: OriginalSourceIssuanceLimits, using admission: inout A
    ) throws(OriginalSourceIssuanceFailure) {
        do {
            try admission.checkpoint(); try law.source.require(limits)
            try admission.admitDepth(value: proofDepth.value, coefficient: proofDepth.coefficient)
            try law.admitProof(limits: limits, using: &admission)
            for polynomial in law.position {
                try admission.consumeWork(1)
                try admission.admitDepth(value: polynomial.depth.value, coefficient: polynomial.depth.coefficient)
                for term in polynomial.terms {
                    try admission.consumeWork(1)
                    _ = try law.field.sign(of: term.coefficient, using: &admission)
                }
            }
            for period in law.periods {
                try admission.consumeWork(1); try period.source.require(limits)
                _ = try law.field.sign(of: period.lower, using: &admission)
                _ = try law.field.sign(of: period.upper, using: &admission)
            }
            try admission.retainStorage(bytes: exactScalarPayloadBytes(count: 9, of: F.Value.self))
            for value in [supportLower, supportUpper, gain, offset, phaseLower, phaseUpper,
                outsideLowerPhase, outsideUpperPhase, labelPeriod] {
                try admission.consumeWork(1)
                _ = try law.field.sign(of: value, using: &admission)
            }
            for root in roots {
                try admission.consumeWork(1)
                _ = try law.field.sign(of: root.parameter, using: &admission)
                _ = try law.field.sign(of: root.phase, using: &admission)
                _ = try law.field.sign(of: root.sine, using: &admission)
                _ = try law.field.sign(of: root.childLabel, using: &admission)
                for value in root.position { try admission.consumeWork(1); _ = try law.field.sign(of: value, using: &admission) }
                for value in root.derivative { try admission.consumeWork(1); _ = try law.field.sign(of: value, using: &admission) }
            }
            try admission.checkpoint()
        } catch { throw .init(preserving: error) }
    }
}
