import CADCore

/// Complete two connected closed curves and retained original UV request authority.
public final class OriginalFullConeConeSurfaceRelation: Sendable {
    public typealias Source = OriginalFullConeConeSurfaceSnapshot
    public typealias Field = Source.Field
    public typealias Selection = OriginalParameterSelection<OriginalAnalyticCoordinateSnapshot, Field>
    public let source: OriginalSourceBinding<Source>
    public let firstRequest: Selection
    public let secondRequest: Selection
    public let firstSupport: Selection
    public let secondSupport: Selection
    public let firstEffective: Selection
    public let secondEffective: Selection
    public let halfAngleDomain: ExactParameterDomain<Field>
    public let halfAngleSupport: ExactParameterSet<Field>
    public let isEmpty: Bool
    public let proofDepth: ExactScalarDepth
    public var hasPositiveDimensionalSolutions: Bool { !isEmpty }
    public var hasPositiveDimensionalImage: Bool { !isEmpty }
    public var imageDimension: Int? { isEmpty ? nil : 1 }
    public var fiberDimension: Int? { isEmpty ? nil : 0 }
    public var originalParameterDimension: Int { 4 }
    public var branchCount: Int { isEmpty ? 0 : 2 }
    private init(source: OriginalSourceBinding<Source>, firstRequest: Selection, secondRequest: Selection,
        firstSupport: Selection, secondSupport: Selection, firstEffective: Selection, secondEffective: Selection, halfAngleDomain: ExactParameterDomain<Field>,
        halfAngleSupport: ExactParameterSet<Field>, isEmpty: Bool, proofDepth: ExactScalarDepth) {
        self.source = source; self.firstRequest = firstRequest; self.secondRequest = secondRequest
        self.firstSupport = firstSupport; self.secondSupport = secondSupport
        self.firstEffective = firstEffective; self.secondEffective = secondEffective
        self.halfAngleDomain = halfAngleDomain; self.halfAngleSupport = halfAngleSupport
        self.isEmpty = isEmpty; self.proofDepth = proofDepth
    }
    public static func resolve<A: ExactScalarAdmission & ~Copyable>(source: OriginalSourceBinding<Source>,
        firstBox: SurfaceParameterBox?, secondBox: SurfaceParameterBox?, maximumComponents: Int,
        limits: OriginalDomainIdentityLimits, prepared: OriginalFullConeConeSurfaceRelation? = nil,
        using a: inout A) throws -> OriginalFullConeConeSurfaceRelation {
        return try OriginalSourceProofAdmission<A>.withBorrow(&a) { a in
            try a.checkpoint(); try source.require(limits.source); try requireLimits(limits)
            let s = source.original, f = s.field
            let issuer = DefaultOriginalAnalyticDomainIssuer<OriginalAnalyticCoordinateSnapshot, Field>()
            let firstFrame: OriginalParameterFrame<OriginalAnalyticCoordinateSnapshot, Field>
            let secondFrame: OriginalParameterFrame<OriginalAnalyticCoordinateSnapshot, Field>
            if let prepared {
                guard prepared.source.owns(try source.chart(0, limits: limits.source, using: &a)) else {
                    throw OriginalDomainIdentityFailure.foreignOwner
                }
                try prepared.admitProof(limits: limits, using: &a)
                firstFrame = prepared.firstRequest.frame; secondFrame = prepared.secondRequest.frame
            } else {
                firstFrame = try issuer.frame(law: s.firstLaw, limits: limits, using: &a)
                secondFrame = try issuer.frame(law: s.secondLaw, limits: limits, using: &a)
            }
            let fr = try request(firstFrame, box: firstBox, using: &a, limits: limits)
            let sr = try request(secondFrame, box: secondBox, using: &a, limits: limits)
            let firstSupport: Selection, secondSupport: Selection
            let firstEffective: Selection, secondEffective: Selection
            if let prepared {
                firstSupport = prepared.firstSupport; secondSupport = prepared.secondSupport
                firstEffective = try fr.intersection(firstSupport, limits: limits, using: &a)
                secondEffective = try sr.intersection(secondSupport, limits: limits, using: &a)
            } else {
                let fc = try issuer.issue(request: fr, law: s.firstLaw, limits: limits, using: &a)
                let sc = try issuer.issue(request: sr, law: s.secondLaw, limits: limits, using: &a)
                firstSupport = fc.support; secondSupport = sc.support
                firstEffective = fc.effective; secondEffective = sc.effective
            }
            var empty = firstEffective.isEmpty || secondEffective.isEmpty
            if let referenceBox = s.referenceIsFirst ? firstBox : secondBox {
                // Source-owned |lambda|<4 gives referenceZ>2.56 and V=Z/ca>2.56.
                // This is an exclusion over the entire selected reference domain.
                let upper = try f.binary64(exactly: referenceBox.v.upper, using: &a)
                let lower = try f.dividing(f.integer(64, using: &a), f.integer(25, using: &a), using: &a)
                if try f.compare(upper, lower, using: &a) != .greater { empty = true }
            }
        // FIXME(INCOMPLETE_IMPLEMENTATION): Ordinary/prepared full SSI owns
        // the full pair and proved selected exclusion. Other nonempty finite UV
        // requests require exact inverse-angle refinement before success.
        guard empty || (firstBox == nil && secondBox == nil) else { throw OriginalDomainIdentityFailure.incompleteCoverage }
        guard maximumComponents >= 0 else { throw OriginalDomainIdentityFailure.invalidDomain }
        guard empty || maximumComponents >= 2 else { throw NativeExactRelationFailure.resultLimit }
            let domain: ExactParameterDomain<Field>, support: ExactParameterSet<Field>
            if let prepared { domain = prepared.halfAngleDomain; support = prepared.halfAngleSupport }
            else {
                domain = try ExactParameterDomain(field: f, depth: s.proofDepth, using: &a)
                let interval = try domain.interval(lower: .finite(f.integer(-1, using: &a)), upper: .finite(f.integer(1, using: &a)), using: &a)
                try a.retainStorage(bytes: exactScalarPayloadBytes(count: 1, of: ExactParameterInterval<Field.Value>.self))
                support = try domain.set(intervals: [interval], using: &a)
            }
        let depth = try a.depth
        try a.retainStorage(bytes: MemoryLayout<(OriginalSourceBinding<Source>, Selection, Selection, Selection, Selection, Selection, Selection,
            ExactParameterDomain<Field>, ExactParameterSet<Field>, Bool, ExactScalarDepth)>.stride + 2 * MemoryLayout<UnsafeRawPointer>.stride)
        let relation = Self(source: source, firstRequest: fr, secondRequest: sr, firstSupport: firstSupport, secondSupport: secondSupport, firstEffective: firstEffective,
            secondEffective: secondEffective, halfAngleDomain: domain, halfAngleSupport: support, isEmpty: empty, proofDepth: depth)
        try a.checkpoint(); return relation
        }
    }
    public func admitProof<A: ExactScalarAdmission & ~Copyable>(limits: OriginalDomainIdentityLimits, using a: inout A) throws {
        try a.checkpoint(); try source.require(limits.source); try Self.requireLimits(limits)
        try a.admitDepth(value: proofDepth.value, coefficient: proofDepth.coefficient)
        try source.original.admitProof(using: &a)
        try source.original.firstLaw.admitProof(limits: limits.source, using: &a)
        try source.original.secondLaw.admitProof(limits: limits.source, using: &a)
        try firstRequest.frame.require(limits, &a); try secondRequest.frame.require(limits, &a)
        try a.checkpoint()
    }
    public func section<A: ExactScalarAdmission & ~Copyable>(chart: Int, halfAngle: Field.Value,
        limits: OriginalDomainIdentityLimits, using a: inout A) throws -> OriginalFullConeConeSurfaceSection {
        try admitProof(limits: limits, using: &a)
        guard !isEmpty, chart == 0 || chart == 1, try halfAngleDomain.contains(halfAngle, in: halfAngleSupport, using: &a) else {
            throw OriginalDomainIdentityFailure.outsideSupport
        }
        return try OriginalFullConeConeSurfaceSection.issue(relation: self, chart: chart, halfAngle: halfAngle, using: &a)
    }
    private static func requireLimits(_ limits: OriginalDomainIdentityLimits) throws {
        guard limits.maximumCharts >= 4 else { throw OriginalDomainIdentityFailure.chartLimit }
        guard limits.maximumFamilies >= 2 else { throw OriginalDomainIdentityFailure.familyLimit }
        guard limits.maximumTransportDepth >= 1 else { throw OriginalDomainIdentityFailure.transportDepthLimit }
    }
    private static func request<A: ExactScalarAdmission & ~Copyable>(
        _ frame: OriginalParameterFrame<OriginalAnalyticCoordinateSnapshot, Field>, box: SurfaceParameterBox?,
        using a: inout A, limits: OriginalDomainIdentityLimits) throws -> Selection {
        guard let box else { return try frame.fullSelection(limits: limits, using: &a) }
        let f = frame.scalarField, depth = try ExactScalarDepth(value: 0, coefficient: 0)
        try a.retainStorage(bytes: exactScalarPayloadBytes(count: 2, of: [ExactParameterInterval<Field.Value>].self))
        try a.retainStorage(bytes: exactScalarPayloadBytes(count: 2, of: ExactParameterInterval<Field.Value>.self))
        return try frame.selection(intervals: [[.checked(field: f,
            lower: .finite(f.binary64(exactly: box.u.lower, using: &a)), upper: .finite(f.binary64(exactly: box.u.upper, using: &a)), depth: depth, using: &a)],
            [.checked(field: f, lower: .finite(f.binary64(exactly: box.v.lower, using: &a)),
            upper: .finite(f.binary64(exactly: box.v.upper, using: &a)), depth: depth, using: &a)]], limits: limits, using: &a)
    }
}
