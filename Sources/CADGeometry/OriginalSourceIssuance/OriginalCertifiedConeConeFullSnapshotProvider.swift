import CADCore

/// Proves the original pair/root correspondence before any public localization.
public struct OriginalCertifiedConeConeFullSnapshotProvider: OriginalSourceSnapshotting {
    public let reference: OriginalPhysicalAngleScalarDomain
    public let parameterized: OriginalPhysicalAngleScalarDomain
    public let phase: OriginalPiScalarDomain
    public let tolerance: ModelingTolerance
    public init(reference: OriginalPhysicalAngleScalarDomain, parameterized: OriginalPhysicalAngleScalarDomain,
        phase: OriginalPiScalarDomain, tolerance: ModelingTolerance) {
        self.reference = reference; self.parameterized = parameterized; self.phase = phase; self.tolerance = tolerance
    }
    public static func supports(_ input: Curve3D) -> Bool {
        guard case .certifiedIntersection(.coneCone(let original)) = input,
            case .analytic(.cone(let apex, let axis, _)) = original.referenceSurface,
            case .analytic(.cone(let secondApex, let secondAxis, _)) = original.parameterizedSurface,
            apex == .origin, axis == .unitZ, secondApex == .init(x: 0, y: 0, z: 4), secondAxis == .unitY,
            original.lowerAngle == 0, original.upperAngle == 2 * Double.pi else { return false }
        switch original.componentKind { case .negativeFullBranch, .positiveFullBranch: return true; default: return false }
    }
    public func snapshot<A: ExactScalarAdmission & ~Copyable>(_ input: borrowing Curve3D,
        limits: OriginalSourceIssuanceLimits, using a: inout A)
        throws(OriginalSourceIssuanceFailure) -> OriginalSourceSnapshot<OriginalCertifiedConeConeFullSnapshot> {
        let input = copy input
        do {
            return try OriginalSourceProofAdmission<A>.withBorrow(&a) { a in
                try a.checkpoint(); try a.consumeWork(1)
                guard Self.supports(input), case .certifiedIntersection(.coneCone(let original)) = input,
                    case .analytic(.cone(_, _, let alpha)) = original.referenceSurface,
                    case .analytic(.cone(_, _, let beta)) = original.parameterizedSurface else {
                    throw OriginalSourceIssuanceFailure.unsupportedRepresentation
                }
                guard limits.remainingSourceDepth >= 1 else { throw OriginalSourceIssuanceFailure.sourceDepthLimit }
                guard reference.originalRadians == alpha, parameterized.originalRadians == beta else {
                    throw OriginalSourceIssuanceFailure.foreignBinding
                }
                try original.validate(tolerance: tolerance)
                let sa = try reference.sine(using: &a), ca = try reference.cosine(using: &a)
                let sb = try parameterized.sine(using: &a), cb = try parameterized.cosine(using: &a)
                try Self.admitPhysicalBounds(reference: reference, referenceSine: sa, referenceCosine: ca,
                    parameterized: parameterized, parameterizedSine: sb, parameterizedCosine: cb, using: &a)
                // q >= .89^2-.36^2 > 0, k=-16*sa^2 < 0. Thus D>0,
                // both selected roots are nonzero and lie strictly between -4/4.
                // Reference Z=4-sb*lambda*cos(theta) is consequently positive.
                // X=-sb*lambda*sin(theta) vanishes exactly at the cardinal phases.
                let pi = try phase.pi(using: &a), zero = try phase.integer(0, using: &a)
                let b = try phase.binary64(exactly: 2 * Double.pi, using: &a)
                let twoPi = try phase.multiplying(phase.integer(2, using: &a), pi, using: &a)
                guard try phase.compare(pi, b, using: &a) == .less,
                    try phase.compare(b, twoPi, using: &a) == .less else { throw OriginalSourceIssuanceFailure.invalidSource }
                let t = try phase.dividing(pi, b, using: &a)
                try a.retainStorage(bytes: exactScalarPayloadBytes(count: 2, of: OriginalPiValue.self))
                let parameters = [zero, t]
                // At tau=+1/-1, q=(ca*cb-sa*sb)(ca*cb+sa*sb) and
                // sqrt(D)=4*sa*ca*cb. Positive denominators select the declared
                // root as +/-4*sa/(ca*cb +/- tau*sa*sb), without a mixed field.
                let depth = try a.depth
                try a.retainStorage(bytes: exactScalarPayloadBytes(count: 1, of: OriginalCertifiedConeConeFullSnapshot.self))
                let snapshot = OriginalCertifiedConeConeFullSnapshot(original: original, referenceField: reference,
                    parameterizedField: parameterized, referenceSine: sa, referenceCosine: ca,
                    parameterizedSine: sb, parameterizedCosine: cb, phaseField: phase,
                    parameters: parameters, proofDepth: depth)
                try a.checkpoint(); return .init(original: snapshot, sourceDepth: 1)
            }
        } catch { throw .init(preserving: error) }
    }
    static func admitPhysicalBounds<A: ExactScalarAdmission & ~Copyable>(reference: OriginalPhysicalAngleScalarDomain,
        referenceSine: OriginalPhysicalAngleValue, referenceCosine: OriginalPhysicalAngleValue,
        parameterized: OriginalPhysicalAngleScalarDomain, parameterizedSine: OriginalPhysicalAngleValue,
        parameterizedCosine: OriginalPhysicalAngleValue, using a: inout A) throws {
        try enclosed(referenceSine, field: reference, lower: 44, upper: 45, using: &a)
        try enclosed(referenceCosine, field: reference, lower: 89, upper: 90, using: &a)
        try enclosed(parameterizedSine, field: parameterized, lower: 35, upper: 36, using: &a)
        try enclosed(parameterizedCosine, field: parameterized, lower: 93, upper: 94, using: &a)
    }
    private static func enclosed<A: ExactScalarAdmission & ~Copyable>(_ value: OriginalPhysicalAngleValue,
        field: OriginalPhysicalAngleScalarDomain, lower: Int, upper: Int, using a: inout A) throws {
        let hundred = try field.integer(100, using: &a)
        let lo = try field.dividing(field.integer(lower, using: &a), hundred, using: &a)
        let hi = try field.dividing(field.integer(upper, using: &a), hundred, using: &a)
        guard try field.compare(lo, value, using: &a) == .less,
            try field.compare(value, hi, using: &a) == .less else { throw OriginalSourceIssuanceFailure.unsupportedRepresentation }
    }
}
