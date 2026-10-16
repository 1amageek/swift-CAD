import CADCore

/// One admitted source section shares its two roots and every seam incident.
public struct OriginalFullSphereConeSurfaceSection: Sendable {
    public typealias Field = OriginalFullSphereConeSurfaceSnapshot.Field
    public let relation: OriginalFullSphereConeSurfaceRelation
    public let chart: Int
    public let halfAngle: Field.Value
    public let sourceValues: OriginalSphereConeSurfaceSectionValues
    public let proofDepth: ExactScalarDepth
    public var field: Field { sourceValues.field }
    public var plusSlant: Field.Value { sourceValues.plusSlant }
    public var minusSlant: Field.Value { sourceValues.minusSlant }
    public var sine: Field.Value { sourceValues.sine }
    public var cosine: Field.Value { sourceValues.cosine }
    private init(relation: OriginalFullSphereConeSurfaceRelation, chart: Int, halfAngle: Field.Value,
        sourceValues: OriginalSphereConeSurfaceSectionValues, proofDepth: ExactScalarDepth) {
        self.relation = relation; self.chart = chart; self.halfAngle = halfAngle
        self.sourceValues = sourceValues; self.proofDepth = proofDepth
    }
    static func issue<A: ExactScalarAdmission & ~Copyable>(relation: OriginalFullSphereConeSurfaceRelation,
        chart: Int, halfAngle: Field.Value, using a: inout A) throws -> Self {
        try a.withProofScope() { a in
            let values = try relation.source.original.sectionValues(chart: chart, halfAngle: halfAngle, using: &a)
            try a.retainStorage(bytes: exactScalarPayloadBytes(count: 1, of: Self.self))
            let result = Self(relation: relation, chart: chart, halfAngle: values.halfAngle,
                sourceValues: values, proofDepth: try a.depth)
            try a.checkpoint(); return result
        }
    }
    /// The checked paired endpoint changes chart coordinates and preserves the root owner.
    public func otherIncident<A: ExactScalarAdmission & ~Copyable>(limits: OriginalDomainIdentityLimits,
        using a: inout A) throws -> Self {
        try relation.admitProof(limits: limits, using: &a)
        try a.admitDepth(value: proofDepth.value, coefficient: proofDepth.coefficient)
        let f = field
        guard try f.compare(halfAngle, f.integer(-1, using: &a), using: &a) == .equal
            || f.compare(halfAngle, f.integer(1, using: &a), using: &a) == .equal else {
            throw OriginalDomainIdentityFailure.outsideSupport
        }
        let t = try f.negated(halfAngle, using: &a)
        try a.retainStorage(bytes: exactScalarPayloadBytes(count: 1, of: Self.self))
        let result = Self(relation: relation, chart: 1 - chart, halfAngle: t, sourceValues: sourceValues, proofDepth: proofDepth)
        try a.checkpoint(); return result
    }
    public func member<A: ExactScalarAdmission & ~Copyable>(branch: Int, coneCycle: OriginalParameterCycle,
        sphereCycle: OriginalParameterCycle, limits: OriginalDomainIdentityLimits,
        using a: inout A) throws -> OriginalFullSphereConeSurfaceMember {
        try a.withProofScope() { a in
            try relation.admitProof(limits: limits, using: &a)
            try a.admitDepth(value: proofDepth.value, coefficient: proofDepth.coefficient)
            guard branch == 0 || branch == 1 else { throw OriginalDomainIdentityFailure.outsideSupport }
            let source = relation.source.original, f = field
            let point = try sourceValues.position(branch: branch, using: &a)
            let period = try f.importing(source.labelPeriod, using: &a)
            let shift = try f.dividing(f.multiplying(period, f.integer(chart, using: &a), using: &a), f.integer(2, using: &a), using: &a)
            let coneOffset = try f.adding(shift, f.multiplying(period, coneCycle.scalar(in: f, using: &a), using: &a), using: &a)
            let sphereOffset = try f.multiplying(period, sphereCycle.scalar(in: f, using: &a), using: &a)
            try a.retainStorage(bytes: exactScalarPayloadBytes(count: 1, of: OriginalFullSphereConeSurfaceMember.self))
            let result = OriginalFullSphereConeSurfaceMember(section: self, branch: branch, slant: point.slant,
                x: point.x, y: point.y, z: point.z, coneLabelOffset: coneOffset, sphereLabelOffset: sphereOffset, proofDepth: try a.depth)
            try a.checkpoint(); return result
        }
    }
}
