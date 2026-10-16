import CADCore

/// Complete original selected curve or point and retained UV request authority.
public final class OriginalBoundedSphereConeSurfaceRelation: Sendable {
    public typealias Source = OriginalBoundedSphereConeSurfaceSnapshot
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
    /// Materialized for nonempty unbounded publication; finite/empty results and internal preparation have none.
    public let halfAngleSupport: ExactParameterSet<Field>?
    public let isEmpty: Bool
    public let finiteArc: OriginalBoundedSphereConeSurfaceFiniteArcReceipt?
    public let finiteCut: OriginalBoundedSphereConeSurfaceFiniteCutReceipt?
    public let proofDepth: ExactScalarDepth
    public var hasPositiveDimensionalSolutions: Bool { imageDimension == 1 }
    public var hasPositiveDimensionalImage: Bool { imageDimension == 1 }
    public var imageDimension: Int? { isEmpty ? nil : finiteCut?.imageDimension ?? finiteArc?.imageDimension ?? 1 }
    public var fiberDimension: Int? { isEmpty ? nil : 0 }
    public var originalParameterDimension: Int { 4 }
    public var branchCount: Int { isEmpty ? 0 : finiteArc == nil && finiteCut == nil ? 2 : 1 }
    private init(source: OriginalSourceBinding<Source>, firstRequest: Selection, secondRequest: Selection,
        firstSupport: Selection, secondSupport: Selection, firstEffective: Selection, secondEffective: Selection, halfAngleDomain: ExactParameterDomain<Field>,
        halfAngleSupport: ExactParameterSet<Field>?, isEmpty: Bool, finiteArc: OriginalBoundedSphereConeSurfaceFiniteArcReceipt?,
        finiteCut: OriginalBoundedSphereConeSurfaceFiniteCutReceipt?, proofDepth: ExactScalarDepth) {
        self.source = source; self.firstRequest = firstRequest; self.secondRequest = secondRequest
        self.firstSupport = firstSupport; self.secondSupport = secondSupport
        self.firstEffective = firstEffective; self.secondEffective = secondEffective
        self.halfAngleDomain = halfAngleDomain; self.halfAngleSupport = halfAngleSupport
        self.isEmpty = isEmpty; self.finiteArc = finiteArc; self.finiteCut = finiteCut; self.proofDepth = proofDepth
    }
    public static func resolve(source: OriginalSourceBinding<Source>,
        firstBox: SurfaceParameterBox?, secondBox: SurfaceParameterBox?, maximumComponents: Int,
        tolerance: ModelingTolerance,
        limits: OriginalDomainIdentityLimits, prepared: OriginalBoundedSphereConeSurfaceRelation? = nil,
        using a: inout OriginalQueryExecution) throws -> OriginalBoundedSphereConeSurfaceRelation {
        try resolve(source: source, firstBox: firstBox, secondBox: secondBox,
            maximumComponents: maximumComponents, tolerance: tolerance, limits: limits,
            prepared: prepared, purpose: .publication, using: &a)
    }
    static func prepare(source: OriginalSourceBinding<Source>, maximumComponents: Int,
        tolerance: ModelingTolerance, limits: OriginalDomainIdentityLimits,
        using a: inout OriginalQueryExecution) throws -> OriginalBoundedSphereConeSurfaceRelation {
        try resolve(source: source, firstBox: nil, secondBox: nil,
            maximumComponents: maximumComponents, tolerance: tolerance, limits: limits,
            prepared: nil, purpose: .preparation, using: &a)
    }
    private enum ResolutionPurpose: Equatable { case publication, preparation }
    private static func resolve(source: OriginalSourceBinding<Source>,
        firstBox: SurfaceParameterBox?, secondBox: SurfaceParameterBox?, maximumComponents: Int,
        tolerance: ModelingTolerance, limits: OriginalDomainIdentityLimits,
        prepared: OriginalBoundedSphereConeSurfaceRelation?, purpose: ResolutionPurpose,
        using a: inout OriginalQueryExecution) throws -> OriginalBoundedSphereConeSurfaceRelation {
        return try a.withProofScope() { a in
            try a.checkpoint(); try source.require(limits.source); try requireLimits(limits)
            try a.admitSourceDepth(source.sourceDepth)
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
            if let coneBox = s.sphereIsFirst ? secondBox : firstBox {
                // Whole-pair equality implies Z>=center.z-radius. This slant bound
                // excludes the complete selected domain, independently of UV samples.
                let upper = try f.binary64(exactly: coneBox.v.upper, using: &a)
                let maximumZ = try f.adding(f.binary64(exactly:s.apex.z,using:&a), f.multiplying(s.cosine, upper, using: &a), using: &a)
                if try f.compare(maximumZ,f.subtracting(f.binary64(exactly:s.sphereCenter.z,using:&a),f.binary64(exactly:s.sphereRadius,using:&a),using:&a),using:&a) == .less { empty = true }
        }
            let finiteArc: OriginalBoundedSphereConeSurfaceFiniteArcReceipt?
            let finiteCut: OriginalBoundedSphereConeSurfaceFiniteCutReceipt?
            if !empty && (firstBox != nil || secondBox != nil) {
                guard let firstBox, let secondBox else { throw OriginalSourceIssuanceFailure.unsupportedRepresentation }
                switch try OriginalBoundedSphereConeSurfaceFiniteCutReceipt.resolve(source: source,
                    firstBox: firstBox, secondBox: secondBox, tolerance: tolerance, limits: limits.source,
                    maximumSpanCount: a.effectiveLimits.maximumSpans,
                    maximumSubdivisionDepth: a.effectiveLimits.maximumSubdivisionDepth,
                    maximumAlgebraicDepth: max(a.effectiveLimits.maximumValueDepth, a.effectiveLimits.maximumCoefficientDepth),
                    using: &a) {
                case .selected(let arc): finiteArc = arc; finiteCut = nil
                case .cut(let cut): finiteArc = nil; finiteCut = cut
                case .empty(let exclusion): finiteArc = nil; finiteCut = exclusion; empty = true
                }
            } else { finiteArc = nil; finiteCut = nil }
        guard maximumComponents >= 0 else { throw OriginalDomainIdentityFailure.invalidDomain }
        guard empty || maximumComponents >= 1 else { throw NativeExactRelationFailure.resultLimit }
            let domain: ExactParameterDomain<Field>
            if let prepared { domain = prepared.halfAngleDomain }
            else { domain = try ExactParameterDomain(field: s.criticalField, depth: s.proofDepth, using: &a) }
            let support: ExactParameterSet<Field>?
            if purpose == .publication && !empty && finiteArc == nil && finiteCut == nil {
                if let retained = prepared?.halfAngleSupport { support = retained }
                else {
                    let interval = try domain.interval(lower: .finite(s.lowerHalfAngle), upper: .finite(s.upperHalfAngle), using: &a)
                    try a.retainStorage(bytes: exactScalarPayloadBytes(count: 1, of: ExactParameterInterval<Field.Value>.self))
                    support = try domain.set(intervals: [interval], using: &a)
                }
            } else { support = nil }
        let depth = try a.depth
        try a.retainStorage(bytes: MemoryLayout<(OriginalSourceBinding<Source>, Selection, Selection, Selection, Selection, Selection, Selection,
            ExactParameterDomain<Field>, ExactParameterSet<Field>?, Bool, OriginalBoundedSphereConeSurfaceFiniteArcReceipt?,
            OriginalBoundedSphereConeSurfaceFiniteCutReceipt?, ExactScalarDepth)>.stride + 2 * MemoryLayout<UnsafeRawPointer>.stride)
        let relation = Self(source: source, firstRequest: fr, secondRequest: sr, firstSupport: firstSupport, secondSupport: secondSupport, firstEffective: firstEffective,
            secondEffective: secondEffective, halfAngleDomain: domain, halfAngleSupport: support, isEmpty: empty,
            finiteArc: finiteArc, finiteCut: finiteCut, proofDepth: depth)
        try a.checkpoint(); return relation
        }
    }
    public func admitProof(limits: OriginalDomainIdentityLimits, using a: inout OriginalQueryExecution) throws {
        try a.checkpoint(); try source.require(limits.source); try Self.requireLimits(limits)
        try a.admitSourceDepth(source.sourceDepth)
        try a.admitDepth(value: proofDepth.value, coefficient: proofDepth.coefficient)
        try source.original.firstLaw.admitProof(limits: limits.source, using: &a)
        try source.original.secondLaw.admitProof(limits: limits.source, using: &a)
        try firstRequest.frame.require(limits, &a); try secondRequest.frame.require(limits, &a)
        try finiteArc?.admitProof(using: &a)
        try finiteCut?.admitProof(limits: limits.source, using: &a)
        try a.checkpoint()
    }
    public func section(halfAngle: Field.Value,
        limits: OriginalDomainIdentityLimits, using a: inout OriginalQueryExecution) throws -> OriginalBoundedSphereConeSurfaceSection {
        try admitProof(limits: limits, using: &a)
        // FIXME(INCOMPLETE_IMPLEMENTATION): Finite SSI uses source-owned raw cone-U
        // membership. The legacy half-angle query cannot prove finite UV membership
        // and must remain failure until that exact inverse query is source-supported.
        guard finiteArc == nil && finiteCut == nil else { throw OriginalDomainIdentityFailure.incompleteCoverage }
        guard !isEmpty else { throw OriginalDomainIdentityFailure.outsideSupport }
        guard let halfAngleSupport else { throw OriginalDomainIdentityFailure.invalidDomain }
        guard try halfAngleDomain.contains(halfAngle, in: halfAngleSupport, using: &a) else {
            throw OriginalDomainIdentityFailure.outsideSupport
        }
        return try OriginalBoundedSphereConeSurfaceSection.issue(relation: self, halfAngle: halfAngle, using: &a)
    }
    public func member(coneU: Field.Value, branch: Int,
        coneCycle: OriginalParameterCycle, sphereCycle: OriginalParameterCycle,
        limits: OriginalDomainIdentityLimits, using a: inout OriginalQueryExecution) throws -> OriginalBoundedSphereConeSurfaceArcMember {
        try admitProof(limits: limits, using: &a)
        return try a.withProofScope() { a in
            try a.admitDepth(value: proofDepth.value, coefficient: proofDepth.coefficient)
            guard !isEmpty else { throw OriginalDomainIdentityFailure.outsideSupport }
            // FIXME(INCOMPLETE_IMPLEMENTATION): The algebraic scalar argument
            // cannot represent the implicit finite cut endpoint. Cut queries
            // use an exact authored binary64 label or the retained boundary root;
            // general algebraic-label ordering against that root remains unsupported.
            guard finiteCut == nil else { throw OriginalDomainIdentityFailure.incompleteCoverage }
            guard !isEmpty, let finiteArc, branch == finiteArc.branch else {
                throw OriginalDomainIdentityFailure.outsideSupport
            }
            guard try finiteArc.accepts(coneCycle: coneCycle.original, sphereCycle: sphereCycle.original, using: &a) else {
                throw OriginalDomainIdentityFailure.outsideSupport
            }
            let position = try finiteArc.position(coneU: coneU, using: &a)
            try a.retainStorage(bytes: exactScalarPayloadBytes(count: 1, of: OriginalBoundedSphereConeSurfaceArcMember.self))
            let result = OriginalBoundedSphereConeSurfaceArcMember(relation: self, position: position)
            try a.checkpoint(); return result
        }
    }

