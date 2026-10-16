import CADCore

/// Circle chart section retains both regular seam sides and the apex incidents.
public struct OriginalApexSphereConeSurfaceSection: Sendable {
    public typealias Field = OriginalApexSphereConeSurfaceSnapshot.Field
    public let relation: OriginalApexSphereConeSurfaceRelation
    public let chart: Int
    public let halfAngle: Field.Value
    public let sourceValues: OriginalApexSphereConeSurfaceValues
    public let proofDepth: ExactScalarDepth
    public var field: Field { sourceValues.field }
    private init(relation: OriginalApexSphereConeSurfaceRelation, chart: Int, halfAngle: Field.Value,
        sourceValues: OriginalApexSphereConeSurfaceValues, proofDepth: ExactScalarDepth) {
        self.relation = relation; self.chart = chart; self.halfAngle = halfAngle
        self.sourceValues = sourceValues; self.proofDepth = proofDepth
    }
    static func issue<A: ExactScalarAdmission & ~Copyable>(relation: OriginalApexSphereConeSurfaceRelation,
        chart: Int, halfAngle: Field.Value, using a: inout A) throws -> Self {
        try a.withProofScope() { a in
        let values = try relation.source.original.sectionValues(chart: chart, halfAngle: halfAngle, using: &a)
        try a.retainStorage(bytes: exactScalarPayloadBytes(count: 1, of: Self.self))
        let result = Self(relation: relation, chart: chart, halfAngle: halfAngle, sourceValues: values, proofDepth: try a.depth)
        try a.checkpoint(); return result
        }
    }
    public func otherIncident<A: ExactScalarAdmission & ~Copyable>(limits: OriginalDomainIdentityLimits,
        using a: inout A) throws -> Self {
        try relation.admitProof(limits: limits, using: &a)
        try a.admitDepth(value: proofDepth.value, coefficient: proofDepth.coefficient)
        let f = field
        guard try f.compare(halfAngle, f.integer(-1, using: &a), using: &a) == .equal
            || f.compare(halfAngle, f.integer(1, using: &a), using: &a) == .equal else {
            throw OriginalDomainIdentityFailure.outsideSupport
        }
        try a.retainStorage(bytes: exactScalarPayloadBytes(count: 1, of: Self.self))
        let result = Self(relation: relation, chart: 1-chart, halfAngle: try f.negated(halfAngle, using: &a),
            sourceValues: sourceValues, proofDepth: proofDepth)
        try a.checkpoint(); return result
    }
    public func member<A: ExactScalarAdmission & ~Copyable>(coneCycle: OriginalParameterCycle,
        sphereCycle: OriginalParameterCycle, limits: OriginalDomainIdentityLimits,
        using a: inout A) throws -> OriginalApexSphereConeSurfaceMember {
        try a.withProofScope() { a in
        try relation.admitProof(limits: limits, using: &a)
        try a.admitDepth(value: proofDepth.value, coefficient: proofDepth.coefficient)
        let f = field, period = relation.source.original.labelPeriod
        let shift = try f.dividing(f.multiplying(period, f.integer(chart, using: &a), using: &a), f.integer(2, using: &a), using: &a)
        let coneOffset = try f.adding(shift, f.multiplying(period, coneCycle.scalar(in: f, using: &a), using: &a), using: &a)
        let sphereOffset = try f.multiplying(period, sphereCycle.scalar(in: f, using: &a), using: &a)
        try a.retainStorage(bytes: exactScalarPayloadBytes(count: 1, of: OriginalApexSphereConeSurfaceMember.self))
        let sign = try f.sign(of: sourceValues.sine, using: &a)
        let result = OriginalApexSphereConeSurfaceMember(relation: relation, section: self, slant: sourceValues.slant,
            x: sourceValues.x, y: sourceValues.y, z: sourceValues.z, coneLabelOffset: coneOffset,
            sphereLabelOffset: sphereOffset, apexConeU: nil, proofDepth: try a.depth,
            stratum: sign == .zero ? .apex : sign == .positive ? .positiveArc : .negativeArc)
        try a.checkpoint(); return result
        }
    }
}
