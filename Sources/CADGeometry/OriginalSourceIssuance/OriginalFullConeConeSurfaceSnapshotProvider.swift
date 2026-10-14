import CADCore

/// Reuses source-owned coefficient bounds and original primitive coordinate laws.
public struct OriginalFullConeConeSurfaceSnapshotProvider: OriginalSourceSnapshotting {
    public let reference: OriginalPhysicalAngleScalarDomain
    public let parameterized: OriginalPhysicalAngleScalarDomain
    public let maximumExtensionLevel: Int
    public let tolerance: ModelingTolerance
    public init(reference: OriginalPhysicalAngleScalarDomain, parameterized: OriginalPhysicalAngleScalarDomain,
        maximumExtensionLevel: Int, tolerance: ModelingTolerance) {
        self.reference = reference; self.parameterized = parameterized
        self.maximumExtensionLevel = maximumExtensionLevel; self.tolerance = tolerance
    }
    public static func pair(_ input: OriginalFullConeConeSurfaceInput) -> (reference: Surface3D, parameterized: Surface3D, referenceFirst: Bool)? {
        let first = Surface3D.analytic(.cone(apex: .origin, axis: .unitZ, halfAngle: Double(bitPattern: 0x3fddac670561bb50)))
        let second = Surface3D.analytic(.cone(apex: .init(x: 0, y: 0, z: 4), axis: .unitY, halfAngle: Double(bitPattern: 0x3fd6f61941e4def1)))
        if input.first == first && input.second == second { return (first, second, true) }
        if input.first == second && input.second == first { return (first, second, false) }
        return nil
    }
    public func snapshot<A: ExactScalarAdmission & ~Copyable>(_ input: borrowing OriginalFullConeConeSurfaceInput,
        limits: OriginalSourceIssuanceLimits, using a: inout A)
        throws(OriginalSourceIssuanceFailure) -> OriginalSourceSnapshot<OriginalFullConeConeSurfaceSnapshot> {
        let input = copy input
        do {
            return try OriginalSourceProofAdmission<A>.withBorrow(&a) { a in
                try a.checkpoint(); try a.consumeWork(1)
                guard limits.remainingSourceDepth >= 1 else { throw OriginalSourceIssuanceFailure.sourceDepthLimit }
                guard let pair = Self.pair(input), case .analytic(.cone(_, _, let alpha)) = pair.reference,
                    case .analytic(.cone(_, _, let beta)) = pair.parameterized else { throw OriginalSourceIssuanceFailure.unsupportedRepresentation }
                guard reference.originalRadians == alpha, parameterized.originalRadians == beta else { throw OriginalSourceIssuanceFailure.foreignBinding }
                let sa = try reference.sine(using: &a), ca = try reference.cosine(using: &a)
                let sb = try parameterized.sine(using: &a), cb = try parameterized.cosine(using: &a)
                try OriginalCertifiedConeConeFullSnapshotProvider.admitPhysicalBounds(reference: reference,
                    referenceSine: sa, referenceCosine: ca, parameterized: parameterized,
                    parameterizedSine: sb, parameterizedCosine: cb, using: &a)
                typealias Field = OriginalFullConeConeSurfaceSnapshot.Field
                let f = try Field.base(field: parameterized, maximumExtensionLevel: maximumExtensionLevel, using: &a)
                let primitive = DefaultOriginalSourceBindingIssuer(provider: OriginalAnalyticCoordinateSurfaceSnapshotProvider(tolerance: tolerance))
                let first = try primitive.bind(input.first, limits: .init(remainingSourceDepth: 0), using: &a)
                let second = try primitive.bind(input.second, limits: .init(remainingSourceDepth: 0), using: &a)
                let issuer = DefaultOriginalAnalyticCoordinateIssuer<OriginalAnalyticCoordinateSnapshot, Field>()
                let firstLaw = try issuer.issue(source: first, field: f, limits: limits, using: &a)
                let secondLaw = try issuer.issue(source: second, field: f, limits: limits, using: &a)
                let sine = try f.importingBase(sb, using: &a), cosine = try f.importingBase(cb, using: &a)
                let period = try f.binary64(exactly: 2 * Double.pi, using: &a)
                try a.retainStorage(bytes: exactScalarPayloadBytes(count: 1, of: OriginalFullConeConeSurfaceSnapshot.self))
                let result = OriginalFullConeConeSurfaceSnapshot(original: input, firstLaw: firstLaw, secondLaw: secondLaw,
                    referenceIsFirst: pair.referenceFirst, field: f, referenceField: reference, parameterizedField: parameterized,
                    referenceSine: sa, referenceCosine: ca, parameterizedSine: sine, parameterizedCosine: cosine,
                    labelPeriod: period, proofDepth: try a.depth)
                try a.checkpoint(); return .init(original: result, sourceDepth: 1)
            }
        } catch { throw .init(preserving: error) }
    }
}
