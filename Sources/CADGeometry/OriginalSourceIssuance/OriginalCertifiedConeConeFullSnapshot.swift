import CADCore

/// Complete original full branch and its two exact cardinal contact parameters.
public struct OriginalCertifiedConeConeFullSnapshot: Sendable {
    public let original: CertifiedConeConeIntersectionCurve
    public let referenceField: OriginalPhysicalAngleScalarDomain
    public let parameterizedField: OriginalPhysicalAngleScalarDomain
    public let referenceSine: OriginalPhysicalAngleValue
    public let referenceCosine: OriginalPhysicalAngleValue
    public let parameterizedSine: OriginalPhysicalAngleValue
    public let parameterizedCosine: OriginalPhysicalAngleValue
    public let phaseField: OriginalPiScalarDomain
    public let parameters: [OriginalPiValue]
    public let proofDepth: ExactScalarDepth

    public func admitProof<A: ExactScalarAdmission & ~Copyable>(using a: inout A) throws {
        try a.checkpoint(); try a.admitDepth(value: proofDepth.value, coefficient: proofDepth.coefficient)
        _ = try referenceField.importing(referenceSine, using: &a)
        _ = try referenceField.importing(referenceCosine, using: &a)
        _ = try parameterizedField.importing(parameterizedSine, using: &a)
        _ = try parameterizedField.importing(parameterizedCosine, using: &a)
        for t in parameters { try a.consumeWork(1); _ = try phaseField.importing(t, using: &a) }
        try a.checkpoint()
    }
    /// Encloses source-owned expressions; bounds do not define their equality.
    package func bounds<A: ExactScalarAdmission & ~Copyable>(phaseOrdinal: Int,
        tolerance: ModelingTolerance, using a: inout A)
        throws -> (parameterizedSlant: OutwardScalarInterval, referenceSlant: OutwardScalarInterval,
            planeU: OutwardScalarInterval, planeV: OutwardScalarInterval) {
        try admitProof(using: &a)
        guard phaseOrdinal >= 0, phaseOrdinal < 2 else { throw OriginalSourceIssuanceFailure.invalidChart }
        let alpha = try CertifiedRotationTrigonometry.evaluate(.exact(referenceField.originalRadians),
            tolerance: tolerance, using: &a)
        let beta = try CertifiedRotationTrigonometry.evaluate(.exact(parameterizedField.originalRadians),
            tolerance: tolerance, using: &a)
        let sign = original.componentKind == .positiveFullBranch ? 1.0 : -1.0
        let tau = phaseOrdinal == 0 ? 1.0 : -1.0
        let ac = alpha.cosine * beta.cosine
        let denominator = ac + .exact(sign * tau) * alpha.sine * beta.sine
        guard denominator.lower > 0,
            let slant = (.exact(sign * 4) * alpha.sine).divided(by: denominator),
            let z = (.exact(4) * ac).divided(by: denominator),
            let reference = z.divided(by: alpha.cosine) else { throw ExactScalarFailure.unresolved }
        let v = -(beta.cosine * slant)
        try a.checkpoint(); return (slant, reference, z, v)
    }
}
