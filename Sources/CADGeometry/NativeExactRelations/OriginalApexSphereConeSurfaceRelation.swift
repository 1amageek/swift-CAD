import CADCore

/// One connected stratified image and retained original UV request authority.
public final class OriginalApexSphereConeSurfaceRelation: Sendable {
    public typealias Source = OriginalApexSphereConeSurfaceSnapshot
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
    public let isApexOnly: Bool
    public let apexFiberDimension: Int?
    public let isEmpty: Bool
    public let proofDepth: ExactScalarDepth
    public var hasPositiveDimensionalSolutions: Bool { !isEmpty && (!isApexOnly || (apexFiberDimension ?? 0)>0) }
    public var hasPositiveDimensionalImage: Bool { !isEmpty && !isApexOnly }
    public var imageDimension: Int? { isEmpty ? nil : isApexOnly ? 0:1 }
    public var fiberDimension: Int? { isApexOnly ? apexFiberDimension:nil }
    public var stratumCount: Int { isEmpty ? 0 : isApexOnly ? 1:3 }
    public var originalParameterDimension: Int { 4 }
    public var branchCount: Int { isEmpty || isApexOnly ? 0:2 }
    private init(source: OriginalSourceBinding<Source>, firstRequest: Selection, secondRequest: Selection,
        firstSupport: Selection, secondSupport: Selection, firstEffective: Selection, secondEffective: Selection, halfAngleDomain: ExactParameterDomain<Field>,
        halfAngleSupport: ExactParameterSet<Field>, isEmpty: Bool, isApexOnly:Bool, apexFiberDimension:Int?, proofDepth: ExactScalarDepth) {
        self.source = source; self.firstRequest = firstRequest; self.secondRequest = secondRequest
        self.firstSupport = firstSupport; self.secondSupport = secondSupport
        self.firstEffective = firstEffective; self.secondEffective = secondEffective
        self.halfAngleDomain = halfAngleDomain; self.halfAngleSupport = halfAngleSupport
        self.isEmpty = isEmpty;self.isApexOnly=isApexOnly;self.apexFiberDimension=apexFiberDimension; self.proofDepth = proofDepth
    }
    public static func resolve<A: ExactScalarAdmission & ~Copyable>(source: OriginalSourceBinding<Source>,
        firstBox: SurfaceParameterBox?, secondBox: SurfaceParameterBox?, maximumComponents: Int,
        limits: OriginalDomainIdentityLimits, prepared: OriginalApexSphereConeSurfaceRelation? = nil,
        using a: inout A) throws -> OriginalApexSphereConeSurfaceRelation {
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
            let cone=s.sphereIsFirst ? secondEffective:firstEffective
            let sphere=s.sphereIsFirst ? firstEffective:secondEffective
            let zero=try f.integer(0,using:&a)
            let coneBox=s.sphereIsFirst ? secondBox:firstBox
            let apexOnly=coneBox.map { $0.v.lower==0 && $0.v.upper==0 } ?? false
            if apexOnly && !empty {
                let sphereZero=try sphere.frame.axisDomains[1].contains(zero,in:sphere.axes[1],using:&a)
                if sphereZero { empty = try !Self.hasSphereApexU(sphere,period:s.labelPeriod,using:&a) } else { empty=true }
            }
            if let sphereBox = s.sphereIsFirst ? firstBox : secondBox {
                // All common points have X >= 1-2*(1/2)^2 > 0.
                // Canonical sphere labels in [0,B/2] have X=-rho*sin(theta)<=0.
                let lower = try f.binary64(exactly: sphereBox.u.lower, using: &a)
                let upper = try f.binary64(exactly: sphereBox.u.upper, using: &a)
                let half = try f.dividing(s.labelPeriod, f.integer(2, using: &a), using: &a)
                if try f.compare(lower, f.integer(0, using: &a), using: &a) != .less,
                    try f.compare(upper, half, using: &a) != .greater { empty = true }
            }
            let apexDimension = empty ? nil:try Self.coneUDimension(cone,using:&a)
        // FIXME(INCOMPLETE_IMPLEMENTATION): Ordinary/prepared full SSI owns
        // the full pair and proved selected exclusion. Other nonempty finite UV
        // requests require exact inverse-angle refinement before success.
        guard empty || apexOnly || (firstBox == nil && secondBox == nil) else { throw OriginalDomainIdentityFailure.incompleteCoverage }
        guard maximumComponents >= 0 else { throw OriginalDomainIdentityFailure.invalidDomain }
        guard empty || maximumComponents >= 1 else { throw NativeExactRelationFailure.resultLimit }
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
            ExactParameterDomain<Field>, ExactParameterSet<Field>, Bool, Bool, Int?, ExactScalarDepth)>.stride + 2 * MemoryLayout<UnsafeRawPointer>.stride)
        let relation = Self(source: source, firstRequest: fr, secondRequest: sr, firstSupport: firstSupport, secondSupport: secondSupport, firstEffective: firstEffective,
            secondEffective: secondEffective, halfAngleDomain: domain, halfAngleSupport: support, isEmpty: empty, isApexOnly:apexOnly, apexFiberDimension:apexDimension, proofDepth: depth)
        try a.checkpoint(); return relation
        }
    }
    public func admitProof<A: ExactScalarAdmission & ~Copyable>(limits: OriginalDomainIdentityLimits, using a: inout A) throws {
        try a.checkpoint(); try source.require(limits.source); try Self.requireLimits(limits)
        try a.admitDepth(value: proofDepth.value, coefficient: proofDepth.coefficient)
        try source.original.firstLaw.admitProof(limits: limits.source, using: &a)
        try source.original.secondLaw.admitProof(limits: limits.source, using: &a)
        try firstRequest.frame.require(limits, &a); try secondRequest.frame.require(limits, &a)
        try a.checkpoint()
    }
    public func section<A: ExactScalarAdmission & ~Copyable>(chart: Int, halfAngle: Field.Value,
        limits: OriginalDomainIdentityLimits, using a: inout A) throws -> OriginalApexSphereConeSurfaceSection {
        try admitProof(limits: limits, using: &a)
        guard !isEmpty,!isApexOnly, chart == 0 || chart == 1, try halfAngleDomain.contains(halfAngle, in: halfAngleSupport, using: &a) else {
            throw OriginalDomainIdentityFailure.outsideSupport
        }
        return try OriginalApexSphereConeSurfaceSection.issue(relation: self, chart: chart, halfAngle: halfAngle, using: &a)
    }
    public func apex<A: ExactScalarAdmission & ~Copyable>(coneU: Field.Value,
        sphereCycle: OriginalParameterCycle, limits: OriginalDomainIdentityLimits,
        using a: inout A) throws -> OriginalApexSphereConeSurfaceMember {
        try admitProof(limits: limits, using: &a)
        guard !isEmpty else { throw OriginalDomainIdentityFailure.outsideSupport }
        let f = source.original.field
        let u = try f.importing(coneU, using: &a)
        let offset = try f.multiplying(source.original.labelPeriod, sphereCycle.scalar(in: f, using: &a), using: &a)
        let zero=try f.integer(0,using:&a)
        let sphereU=try f.subtracting(offset,f.dividing(source.original.labelPeriod,f.integer(4,using:&a),using:&a),using:&a)
        let cone=source.original.sphereIsFirst ? secondEffective:firstEffective
        let sphere=source.original.sphereIsFirst ? firstEffective:secondEffective
        try a.retainStorage(bytes:exactScalarPayloadBytes(count:4,of:Field.Value.self))
        guard try cone.contains([u,zero],limits:limits,using:&a),
            try sphere.contains([sphereU,zero],limits:limits,using:&a) else { throw OriginalDomainIdentityFailure.outsideSupport }
        return try OriginalApexSphereConeSurfaceMember.apex(relation: self, coneU: u, sphereOffset: offset, using: &a)
    }
    public func apexIdentity<A:ExactScalarAdmission & ~Copyable>(limits:OriginalDomainIdentityLimits,
        using a:inout A) throws -> OriginalParameterIdentity<OriginalAnalyticCoordinateSnapshot,Field> {
        try admitProof(limits:limits,using:&a)
        guard !isEmpty else { throw OriginalDomainIdentityFailure.outsideSupport }
        let selected=source.original.sphereIsFirst ? secondEffective:firstEffective
        let law=source.original.sphereIsFirst ? source.original.secondLaw:source.original.firstLaw
        let frame=selected.frame,zero=try source.original.field.integer(0,using:&a)
        let u=try frame.axisDomains[0].interval(lower:.negativeInfinity,upper:.positiveInfinity,using:&a)
        let v=try frame.axisDomains[1].interval(lower:.finite(zero),upper:.finite(zero),using:&a)
        try a.retainStorage(bytes:exactScalarPayloadBytes(count:2,of:[ExactParameterInterval<Field.Value>].self))
        try a.retainStorage(bytes:exactScalarPayloadBytes(count:2,of:ExactParameterInterval<Field.Value>.self))
        let scope=try selected.intersection(frame.selection(intervals:[[u],[v]],limits:limits,using:&a),limits:limits,using:&a)
        let cover=try DefaultOriginalAnalyticDomainIssuer<OriginalAnalyticCoordinateSnapshot,Field>().issue(request:scope,law:law,limits:limits,using:&a)
        return try DefaultOriginalParameterIdentityIssuer<OriginalAnalyticCoordinateSnapshot,Field>().collapsed(cover:cover,on:scope,fiber:0,limits:limits,using:&a)
    }
    private static func coneUDimension<A:ExactScalarAdmission & ~Copyable>(_ cone:Selection,using a:inout A) throws -> Int {
        for i in cone.axes[0].intervals {
            guard case .finite(let lo)=i.lower,case .finite(let hi)=i.upper else { return 1 }
            if try cone.frame.scalarField.compare(lo,hi,using:&a) != .equal { return 1 }
        }
        return 0
    }
    private static func hasSphereApexU<A:ExactScalarAdmission & ~Copyable>(_ sphere:Selection,
        period:Field.Value,using a:inout A) throws -> Bool {
        let f=sphere.frame.scalarField,quarter=try f.dividing(period,f.integer(4,using:&a),using:&a)
        for i in sphere.axes[0].intervals {
            try a.consumeWork(1)
            guard case .finite(let lower)=i.lower,case .finite(let upper)=i.upper else { return true }
            let lo=try f.dividing(f.adding(lower,quarter,using:&a),period,using:&a)
            let hi=try f.dividing(f.adding(upper,quarter,using:&a),period,using:&a)
            var k=try OriginalParameterCycle.floor(lo,field:f,using:&a).scalar(in:f,using:&a)
            if try f.compare(k,lo,using:&a) != .equal || !i.includesLower { k=try f.adding(k,f.integer(1,using:&a),using:&a) }
            let order=try f.compare(k,hi,using:&a)
            if order == .less || order == .equal && i.includesUpper { return true }
        }
        return false
    }
    private static func requireLimits(_ limits: OriginalDomainIdentityLimits) throws {
        guard limits.maximumCharts >= 2 else { throw OriginalDomainIdentityFailure.chartLimit }
        guard limits.maximumFamilies >= 3 else { throw OriginalDomainIdentityFailure.familyLimit }
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
