import CADCore

/// Sealed position-only exclusion; no positive implicit parameterization is claimed.
public struct OriginalImplicitHostPlaneSeparationReceipt: Sendable {
    public typealias Field = OriginalExactScalarDomain
    public enum ProofScope: Sendable { case originalCommonRootPositionOnly }
    public let source: OriginalSourceBinding<OriginalImplicitCurveSnapshot>
    public let plane: OriginalPlaneBasisReceipt<OriginalPlaneSnapshot, Field>
    public let field: Field
    public let host: OriginalSourceBinding<BSplineSurface3D>
    public let support: OriginalSourceParameterInterval<OriginalExactScalar>
    public let hostSupport: [OriginalSourceParameterInterval<OriginalExactScalar>]
    public let hostWeights: [OriginalExactScalar]
    public let hostHomogeneousZ: [OriginalExactScalar]
    public let hostHeight: OriginalExactScalar
    public let planeHeight: OriginalExactScalar
    public let signedGap: OriginalExactScalar
    public let proofScope: ProofScope
    public let proofDepth: ExactScalarDepth
    public var cells: [CertifiedImplicitIntersectionGraphCell] { source.original.cells }
    public var cellCount: Int { source.original.original.cells.count }

    init(source: OriginalSourceBinding<OriginalImplicitCurveSnapshot>,
        plane: OriginalPlaneBasisReceipt<OriginalPlaneSnapshot, Field>, field: Field,
        support: OriginalSourceParameterInterval<OriginalExactScalar>,
        hostSupport: [OriginalSourceParameterInterval<OriginalExactScalar>],
        hostWeights: [OriginalExactScalar], hostHomogeneousZ: [OriginalExactScalar],
        hostHeight: OriginalExactScalar, planeHeight: OriginalExactScalar,
        signedGap: OriginalExactScalar, proofDepth: ExactScalarDepth) {
        self.source = source; self.plane = plane; self.field = field
        host = source.original.second; self.support = support; self.hostSupport = hostSupport
        self.hostWeights = hostWeights; self.hostHomogeneousZ = hostHomogeneousZ
        self.hostHeight = hostHeight; self.planeHeight = planeHeight; self.signedGap = signedGap
        proofScope = .originalCommonRootPositionOnly; self.proofDepth = proofDepth
    }

    public func admitProof<A: ExactScalarAdmission & ~Copyable>(maximumCells: Int,
        limits: OriginalSourceIssuanceLimits, using a: inout A
    ) throws(OriginalSourceIssuanceFailure) {
        do {
            try a.checkpoint(); try a.consumeWork(32); try source.require(limits)
            try source.original.first.require(limits); try source.original.second.require(limits)
            try host.require(limits); try plane.source.require(limits)
            guard cellCount > 0, cellCount <= maximumCells else { throw OriginalSourceIssuanceFailure.chartLimit }
            guard host.owner === source.original.second.owner else { throw OriginalSourceIssuanceFailure.foreignBinding }
            try a.admitDepth(value: proofDepth.value, coefficient: proofDepth.coefficient)
            _ = try field.importing(plane.field.integer(0, using: &a), using: &a)
            func admit(_ value: OriginalExactScalar, _ a: inout A) throws {
                try a.consumeWork(1); _ = try field.importing(value, using: &a)
            }
            try admit(support.lower, &a); try admit(support.upper, &a)
            try admit(hostHeight, &a); try admit(planeHeight, &a); try admit(signedGap, &a)
            for interval in hostSupport { try admit(interval.lower, &a); try admit(interval.upper, &a) }
            for value in hostWeights { try admit(value, &a) }
            for value in hostHomogeneousZ { try admit(value, &a) }
            for value in plane.origin { try admit(value, &a) }
            for value in plane.normal { try admit(value, &a) }
            for value in plane.u { try admit(value, &a) }
            for value in plane.v { try admit(value, &a) }
            try a.checkpoint()
        } catch { throw .init(preserving: error) }
    }
}
