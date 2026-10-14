import CADCore

/// One connected stratified image and retained original UV request authority.
public final class OriginalCommonApexConeRelation: Sendable {
    public typealias Source = OriginalCommonApexConeSnapshot
    public typealias Field = Source.Field
    public typealias Selection = OriginalParameterSelection<OriginalAnalyticCoordinateSnapshot, Field>
    public let source: OriginalSourceBinding<Source>
    public let firstRequest: Selection
    public let secondRequest: Selection
    public let firstSupport: Selection
    public let secondSupport: Selection
    public let firstEffective: Selection
    public let secondEffective: Selection
    public let firstFiber: Selection
    public let secondFiber: Selection
    public let firstIdentity: OriginalParameterIdentity<OriginalAnalyticCoordinateSnapshot, Field>?
    public let secondIdentity: OriginalParameterIdentity<OriginalAnalyticCoordinateSnapshot, Field>?
    public let isEmpty: Bool
    public let proofDepth: ExactScalarDepth
    public let fiberDimension: Int?
    public var hasPositiveDimensionalSolutions: Bool { (fiberDimension ?? 0)>0 }
    public var hasPositiveDimensionalImage: Bool { false }
    public var imageDimension: Int? { isEmpty ? nil : 0 }
    public var originalParameterDimension: Int { 4 }
    private init(source: OriginalSourceBinding<Source>, firstRequest: Selection, secondRequest: Selection,
        firstSupport: Selection, secondSupport: Selection, firstEffective: Selection, secondEffective: Selection,
        firstFiber: Selection, secondFiber: Selection,
        firstIdentity: OriginalParameterIdentity<OriginalAnalyticCoordinateSnapshot, Field>?,
        secondIdentity: OriginalParameterIdentity<OriginalAnalyticCoordinateSnapshot, Field>?,
        fiberDimension: Int?, proofDepth: ExactScalarDepth) {
        self.source=source; self.firstRequest=firstRequest; self.secondRequest=secondRequest
        self.firstSupport=firstSupport; self.secondSupport=secondSupport
        self.firstEffective=firstEffective; self.secondEffective=secondEffective
        self.firstFiber=firstFiber; self.secondFiber=secondFiber
        self.firstIdentity=firstIdentity; self.secondIdentity=secondIdentity
        self.isEmpty=firstFiber.isEmpty || secondFiber.isEmpty
        self.fiberDimension=fiberDimension; self.proofDepth=proofDepth
    }
    public static func resolve<A: ExactScalarAdmission & ~Copyable>(source: OriginalSourceBinding<Source>,
        firstBox: SurfaceParameterBox?, secondBox: SurfaceParameterBox?, maximumComponents: Int,
        limits: OriginalDomainIdentityLimits, prepared: OriginalCommonApexConeRelation? = nil,
        using a: inout A) throws -> OriginalCommonApexConeRelation {
        return try OriginalSourceProofAdmission<A>.withBorrow(&a) { a in
            try a.checkpoint(); try source.require(limits.source); try requireLimits(limits)
            let s = source.original
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
            let ff = try fiber(firstEffective, limits: limits, using: &a)
            let sf = try fiber(secondEffective, limits: limits, using: &a)
            let empty = ff.isEmpty || sf.isEmpty
            guard maximumComponents >= 0 else { throw OriginalDomainIdentityFailure.invalidDomain }
            guard empty || maximumComponents >= 1 else { throw NativeExactRelationFailure.resultLimit }
            let fi: OriginalParameterIdentity<OriginalAnalyticCoordinateSnapshot, Field>?
            let si: OriginalParameterIdentity<OriginalAnalyticCoordinateSnapshot, Field>?
            if empty { fi=nil; si=nil }
            else {
                let identity = DefaultOriginalParameterIdentityIssuer<OriginalAnalyticCoordinateSnapshot, Field>()
                let fc = try issuer.issue(request: ff, law: s.firstLaw, limits: limits, using: &a)
                let sc = try issuer.issue(request: sf, law: s.secondLaw, limits: limits, using: &a)
                fi = try identity.collapsed(cover: fc, on: ff, fiber: 0, limits: limits, using: &a)
                si = try identity.collapsed(cover: sc, on: sf, fiber: 0, limits: limits, using: &a)
            }
            let dimension = empty ? nil : try axisDimension(ff, using: &a)+axisDimension(sf, using: &a)
            try a.retainStorage(bytes: MemoryLayout<(OriginalSourceBinding<Source>, Selection, Selection, Selection, Selection, Selection, Selection, Selection, Selection,
                OriginalParameterIdentity<OriginalAnalyticCoordinateSnapshot, Field>?, OriginalParameterIdentity<OriginalAnalyticCoordinateSnapshot, Field>?, Bool, Int?, ExactScalarDepth)>.stride+2*MemoryLayout<UnsafeRawPointer>.stride)
            let relation = Self(source: source, firstRequest: fr, secondRequest: sr, firstSupport: firstSupport,
                secondSupport: secondSupport, firstEffective: firstEffective, secondEffective: secondEffective,
                firstFiber: ff, secondFiber: sf, firstIdentity: fi, secondIdentity: si, fiberDimension: dimension, proofDepth: try a.depth)
            try a.checkpoint(); return relation
        }
    }
    private static func fiber<A: ExactScalarAdmission & ~Copyable>(_ selected: Selection,
        limits: OriginalDomainIdentityLimits, using a: inout A) throws -> Selection {
        let frame=selected.frame, zero=try frame.scalarField.integer(0, using: &a)
        let singleton=try frame.axisDomains[1].interval(lower: .finite(zero), upper: .finite(zero), using: &a)
        try a.retainStorage(bytes: exactScalarPayloadBytes(count: 2, of: [ExactParameterInterval<Field.Value>].self))
        try a.retainStorage(bytes: exactScalarPayloadBytes(count: 2, of: ExactParameterInterval<Field.Value>.self))
        let whole=try frame.axisDomains[0].interval(lower: .negativeInfinity, upper: .positiveInfinity, using: &a)
        return try selected.intersection(frame.selection(intervals: [[whole], [singleton]], limits: limits, using: &a), limits: limits, using: &a)
    }
    private static func axisDimension<A: ExactScalarAdmission & ~Copyable>(_ selected: Selection,
        using a: inout A) throws -> Int {
        for i in selected.axes[0].intervals {
            try a.consumeWork(1)
            guard case .finite(let lo)=i.lower, case .finite(let hi)=i.upper else { return 1 }
            if try selected.frame.scalarField.compare(lo,hi,using:&a) != .equal { return 1 }
        }
        return 0
    }
    public func admitProof<A: ExactScalarAdmission & ~Copyable>(limits: OriginalDomainIdentityLimits, using a: inout A) throws {
        try a.checkpoint(); try source.require(limits.source); try Self.requireLimits(limits)
        try a.admitDepth(value: proofDepth.value, coefficient: proofDepth.coefficient)
        try source.original.firstLaw.admitProof(limits: limits.source, using: &a)
        try source.original.secondLaw.admitProof(limits: limits.source, using: &a)
        try firstRequest.frame.require(limits, &a); try secondRequest.frame.require(limits, &a)
        try a.checkpoint()
    }
    public func member<A: ExactScalarAdmission & ~Copyable>(firstU: Field.Value, secondU: Field.Value,
        limits: OriginalDomainIdentityLimits, using a: inout A) throws -> OriginalCommonApexConeMember {
        try OriginalSourceProofAdmission<A>.withBorrow(&a) { a in
            try admitProof(limits: limits, using: &a)
            let f=source.original.field,zero=try f.integer(0,using:&a)
            guard !isEmpty, try firstFiber.frame.axisDomains[0].contains(firstU,in:firstFiber.axes[0],using:&a),
                try secondFiber.frame.axisDomains[0].contains(secondU,in:secondFiber.axes[0],using:&a) else { throw OriginalDomainIdentityFailure.outsideSupport }
            try a.retainStorage(bytes: exactScalarPayloadBytes(count:1,of:OriginalCommonApexConeMember.self))
            let result=OriginalCommonApexConeMember(relation:self,firstU:firstU,secondU:secondU,zero:zero,proofDepth:try a.depth)
            try a.checkpoint(); return result
        }
    }
    private static func requireLimits(_ limits: OriginalDomainIdentityLimits) throws {
        guard limits.maximumCharts >= 2 else { throw OriginalDomainIdentityFailure.chartLimit }
        guard limits.maximumFamilies >= 2 else { throw OriginalDomainIdentityFailure.familyLimit }
        guard limits.maximumIdentityProofs >= 2 else { throw OriginalDomainIdentityFailure.identityLimit }
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
