import CADCore

/// One admitted point section shares its selected root between both source arcs.
public struct OriginalBoundedSphereConeSurfaceSection: Sendable {
    public typealias Field = OriginalBoundedSphereConeSurfaceSnapshot.Field
    public let relation: OriginalBoundedSphereConeSurfaceRelation
    public let sourceHalfAngle: Field.Value
    public let halfAngle: Field.Value
    public let field: Field
    public let sine: Field.Value
    public let cosine: Field.Value
    public let plusSlant: Field.Value
    public let minusSlant: Field.Value
    public let isSharedEndpoint: Bool
    public let sourceValues: OriginalSphereConeSurfaceSectionValues
    public let proofDepth: ExactScalarDepth
    private init(relation: OriginalBoundedSphereConeSurfaceRelation, sourceHalfAngle: Field.Value, halfAngle: Field.Value,
        field: Field, sine: Field.Value, cosine: Field.Value, plusSlant: Field.Value,
        minusSlant: Field.Value, isSharedEndpoint: Bool, sourceValues: OriginalSphereConeSurfaceSectionValues, proofDepth: ExactScalarDepth) {
        self.relation = relation; self.sourceHalfAngle = sourceHalfAngle; self.halfAngle = halfAngle; self.field = field; self.sine = sine
        self.cosine = cosine; self.plusSlant = plusSlant; self.minusSlant = minusSlant
        self.isSharedEndpoint = isSharedEndpoint; self.sourceValues = sourceValues; self.proofDepth = proofDepth
    }
    static func issue<A: ExactScalarAdmission & ~Copyable>(relation: OriginalBoundedSphereConeSurfaceRelation,
        halfAngle t: Field.Value, using a: inout A) throws -> Self {
        return try OriginalSourceProofAdmission<A>.withBorrow(&a) { a in
            let source = relation.source.original
            let values = try source.sectionValues(halfAngle: t, using: &a)
            let f = values.field, plus = values.plusSlant, minus = values.minusSlant
            let ss = values.sine, cc = values.cosine, depth = values.proofDepth
            let boundary = values.isDoubleRoot
            try a.retainStorage(bytes: exactScalarPayloadBytes(count: 1, of: Self.self))
        let section = Self(relation: relation, sourceHalfAngle: t, halfAngle: try f.importing(t, using: &a), field: f, sine: ss, cosine: cc,
            plusSlant: plus, minusSlant: minus, isSharedEndpoint: boundary, sourceValues: values, proofDepth: depth)
        try a.checkpoint(); return section
        }
    }
    public func member<A: ExactScalarAdmission & ~Copyable>(branch: Int, coneCycle: OriginalParameterCycle,
        sphereCycle: OriginalParameterCycle, limits: OriginalDomainIdentityLimits,
        using a: inout A) throws -> OriginalBoundedSphereConeSurfaceMember {
        return try OriginalSourceProofAdmission<A>.withBorrow(&a) { a in
            try relation.admitProof(limits: limits, using: &a)
            try a.admitDepth(value: proofDepth.value, coefficient: proofDepth.coefficient)
            guard branch == 0 || branch == 1 else { throw OriginalDomainIdentityFailure.outsideSupport }
            let source = relation.source.original, f = field
            let position = try sourceValues.position(branch: branch, using: &a)
            let slant = position.slant, x = position.x, y = position.y, z = position.z
            let coneOffset = try f.multiplying(f.importing(source.labelPeriod, using: &a), coneCycle.scalar(in: f, using: &a), using: &a)
            let sphereOffset = try f.multiplying(f.importing(source.labelPeriod, using: &a), sphereCycle.scalar(in: f, using: &a), using: &a)
            let depth = try a.depth
            try a.retainStorage(bytes: exactScalarPayloadBytes(count: 1, of: OriginalBoundedSphereConeSurfaceMember.self))
            let result = OriginalBoundedSphereConeSurfaceMember(section: self, branch: branch, slant: slant,
                x: x, y: y, z: z, coneLabelOffset: coneOffset, sphereLabelOffset: sphereOffset, proofDepth: depth)
            try a.checkpoint(); return result
        }
    }
}
