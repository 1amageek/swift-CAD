import CADCore

/// Reuses the original physical coefficient bounds and primitive source laws.
public struct OriginalApexSphereConeSurfaceSnapshotProvider: OriginalSourceSnapshotting {
    public let physical: OriginalPhysicalAngleScalarDomain
    public let maximumExtensionLevel: Int
    public let tolerance: ModelingTolerance
    public init(physical: OriginalPhysicalAngleScalarDomain, maximumExtensionLevel: Int,
        tolerance: ModelingTolerance) {
        self.physical = physical; self.maximumExtensionLevel = maximumExtensionLevel; self.tolerance = tolerance
    }
    public static func pair(_ input: OriginalApexSphereConeSurfaceInput) -> (sphere: Surface3D, cone: Surface3D, sphereFirst: Bool)? {
        let sphere = Surface3D.analytic(.sphere(center: .origin, radius: 1))
        let cone = Surface3D.analytic(.cone(apex: .init(x: 1, y: 0, z: 0), axis: .unitZ,
            halfAngle: Double(bitPattern: 0x3fddac670561bb50)))
        if input.first == sphere && input.second == cone { return (sphere, cone, true) }
        if input.first == cone && input.second == sphere { return (sphere, cone, false) }
        return nil
    }
    public func snapshot<A: ExactScalarAdmission & ~Copyable>(_ input: borrowing OriginalApexSphereConeSurfaceInput,
        limits: OriginalSourceIssuanceLimits, using a: inout A)
        throws(OriginalSourceIssuanceFailure) -> OriginalSourceSnapshot<OriginalApexSphereConeSurfaceSnapshot> {
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
            typealias Field = OriginalApexSphereConeSurfaceSnapshot.Field
            let base = try Field.base(field: physical, maximumExtensionLevel: maximumExtensionLevel, using: &a)
            let primitive = DefaultOriginalSourceBindingIssuer(provider: OriginalAnalyticCoordinateSurfaceSnapshotProvider(tolerance: tolerance))
            let first = try primitive.bind(input.first, limits: .init(remainingSourceDepth: 0), using: &a)
            let second = try primitive.bind(input.second, limits: .init(remainingSourceDepth: 0), using: &a)
            let issuer = DefaultOriginalAnalyticCoordinateIssuer<OriginalAnalyticCoordinateSnapshot, Field>()
            let firstLaw = try issuer.issue(source: first, field: base, limits: limits, using: &a)
            let secondLaw = try issuer.issue(source: second, field: base, limits: limits, using: &a)
            let sine = try base.importingBase(s, using: &a), cosine = try base.importingBase(c, using: &a)
            let period = try base.binary64(exactly: 2 * Double.pi, using: &a), depth = try a.depth
            try a.retainStorage(bytes: exactScalarPayloadBytes(count: 1, of: OriginalApexSphereConeSurfaceSnapshot.self))
            let result = OriginalApexSphereConeSurfaceSnapshot(original: input, firstLaw: firstLaw, secondLaw: secondLaw,
                sphereIsFirst: pair.sphereFirst, field: base, sine: sine, cosine: cosine,
                labelPeriod: period, proofDepth: depth)
            try a.checkpoint(); return .init(original: result, sourceDepth: 1)
            }
        } catch { throw .init(preserving: error) }
    }
}
