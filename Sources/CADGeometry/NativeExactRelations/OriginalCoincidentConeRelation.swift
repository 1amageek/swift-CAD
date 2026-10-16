import CADCore

/// One connected stratified image and retained original UV request authority.
public final class OriginalCoincidentConeRelation: Sendable {
    public typealias Source = OriginalCoincidentConeSnapshot
    public typealias Field = Source.Field
    public typealias Selection = OriginalParameterSelection<OriginalAnalyticCoordinateSnapshot, Field>
    public let source: OriginalSourceBinding<Source>
    public let firstRequest: Selection
    public let secondRequest: Selection
    public let firstSupport: Selection
    public let secondSupport: Selection
    public let firstEffective: Selection
    public let secondEffective: Selection
    public struct Piece: Sendable {
        public let phase: Int
        public let otherPhase: Int?
        public let includesApex: Bool
        public let imageDimension: Int
    }
    public let firstFiber: Selection
    public let secondFiber: Selection
    public let firstIdentity: OriginalParameterIdentity<OriginalAnalyticCoordinateSnapshot,Field>?
    public let secondIdentity: OriginalParameterIdentity<OriginalAnalyticCoordinateSnapshot,Field>?
    public let phaseDomain: ExactParameterDomain<Field>
    public let phase: ExactParameterSet<Field>
    public let slantDomain: ExactParameterDomain<Field>
    public let regularSlants: ExactParameterSet<Field>
    public let apexFiberDimension: Int?
    private let storage: [Piece]
    public var pieces: ArraySlice<Piece> { storage[...] }
    public var isEmpty: Bool { storage.isEmpty }
    public var hasRegular: Bool { !phase.isEmpty && !regularSlants.isEmpty }
    public var hasApex: Bool { apexFiberDimension != nil }
    public var hasPositiveDimensionalSolutions: Bool { storage.contains { $0.imageDimension>0 } || (apexFiberDimension ?? 0)>0 }
    public var hasPositiveDimensionalImage: Bool { storage.contains { $0.imageDimension>0 } }
    public let proofDepth: ExactScalarDepth
    public var originalParameterDimension: Int { 4 }
    private init(source:OriginalSourceBinding<Source>,firstRequest:Selection,secondRequest:Selection,
        firstSupport:Selection,secondSupport:Selection,firstEffective:Selection,secondEffective:Selection,
        firstFiber:Selection,secondFiber:Selection,firstIdentity:OriginalParameterIdentity<OriginalAnalyticCoordinateSnapshot,Field>?,
        secondIdentity:OriginalParameterIdentity<OriginalAnalyticCoordinateSnapshot,Field>?,phaseDomain:ExactParameterDomain<Field>,
        phase:ExactParameterSet<Field>,slantDomain:ExactParameterDomain<Field>,regularSlants:ExactParameterSet<Field>,
        apexFiberDimension:Int?,storage:[Piece],proofDepth:ExactScalarDepth) {
        self.source=source;self.firstRequest=firstRequest;self.secondRequest=secondRequest
        self.firstSupport=firstSupport;self.secondSupport=secondSupport
        self.firstEffective=firstEffective;self.secondEffective=secondEffective
        self.firstFiber=firstFiber;self.secondFiber=secondFiber;self.firstIdentity=firstIdentity;self.secondIdentity=secondIdentity
        self.phaseDomain=phaseDomain;self.phase=phase;self.slantDomain=slantDomain;self.regularSlants=regularSlants
        self.apexFiberDimension=apexFiberDimension;self.storage=storage;self.proofDepth=proofDepth
    }
    public static func resolve<A: ExactScalarAdmission & ~Copyable>(source: OriginalSourceBinding<Source>,
        firstBox: SurfaceParameterBox?, secondBox: SurfaceParameterBox?, maximumComponents: Int,
        limits: OriginalDomainIdentityLimits, prepared: OriginalCoincidentConeRelation? = nil,
        using a: inout A) throws -> OriginalCoincidentConeRelation {
        return try a.withProofScope() { a in
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
            let f=s.field,zero=try f.integer(0,using:&a),one=try f.integer(1,using:&a)
            let phaseDomain: ExactParameterDomain<Field>
            if let prepared { phaseDomain=prepared.phaseDomain }
            else { phaseDomain=try ExactParameterDomain(field:f,depth:s.proofDepth,using:&a) }
            let fp=try OriginalCoaxialAngularSelection.residue(axis:firstEffective.axes[0],offset:zero,
                period:s.labelPeriod,field:f,domain:phaseDomain,using:&a)
            let sp=try OriginalCoaxialAngularSelection.residue(axis:secondEffective.axes[0],offset:zero,
                period:s.labelPeriod,field:f,domain:phaseDomain,using:&a)
            let phase=try phaseDomain.intersection(fp,sp,using:&a)
            // The source equality authorizes this checked identity coordinate rebase.
            try a.retainStorage(bytes:exactScalarPayloadBytes(count:4,of:Field.Value.self))
            try a.retainStorage(bytes:exactScalarPayloadBytes(count:2,of:Int.self))
            let secondInFirst=try secondEffective.coordinateImage(to:firstFrame,permutation:[0,1],gains:[one,one],offsets:[zero,zero],limits:limits,using:&a)
            let slantDomain=firstFrame.axisDomains[1]
            let slants=try slantDomain.intersection(firstEffective.axes[1],secondInFirst.axes[1],using:&a)
            let z=try slantDomain.interval(lower:.finite(zero),upper:.finite(zero),using:&a)
            try a.retainStorage(bytes:exactScalarPayloadBytes(count:1,of:ExactParameterInterval<Field.Value>.self))
            let singleton=try slantDomain.set(intervals:[z],using:&a)
            let regular=try slantDomain.difference(slants,singleton,using:&a)
            let ff=try fiber(firstEffective,limits:limits,using:&a),sf=try fiber(secondEffective,limits:limits,using:&a)
            let apex = !ff.isEmpty && !sf.isEmpty
            let fi: OriginalParameterIdentity<OriginalAnalyticCoordinateSnapshot,Field>?
            let si: OriginalParameterIdentity<OriginalAnalyticCoordinateSnapshot,Field>?
            if apex {
                let identity=DefaultOriginalParameterIdentityIssuer<OriginalAnalyticCoordinateSnapshot,Field>()
                let fc=try issuer.issue(request:ff,law:s.firstLaw,limits:limits,using:&a)
                let sc=try issuer.issue(request:sf,law:s.secondLaw,limits:limits,using:&a)
                fi=try identity.collapsed(cover:fc,on:ff,fiber:0,limits:limits,using:&a)
                si=try identity.collapsed(cover:sc,on:sf,fiber:0,limits:limits,using:&a)
            } else { fi=nil;si=nil }
            let apexDimension=apex ? try axisDimension(ff,using:&a)+axisDimension(sf,using:&a):nil
            let regularExists = !phase.isEmpty && !regular.isEmpty
            let vDimension=try dimension(regular,field:f,using:&a)
            var pieces:[Piece]=[]
            guard maximumComponents>=0 else { throw OriginalDomainIdentityFailure.invalidDomain }
            func reserve(_ count:Int) throws {
                guard count<=maximumComponents else { throw NativeExactRelationFailure.resultLimit }
            }
            if apex {
                try reserve(1);try a.retainStorage(bytes:exactScalarPayloadBytes(count:1,of:Piece.self));pieces.reserveCapacity(1)
                pieces.append(.init(phase:-1,otherPhase:nil,includesApex:true,
                    imageDimension:regularExists ? try dimension(phase,field:f,using:&a)+vDimension:0))
            } else if regularExists {
                let intervals=phase.intervals
                let joins=try intervals.count>1 && joinsSeam(intervals,field:f,using:&a)
                let count=intervals.count-(joins ? 1:0)
                try reserve(count);try a.retainStorage(bytes:exactScalarPayloadBytes(count:count,of:Piece.self));pieces.reserveCapacity(count)
                for i in intervals.indices {
                    try a.consumeWork(1)
                    if joins && i==intervals.index(before:intervals.endIndex) { continue }
                    let other = joins && i==intervals.startIndex ? intervals.index(before:intervals.endIndex):nil
                    let phaseDimension=try intervalDimension(intervals[i],field:f,using:&a)
                    let otherDimension=try other.map { try intervalDimension(intervals[$0],field:f,using:&a) } ?? 0
                    let dimension=max(phaseDimension,otherDimension)+vDimension
                    pieces.append(.init(phase:i,otherPhase:other,includesApex:false,imageDimension:dimension))
                }
            }
            try a.retainStorage(bytes:MemoryLayout<(OriginalSourceBinding<Source>,Selection,Selection,Selection,Selection,Selection,Selection,Selection,Selection,
                OriginalParameterIdentity<OriginalAnalyticCoordinateSnapshot,Field>?,OriginalParameterIdentity<OriginalAnalyticCoordinateSnapshot,Field>?,
                ExactParameterDomain<Field>,ExactParameterSet<Field>,ExactParameterDomain<Field>,ExactParameterSet<Field>,Int?,[Piece],ExactScalarDepth)>.stride+2*MemoryLayout<UnsafeRawPointer>.stride)
            let result=Self(source:source,firstRequest:fr,secondRequest:sr,firstSupport:firstSupport,secondSupport:secondSupport,
                firstEffective:firstEffective,secondEffective:secondEffective,firstFiber:ff,secondFiber:sf,firstIdentity:fi,secondIdentity:si,
                phaseDomain:phaseDomain,phase:phase,slantDomain:slantDomain,regularSlants:regular,apexFiberDimension:apexDimension,
                storage:pieces,proofDepth:try a.depth)
            try a.checkpoint();return result
        }
    }
    private static func dimension<A:ExactScalarAdmission & ~Copyable>(_ set:ExactParameterSet<Field>,field:Field,using a:inout A) throws -> Int {
        for interval in set.intervals { if try intervalDimension(interval,field:field,using:&a)>0 { return 1 } }
        return 0
    }
    private static func intervalDimension<A:ExactScalarAdmission & ~Copyable>(_ i:ExactParameterInterval<Field.Value>,field:Field,using a:inout A) throws -> Int {
        guard case .finite(let lo)=i.lower,case .finite(let hi)=i.upper else { return 1 }
        return try field.compare(lo,hi,using:&a) == .equal ? 0:1
    }
    private static func joinsSeam<A:ExactScalarAdmission & ~Copyable>(_ intervals:ArraySlice<ExactParameterInterval<Field.Value>>,field:Field,using a:inout A) throws -> Bool {
        guard let first=intervals.first,let last=intervals.last,first.includesLower,
            case .finite(let lower)=first.lower,case .finite(let upper)=last.upper else { return false }
        return try field.sign(of:lower,using:&a) == .zero && field.compare(upper,field.integer(1,using:&a),using:&a) == .equal
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
    public func regular<A:ExactScalarAdmission & ~Copyable>(phase p:Field.Value,slant:Field.Value,
        firstCycle:OriginalParameterCycle,secondCycle:OriginalParameterCycle,
        limits:OriginalDomainIdentityLimits,using a:inout A) throws -> OriginalCoincidentConeMember {
        try a.withProofScope() { a in
            try admitProof(limits:limits,using:&a);let f=source.original.field
            let normalized=try f.compare(p,f.integer(1,using:&a),using:&a) == .equal ? f.integer(0,using:&a):p
            guard hasRegular,try phaseDomain.contains(normalized,in:phase,using:&a),
                try slantDomain.contains(slant,in:regularSlants,using:&a) else { throw OriginalDomainIdentityFailure.outsideSupport }
            let label=try f.multiplying(source.original.labelPeriod,p,using:&a)
            let first=try f.adding(label,f.multiplying(source.original.labelPeriod,firstCycle.scalar(in:f,using:&a),using:&a),using:&a)
            let second=try f.adding(label,f.multiplying(source.original.labelPeriod,secondCycle.scalar(in:f,using:&a),using:&a),using:&a)
            return try member(firstU:first,secondU:second,slant:slant,label:label,isApex:false,limits:limits,using:&a)
        }
    }
    public func apex<A:ExactScalarAdmission & ~Copyable>(firstU:Field.Value,secondU:Field.Value,
        limits:OriginalDomainIdentityLimits,using a:inout A) throws -> OriginalCoincidentConeMember {
        try a.withProofScope() { a in
            try admitProof(limits:limits,using:&a)
            guard hasApex else { throw OriginalDomainIdentityFailure.outsideSupport }
            let zero=try source.original.field.integer(0,using:&a)
            return try member(firstU:firstU,secondU:secondU,slant:zero,label:firstU,isApex:true,limits:limits,using:&a)
        }
    }
    private func member<A:ExactScalarAdmission & ~Copyable>(firstU:Field.Value,secondU:Field.Value,slant:Field.Value,
        label:Field.Value,isApex:Bool,limits:OriginalDomainIdentityLimits,using a:inout A) throws -> OriginalCoincidentConeMember {
        try a.withProofScope() { a in
            try a.retainStorage(bytes:exactScalarPayloadBytes(count:4,of:Field.Value.self))
            guard try firstEffective.contains([firstU,slant],limits:limits,using:&a),
                try secondEffective.contains([secondU,slant],limits:limits,using:&a) else { throw OriginalDomainIdentityFailure.outsideSupport }
            let position=try source.original.position(intrinsicLabel:label,slant:slant,using:&a)
            try a.retainStorage(bytes:exactScalarPayloadBytes(count:1,of:OriginalCoincidentConeMember.self))
            let result=OriginalCoincidentConeMember(relation:self,firstU:firstU,secondU:secondU,slant:slant,
                isApex:isApex,position:position,proofDepth:try a.depth)
            try a.checkpoint();return result
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
