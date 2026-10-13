import CADCore

/// Retains the original pair, declared root and authored physical phase unchanged.
public struct OriginalCertifiedSphereConeFullSnapshotProvider: OriginalSourceSnapshotting {
    public let physical: OriginalPhysicalAngleScalarDomain
    public let phaseField: OriginalPiScalarDomain
    public let maximumExtensionLevel: Int
    public let tolerance: ModelingTolerance
    public init(physical: OriginalPhysicalAngleScalarDomain, phaseField: OriginalPiScalarDomain,
        maximumExtensionLevel: Int, tolerance: ModelingTolerance) {
        self.physical = physical; self.phaseField = phaseField
        self.maximumExtensionLevel = maximumExtensionLevel; self.tolerance = tolerance
    }
    public static func supports(_ input: Curve3D) -> Bool {
        guard case .certifiedIntersection(.sphereCone(let curve)) = input,
            curve.sphereSurface == .analytic(.sphere(center: .origin, radius: 3)),
            case .analytic(.cone(let apex, let axis, _)) = curve.coneSurface,
            apex == .init(x: 1, y: 0, z: -4), axis == .unitZ,
            curve.lowerAngle == 0, curve.upperAngle == 2 * Double.pi else { return false }
        switch curve.componentKind { case .negativeFullBranch, .positiveFullBranch: return true; default: return false }
    }
    public func snapshot<A: ExactScalarAdmission & ~Copyable>(_ input: borrowing Curve3D,
        limits: OriginalSourceIssuanceLimits, using a: inout A)
        throws(OriginalSourceIssuanceFailure) -> OriginalSourceSnapshot<OriginalCertifiedSphereConeFullSnapshot> {
        let input = copy input
        do {
            try a.checkpoint(); try a.consumeWork(1)
            guard Self.supports(input), case .certifiedIntersection(.sphereCone(let original)) = input,
                case .analytic(.cone(_, _, let angle)) = original.coneSurface else {
                throw OriginalSourceIssuanceFailure.unsupportedRepresentation
            }
            guard limits.remainingSourceDepth >= 1 else { throw OriginalSourceIssuanceFailure.sourceDepthLimit }
            guard angle == physical.originalRadians else { throw OriginalSourceIssuanceFailure.foreignBinding }
            try original.validate(tolerance: tolerance)
            let f = physical, s = try f.sine(using: &a), c = try f.cosine(using: &a)
            // These exact bounds prove the entire D>0/slant>0/pole-free domain,
            // using sin(theta) in [-1,1], not a finite set of position samples.
            try a.retainStorage(bytes: exactScalarPayloadBytes(count: 2, of: (OriginalPhysicalAngleValue, Int, Int).self))
            for (value, lower, upper) in [(s, 44, 45), (c, 89, 90)] {
                let lo = try f.dividing(f.integer(lower, using: &a), f.integer(100, using: &a), using: &a)
                let hi = try f.dividing(f.integer(upper, using: &a), f.integer(100, using: &a), using: &a)
                guard try f.compare(lo, value, using: &a) == .less,
                    try f.compare(value, hi, using: &a) == .less else { throw OriginalSourceIssuanceFailure.unsupportedRepresentation }
            }
            let phaseSource = try DefaultOriginalSourceBindingIssuer(provider: OriginalCertifiedSphereConePhaseProvider())
                .bind(original, limits: limits, using: &a)
            let law = try DefaultOriginalPhysicalAnalyticCoordinateIssuer<OriginalCertifiedSphereConePhase, OriginalPiScalarDomain>()
                .issue(source: phaseSource, field: phaseField, limits: limits, using: &a)
            let phase = try DefaultOriginalAnalyticCosineZeroIssuer<OriginalCertifiedSphereConePhase, OriginalPiScalarDomain>()
                .issue(law: law, limits: limits, using: &a)
            guard phase.roots.count == 2 else { throw OriginalSourceIssuanceFailure.invalidSource }
            typealias Field = OriginalCertifiedSphereConePlaneRoot.Field
            let base = try Field.base(field: f, maximumExtensionLevel: maximumExtensionLevel, using: &a)
            try a.retainStorage(bytes: exactScalarPayloadBytes(count: 2, of: OriginalCertifiedSphereConePlaneRoot.self))
            var roots: [OriginalCertifiedSphereConePlaneRoot] = []; roots.reserveCapacity(2)
            for ordinal in 0..<2 {
                let sine = ordinal == 0 ? 1 : -1
                let b = try f.adding(f.multiplying(f.integer(sine, using: &a), s, using: &a),
                    f.multiplying(f.integer(4, using: &a), c, using: &a), using: &a)
                let d = try f.subtracting(f.multiplying(b, b, using: &a), f.integer(8, using: &a), using: &a)
                let issuer = try ExactRealRootDomain(field: base, using: &a)
                try a.retainStorage(bytes: exactScalarPayloadBytes(count: 2, of: ExactPolynomialTerm<Field.Value>.self))
                try a.retainStorage(bytes: exactScalarPayloadBytes(count: 2, of: Int.self))
                let polynomial = try issuer.polynomials.polynomial(terms: [
                    .init(powers: [2], coefficient: base.integer(1, using: &a)),
                    .init(powers: [0], coefficient: base.negated(base.importingBase(d, using: &a), using: &a))], using: &a)
                let source = try issuer.bind(polynomial, using: &a)
                let lo = try base.integer(ordinal == 0 ? 2 : 1, using: &a)
                let hi = ordinal == 0 ? try base.integer(3, using: &a) :
                    try base.dividing(base.integer(3, using: &a), base.integer(2, using: &a), using: &a)
                let domain = try issuer.domain(lower: .finite(lo), upper: .finite(hi),
                    includesLower: false, includesUpper: false, using: &a)
                let isolated = try issuer.isolate(source, in: domain, limits: .init(maximumRoots: 1), using: &a)
                guard isolated.roots.count == 1 else { throw OriginalSourceIssuanceFailure.invalidSource }
                let extensionValue = try base.adjoin(isolated.roots[0], using: &a)
                let field = extensionValue.domain, r = extensionValue.generator
                let linear = try field.importingBase(b, using: &a)
                let slant = original.componentKind == .negativeFullBranch ?
                    try field.subtracting(linear, r, using: &a) : try field.adding(linear, r, using: &a)
                let sx = try field.multiplying(field.importingBase(s, using: &a), slant, using: &a)
                let x = try field.subtracting(field.integer(1, using: &a),
                    field.multiplying(field.integer(sine, using: &a), sx, using: &a), using: &a)
                let z = try field.adding(field.integer(-4, using: &a),
                    field.multiplying(field.importingBase(c, using: &a), slant, using: &a), using: &a)
                let depth = try ExactScalarDepth(value: max(r.depth.value, slant.depth.value, x.depth.value, z.depth.value),
                    coefficient: max(r.depth.coefficient, slant.depth.coefficient, x.depth.coefficient, z.depth.coefficient))
                roots.append(.init(phaseOrdinal: ordinal, field: field, radical: r, slant: slant, x: x, z: z,
                    sine: sine, proofDepth: depth))
            }
            var value = phase.proofDepth.value, coefficient = phase.proofDepth.coefficient
            for root in roots { value = max(value, root.proofDepth.value); coefficient = max(coefficient, root.proofDepth.coefficient) }
            let depth = try ExactScalarDepth(value: value, coefficient: coefficient)
            try a.admitDepth(value: value, coefficient: coefficient)
            try a.retainStorage(bytes: exactScalarPayloadBytes(count: 1, of: OriginalCertifiedSphereConeFullSnapshot.self))
            let snapshot = OriginalCertifiedSphereConeFullSnapshot(original: original, physical: f, phase: phase,
                roots: roots, proofDepth: depth)
            try a.checkpoint(); return .init(original: snapshot, sourceDepth: 1)
        } catch { throw .init(preserving: error) }
    }
}
