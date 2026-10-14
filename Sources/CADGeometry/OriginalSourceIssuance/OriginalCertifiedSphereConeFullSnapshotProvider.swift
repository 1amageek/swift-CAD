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
            case .analytic(.cone(let apex, let axis, _)) = curve.coneSurface,
            axis == .unitZ else { return false }
        switch curve.componentKind {
        case .negativeFullBranch, .positiveFullBranch:
            return curve.sphereSurface == .analytic(.sphere(center: .origin, radius: 3))
                && apex == .init(x: 1, y: 0, z: -4)
                && curve.lowerAngle == 0 && curve.upperAngle == 2 * Double.pi
        case .boundedAngularInterval:
            return curve.sphereSurface == .analytic(.sphere(center: .origin, radius: 2))
                && apex == .init(x: 2, y: 0, z: -4)
                && curve.lowerAngle > 0.4 && curve.lowerAngle < 0.6
                && curve.upperAngle > 2.5 && curve.upperAngle < 2.8
        default: return false
        }
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
            // These exact coefficient bounds feed the whole-source theorem.
            // Full branches use sin(theta) in [-1,1]; bounded branches use
            // their retained critical arc, including D=0 at its endpoints.
            try Self.admitPhysicalBounds(field: f, sine: s, cosine: c, using: &a)
            let boundedArc = original.componentKind == .boundedAngularInterval
                ? try OriginalCertifiedSphereConeBoundedArc.issue(original: original, field: f, using: &a) : nil
            let apexX = boundedArc == nil ? 1 : 2
            let constant = boundedArc == nil ? 8 : 16
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
                let sine = boundedArc != nil || ordinal == 0 ? 1 : -1
                let b = try f.adding(f.multiplying(f.integer(sine * apexX, using: &a), s, using: &a),
                    f.multiplying(f.integer(4, using: &a), c, using: &a), using: &a)
                let d = try f.subtracting(f.multiplying(b, b, using: &a), f.integer(constant, using: &a), using: &a)
                let field: Field
                let r: Field.Value
                let slant: Field.Value
                if boundedArc != nil && ordinal == 1 {
                    field = roots[0].field; r = roots[0].radical
                    let twiceB = try field.multiplying(field.integer(2, using: &a),
                        field.importingBase(b, using: &a), using: &a)
                    slant = try field.subtracting(twiceB, roots[0].slant, using: &a)
                } else {
                    let issuer = try ExactRealRootDomain(field: base, using: &a)
                    let bounded = boundedArc != nil
                    try a.retainStorage(bytes: exactScalarPayloadBytes(count: bounded ? 3 : 2,
                        of: ExactPolynomialTerm<Field.Value>.self))
                    try a.retainStorage(bytes: exactScalarPayloadBytes(count: bounded ? 3 : 2, of: Int.self))
                    var terms: [ExactPolynomialTerm<Field.Value>] = []; terms.reserveCapacity(bounded ? 3 : 2)
                    terms.append(.init(powers: [2], coefficient: try base.integer(1, using: &a)))
                    if bounded {
                        // Retain the original slant quadratic. Its root generator avoids
                        // cancellation in the constant coefficient of X=2-s*lambda.
                        let linear = try base.multiplying(base.integer(-2, using: &a), base.importingBase(b, using: &a), using: &a)
                        terms.append(.init(powers: [1], coefficient: linear))
                        terms.append(.init(powers: [0], coefficient: try base.integer(16, using: &a)))
                    } else {
                        terms.append(.init(powers: [0], coefficient: try base.negated(base.importingBase(d, using: &a), using: &a)))
                    }
                    let polynomial = try issuer.polynomials.polynomial(terms: terms, using: &a)
                    let source = try issuer.bind(polynomial, using: &a)
                    let lo = try base.integer(bounded ? 6 : (ordinal == 0 ? 2 : 1), using: &a)
                    let hi = bounded ? try base.integer(7, using: &a) : ordinal == 0 ? try base.integer(3, using: &a) :
                        try base.dividing(base.integer(3, using: &a), base.integer(2, using: &a), using: &a)
                    let domain = try issuer.domain(lower: .finite(lo), upper: .finite(hi),
                        includesLower: false, includesUpper: false, using: &a)
                    let isolated = try issuer.isolate(source, in: domain, limits: .init(maximumRoots: 1), using: &a)
                    guard isolated.roots.count == 1 else { throw OriginalSourceIssuanceFailure.invalidSource }
                    let extensionValue = try base.adjoin(isolated.roots[0], using: &a)
                    field = extensionValue.domain
                    let linear = try field.importingBase(b, using: &a)
                    if bounded {
                        slant = extensionValue.generator
                        r = try field.subtracting(slant, linear, using: &a)
                    } else {
                        r = extensionValue.generator
                        slant = original.componentKind == .negativeFullBranch ?
                            try field.subtracting(linear, r, using: &a) : try field.adding(linear, r, using: &a)
                    }
                }
                let sx = try field.multiplying(field.importingBase(s, using: &a), slant, using: &a)
                let x = try field.subtracting(field.integer(apexX, using: &a),
                    field.multiplying(field.integer(sine, using: &a), sx, using: &a), using: &a)
                let z = try field.adding(field.integer(-4, using: &a),
                    field.multiplying(field.importingBase(c, using: &a), slant, using: &a), using: &a)
                let depth = try ExactScalarDepth(value: max(r.depth.value, slant.depth.value, x.depth.value, z.depth.value),
                    coefficient: max(r.depth.coefficient, slant.depth.coefficient, x.depth.coefficient, z.depth.coefficient))
                roots.append(.init(phaseOrdinal: ordinal, field: field, radical: r, slant: slant, x: x, z: z,
                    sine: sine, proofDepth: depth))
            }
            var value = max(phase.proofDepth.value, boundedArc?.proofDepth.value ?? 0)
            var coefficient = max(phase.proofDepth.coefficient, boundedArc?.proofDepth.coefficient ?? 0)
            for root in roots { value = max(value, root.proofDepth.value); coefficient = max(coefficient, root.proofDepth.coefficient) }
            let depth = try ExactScalarDepth(value: value, coefficient: coefficient)
            try a.admitDepth(value: value, coefficient: coefficient)
            try a.retainStorage(bytes: exactScalarPayloadBytes(count: 1, of: OriginalCertifiedSphereConeFullSnapshot.self))
            let snapshot = OriginalCertifiedSphereConeFullSnapshot(original: original, physical: f, phase: phase,
                roots: roots, proofDepth: depth, boundedArc: boundedArc)
            try a.checkpoint(); return .init(original: snapshot, sourceDepth: 1)
        } catch { throw .init(preserving: error) }
    }
    static func admitPhysicalBounds<A: ExactScalarAdmission & ~Copyable>(field f: OriginalPhysicalAngleScalarDomain,
        sine: OriginalPhysicalAngleValue, cosine: OriginalPhysicalAngleValue, using a: inout A) throws {
        try a.retainStorage(bytes: exactScalarPayloadBytes(count: 2, of: (OriginalPhysicalAngleValue, Int, Int).self))
        for (value, lower, upper) in [(sine, 44, 45), (cosine, 89, 90)] {
            let lo = try f.dividing(f.integer(lower, using: &a), f.integer(100, using: &a), using: &a)
            let hi = try f.dividing(f.integer(upper, using: &a), f.integer(100, using: &a), using: &a)
            guard try f.compare(lo, value, using: &a) == .less,
                try f.compare(value, hi, using: &a) == .less else { throw OriginalSourceIssuanceFailure.unsupportedRepresentation }
        }
    }
}
