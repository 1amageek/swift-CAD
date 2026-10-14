import CADCore

/// One admitted source section shares its two roots and every seam incident.
public struct OriginalFullConeConeSurfaceSection: Sendable {
    public typealias Field = OriginalFullConeConeSurfaceSnapshot.Field
    public let relation: OriginalFullConeConeSurfaceRelation
    public let chart: Int
    public let halfAngle: Field.Value
    public let sourceValues: OriginalConeConeSurfaceSectionValues
    public let proofDepth: ExactScalarDepth
    public var field: Field { sourceValues.field }
    public var sine: Field.Value { sourceValues.sine }
    public var cosine: Field.Value { sourceValues.cosine }
    private init(relation: OriginalFullConeConeSurfaceRelation, chart: Int, halfAngle: Field.Value,
        sourceValues: OriginalConeConeSurfaceSectionValues, proofDepth: ExactScalarDepth) {
        self.relation = relation; self.chart = chart; self.halfAngle = halfAngle
        self.sourceValues = sourceValues; self.proofDepth = proofDepth
    }
    static func issue<A: ExactScalarAdmission & ~Copyable>(relation: OriginalFullConeConeSurfaceRelation,
        chart: Int, halfAngle: Field.Value, using a: inout A) throws -> Self {
        try OriginalSourceProofAdmission<A>.withBorrow(&a) { a in
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
    public func member<A: ExactScalarAdmission & ~Copyable>(branch: Int, parameterizedCycle: OriginalParameterCycle,
        referenceCycle: OriginalParameterCycle, limits: OriginalDomainIdentityLimits,
        using a: inout A) throws -> OriginalFullConeConeSurfaceMember {
        try OriginalSourceProofAdmission<A>.withBorrow(&a) { a in
            try relation.admitProof(limits: limits, using: &a)
            try a.admitDepth(value: proofDepth.value, coefficient: proofDepth.coefficient)
            guard branch == 0 || branch == 1 else { throw OriginalDomainIdentityFailure.outsideSupport }
            let source = relation.source.original, f = field
            func coordinate(_ kind: OriginalConeConeSurfaceCoordinate.Kind) throws -> OriginalConeConeSurfaceCoordinate {
                try OriginalConeConeSurfaceCoordinate.issue(source: relation.source, values: sourceValues, branch: branch,
                    kind: kind, limits: limits.source, using: &a)
            }
            let slant = try coordinate(.parameterizedSlant), referenceSlant = try coordinate(.referenceSlant)
            let x = try coordinate(.x), y = try coordinate(.y), z = try coordinate(.z)
            let period = try f.importing(source.labelPeriod, using: &a)
            let shift = try f.dividing(f.multiplying(period, f.integer(chart, using: &a), using: &a), f.integer(2, using: &a), using: &a)
            let parameterizedOffset = try f.adding(shift, f.multiplying(period, parameterizedCycle.scalar(in: f, using: &a), using: &a), using: &a)
            let referenceShift = branch == 0 ? try f.integer(0, using: &a) : try f.dividing(period, f.integer(2, using: &a), using: &a)
            let referenceOffset = try f.adding(referenceShift, f.multiplying(period, referenceCycle.scalar(in: f, using: &a), using: &a), using: &a)
            try a.retainStorage(bytes: exactScalarPayloadBytes(count: 1, of: OriginalFullConeConeSurfaceMember.self))
            let result = OriginalFullConeConeSurfaceMember(section: self, branch: branch, parameterizedSlant: slant,
                referenceSlant: referenceSlant, x: x, y: y, z: z,
                parameterizedLabelOffset: parameterizedOffset, referenceLabelOffset: referenceOffset, proofDepth: try a.depth)
            try a.checkpoint(); return result
        }
    }
}