    public func member(coneU rawU: Double, branch: Int,
        coneCycle: OriginalParameterCycle, sphereCycle: OriginalParameterCycle,
        limits: OriginalDomainIdentityLimits, using a: inout OriginalQueryExecution)
        throws -> OriginalBoundedSphereConeSurfaceArcMember {
        try admitProof(limits: limits, using: &a)
        return try a.withProofScope { a in
            try a.admitDepth(value: proofDepth.value, coefficient: proofDepth.coefficient)
            let position: OriginalBoundedSphereConeSurfaceFiniteArcPosition
            if let finiteCut {
                position = try finiteCut.position(coneU: rawU, branch: branch,
                    coneCycle: coneCycle, sphereCycle: sphereCycle, limits: limits.source, using: &a)
            } else {
                guard !isEmpty, let finiteArc, branch == finiteArc.branch,
                    try finiteArc.accepts(coneCycle: coneCycle.original, sphereCycle: sphereCycle.original, using: &a) else {
                    throw OriginalDomainIdentityFailure.outsideSupport
                }
                let u = try source.original.field.binary64(exactly: rawU, using: &a)
                position = try finiteArc.position(coneU: u, using: &a)
            }
            try a.retainStorage(count: 1, stride: MemoryLayout<OriginalBoundedSphereConeSurfaceArcMember>.stride)
            let member = OriginalBoundedSphereConeSurfaceArcMember(relation: self, position: position)
            try a.checkpoint(); return member
        }
    }
    private static func requireLimits(_ limits: OriginalDomainIdentityLimits) throws {
        guard limits.maximumCharts >= 2 else { throw OriginalDomainIdentityFailure.chartLimit }
        guard limits.maximumFamilies >= 2 else { throw OriginalDomainIdentityFailure.familyLimit }
        guard limits.maximumTransportDepth >= 1 else { throw OriginalDomainIdentityFailure.transportDepthLimit }
    }
    private static func request(
        _ frame: OriginalParameterFrame<OriginalAnalyticCoordinateSnapshot, Field>, box: SurfaceParameterBox?,
        using a: inout OriginalQueryExecution, limits: OriginalDomainIdentityLimits) throws -> Selection {
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
