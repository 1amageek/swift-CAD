import CADCore

/// Source-owned exact critical arc for the migrated bounded R2 construction.
public struct OriginalCertifiedSphereConeBoundedArc: Sendable {
    public let original: CertifiedSphereConeIntersectionCurve
    public let field: OriginalPhysicalAngleScalarDomain
    /// L is the unique asin(criticalSine) in (0, pi/2); U is pi-L.
    public let criticalSine: OriginalPhysicalAngleValue
    public let proofDepth: ExactScalarDepth

    private init(original: CertifiedSphereConeIntersectionCurve,
        field: OriginalPhysicalAngleScalarDomain, criticalSine: OriginalPhysicalAngleValue,
        proofDepth: ExactScalarDepth) {
        self.original = original; self.field = field
        self.criticalSine = criticalSine; self.proofDepth = proofDepth
    }

    static func issue<A: ExactScalarAdmission & ~Copyable>(
        original: CertifiedSphereConeIntersectionCurve, field f: OriginalPhysicalAngleScalarDomain,
        using a: inout A) throws -> Self {
        try a.checkpoint(); try a.consumeWork(1)
        guard original.componentKind == .boundedAngularInterval,
            original.sphereSurface == .analytic(.sphere(center: .origin, radius: 2)),
            case .analytic(.cone(let apex, let axis, let angle)) = original.coneSurface,
            apex == .init(x: 2, y: 0, z: -4), axis == .unitZ, angle == f.originalRadians,
            original.lowerAngle > 0.4, original.lowerAngle < 0.6,
            original.upperAngle > 2.5, original.upperAngle < 2.8 else {
            throw OriginalSourceIssuanceFailure.unsupportedRepresentation
        }
        let s = try f.sine(using: &a), c = try f.cosine(using: &a)
        let one = try f.integer(1, using: &a), two = try f.integer(2, using: &a)
        let k = try f.dividing(f.multiplying(two, f.subtracting(one, c, using: &a), using: &a), s, using: &a)
        guard try f.sign(of: s, using: &a) == .positive,
            try f.sign(of: c, using: &a) == .positive,
            try f.sign(of: k, using: &a) == .positive,
            try f.compare(k, one, using: &a) == .less else {
            throw OriginalSourceIssuanceFailure.invalidSource
        }
        // On (0,pi), sin(theta)>=k exactly on [asin(k),pi-asin(k)].
        // There b=2*s*sin(theta)+4*c>=4 and D=b*b-16>=0.
        // Both roots of lambda*lambda-2*b*lambda+16 are positive.
        // The symmetric normalized arc has cos(theta)=0 iff cos(2*pi*T)=0.
        let depth = try ExactScalarDepth(value: k.depth.value, coefficient: k.depth.coefficient)
        try a.admitDepth(value: depth.value, coefficient: depth.coefficient)
        try a.retainStorage(bytes: exactScalarPayloadBytes(count: 1, of: Self.self))
        let result = Self(original: original, field: f, criticalSine: k, proofDepth: depth)
        try a.checkpoint(); return result
    }
}
