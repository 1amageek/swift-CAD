import CADCore

/// Exact selected source-pair root, with the original intrinsic cylinder traversal.
public struct OriginalCertifiedCoaxialConeCylinderSnapshot: Sendable {
    public let original: CertifiedConeCylinderIntersectionCurve
    public let field: OriginalPhysicalAngleScalarDomain
    public let height: OriginalPhysicalAngleValue
    public let coneSlant: OriginalPhysicalAngleValue
    public let labelPeriod: OriginalPhysicalAngleValue
    public let conePhaseOffset: OriginalPhysicalAngleValue
    public let proofDepth: ExactScalarDepth

    init(original: CertifiedConeCylinderIntersectionCurve, field: OriginalPhysicalAngleScalarDomain,
        height: OriginalPhysicalAngleValue, coneSlant: OriginalPhysicalAngleValue,
        labelPeriod: OriginalPhysicalAngleValue, conePhaseOffset: OriginalPhysicalAngleValue,
        proofDepth: ExactScalarDepth) {
        self.original=original; self.field=field; self.height=height
        self.coneSlant=coneSlant; self.labelPeriod=labelPeriod
        self.conePhaseOffset=conePhaseOffset; self.proofDepth=proofDepth
    }
}

extension OriginalCertifiedCoaxialConeCylinderSnapshot {
    /// On the entire authored T support [0,1], cos(2*pi*T) has exactly these zeros.
    /// The cylinder's intrinsic label, rather than a rounded physical period,
    /// establishes this theorem for the declared planeY0 source pair.
    public func planeRoot<A: ExactScalarAdmission & ~Copyable>(at index: Int, using a: inout A)
        throws -> OriginalPhysicalAngleValue {
        try a.checkpoint()
        guard index == 0 || index == 1 else { throw OriginalSourceIssuanceFailure.invalidChart }
        return try field.dividing(field.integer(index == 0 ? 1 : 3, using: &a),
            field.integer(4, using: &a), using: &a)
    }

    /// Original parent-cylinder label law; the DI consumer admits the integer index.
    public func cylinderLabel<A: ExactScalarAdmission & ~Copyable>(parameter: OriginalPhysicalAngleValue,
        cycle: OriginalPhysicalAngleValue, using a: inout A) throws -> OriginalPhysicalAngleValue {
        try field.multiplying(labelPeriod, field.adding(parameter, cycle, using: &a), using: &a)
    }

    /// Original parent-cone label law, including the selected negative-slant phase.
    public func coneLabel<A: ExactScalarAdmission & ~Copyable>(parameter: OriginalPhysicalAngleValue,
        cycle: OriginalPhysicalAngleValue, using a: inout A) throws -> OriginalPhysicalAngleValue {
        try field.adding(cylinderLabel(parameter: parameter, cycle: cycle, using: &a),
            conePhaseOffset, using: &a)
    }
}
