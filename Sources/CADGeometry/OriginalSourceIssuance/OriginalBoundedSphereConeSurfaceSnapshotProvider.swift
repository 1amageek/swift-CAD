import CADCore

/// Reuses the exact critical arc and original analytic source laws.
public struct OriginalBoundedSphereConeSurfaceSnapshotProvider: OriginalSourceSnapshotting {
    public let physical: OriginalPhysicalAngleScalarDomain
    public let maximumExtensionLevel: Int
    public let tolerance: ModelingTolerance
    public init(physical: OriginalPhysicalAngleScalarDomain, maximumExtensionLevel: Int,
        tolerance: ModelingTolerance) {
        self.physical = physical; self.maximumExtensionLevel = maximumExtensionLevel; self.tolerance = tolerance
    }
    public static func pair(_ input: OriginalBoundedSphereConeSurfaceInput) -> (sphere: Surface3D, cone: Surface3D, sphereFirst: Bool)? {
        let sphere = Surface3D.analytic(.sphere(center: .origin, radius: 2))
        let cone = Surface3D.analytic(.cone(apex: .init(x: 2, y: 0, z: -4), axis: .unitZ,
            halfAngle: Double(bitPattern: 0x3fddac670561bb50)))
        if input.first == sphere && input.second == cone { return (sphere, cone, true) }
        if input.first == cone && input.second == sphere { return (sphere, cone, false) }
        return nil
    }
    public func snapshot<A: ExactScalarAdmission & ~Copyable>(_ input: borrowing OriginalBoundedSphereConeSurfaceInput,
        limits: OriginalSourceIssuanceLimits, using a: inout A)
        throws(OriginalSourceIssuanceFailure) -> OriginalSourceSnapshot<OriginalBoundedSphereConeSurfaceSnapshot> {
        let input = copy input
        do {
            return try OriginalSourceProofAdmission<A>.withBorrow(&a) { a in
                try a.checkpoint(); try a.consumeWork(1)
                guard limits.remainingSourceDepth >= 1 else { throw OriginalSourceIssuanceFailure.sourceDepthLimit }
                guard let pair = Self.pair(input), case .analytic(.cone(_, _, let angle)) = pair.cone else {
                    throw OriginalSourceIssuanceFailure.unsupportedRepresentation
            }
            guard physical.originalRadians == angle else { throw OriginalSourceIssuanceFailure.foreignBinding }
            let s = try physical.sine(using: &a), c = try physical.cosine(using: &a)
            try OriginalCertifiedSphereConeFullSnapshotProvider.admitPhysicalBounds(field: physical, sine: s, cosine: c, using: &a)
            let curve = try CertifiedSphereConeIntersectionCurve(sphereSurface: pair.sphere, coneSurface: pair.cone,
                componentKind: .boundedAngularInterval, lowerAngle: Double(bitPattern: 4602529519994401816),
                upperAngle: Double(bitPattern: 4613149419042483861), tolerance: tolerance)
            let arc = try OriginalCertifiedSphereConeBoundedArc.issue(original: curve, field: physical, using: &a)
            typealias Field = OriginalBoundedSphereConeSurfaceSnapshot.Field
            let base = try Field.base(field: physical, maximumExtensionLevel: maximumExtensionLevel, using: &a)
            let k = try base.importingBase(arc.criticalSine, using: &a)
            let radicand = try base.subtracting(base.integer(1, using: &a), base.multiplying(k, k, using: &a), using: &a)
            let roots = try ExactRealRootDomain(field: base, using: &a)
            try a.retainStorage(bytes: exactScalarPayloadBytes(count: 2, of: ExactPolynomialTerm<Field.Value>.self))
            try a.retainStorage(bytes: exactScalarPayloadBytes(count: 2, of: Int.self))
            let polynomial = try roots.polynomials.polynomial(terms: [
                .init(powers: [2], coefficient: try base.integer(1, using: &a)),
                .init(powers: [0], coefficient: try base.negated(radicand, using: &a))], using: &a)
            let bound = try roots.domain(lower: .finite(base.dividing(base.integer(4, using: &a), base.integer(5, using: &a), using: &a)),
                upper: .finite(base.dividing(base.integer(9, using: &a), base.integer(10, using: &a), using: &a)),
                includesLower: false, includesUpper: false, using: &a)
            let isolated = try roots.isolate(roots.bind(polynomial, using: &a), in: bound, limits: .init(maximumRoots: 1), using: &a)
            guard isolated.roots.count == 1 else { throw OriginalSourceIssuanceFailure.invalidSource }
            let extensionValue = try base.adjoin(isolated.roots[0], using: &a), f = extensionValue.domain
            let critical = try f.importingBase(arc.criticalSine, using: &a)
            let denominator = try f.adding(f.integer(1, using: &a), extensionValue.generator, using: &a)
            let lower = try f.dividing(critical, denominator, using: &a)
            let upper = try f.dividing(denominator, critical, using: &a)
            let primitive = DefaultOriginalSourceBindingIssuer(provider: OriginalAnalyticCoordinateSurfaceSnapshotProvider(tolerance: tolerance))
            let first = try primitive.bind(input.first, limits: .init(remainingSourceDepth: 0), using: &a)
            let second = try primitive.bind(input.second, limits: .init(remainingSourceDepth: 0), using: &a)
            let issuer = DefaultOriginalAnalyticCoordinateIssuer<OriginalAnalyticCoordinateSnapshot, Field>()
            let firstLaw = try issuer.issue(source: first, field: base, limits: limits, using: &a)
            let secondLaw = try issuer.issue(source: second, field: base, limits: limits, using: &a)
            let sine = try base.importingBase(s, using: &a), cosine = try base.importingBase(c, using: &a)
            let period = try base.binary64(exactly: 2 * Double.pi, using: &a), depth = try a.depth
            try a.retainStorage(bytes: exactScalarPayloadBytes(count: 1, of: OriginalBoundedSphereConeSurfaceSnapshot.self))
            let result = OriginalBoundedSphereConeSurfaceSnapshot(original: input, firstLaw: firstLaw, secondLaw: secondLaw,
                sphereIsFirst: pair.sphereFirst, arc: arc, field: base, criticalField: f, sine: sine, cosine: cosine,
                lowerHalfAngle: lower, upperHalfAngle: upper, labelPeriod: period, proofDepth: depth)
            try a.checkpoint(); return .init(original: result, sourceDepth: 1)
            }
        } catch { throw .init(preserving: error) }
    }
}
