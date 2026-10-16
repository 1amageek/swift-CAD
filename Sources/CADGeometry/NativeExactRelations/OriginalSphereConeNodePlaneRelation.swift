import CADCore

/// All T contacts and the entire complement exclusion in original requested domains.
public final class OriginalSphereConeNodePlaneRelation: Sendable {
    public typealias Source=OriginalSphereConeNodeCurveSnapshot
    public typealias Field=Source.Field
    public typealias CurveSelection=OriginalParameterSelection<Source,Field>
    public typealias PlaneSelection=OriginalParameterSelection<Surface3D,Field>
    public let source:OriginalSourceBinding<Source>
    public let target:OriginalSourceBinding<Surface3D>
    public let support:CurveSelection
    public let request:CurveSelection
    public let effective:CurveSelection
    public let planeRequest:PlaneSelection
    private let storage:[Int]
    public var ordinals:ArraySlice<Int> { storage[...] }
    public var isEmpty:Bool { storage.isEmpty }
    public var hasPositiveDimensionalSolutions:Bool { false }
    public var hasPositiveDimensionalParentCorrespondence:Bool { storage.contains { $0 != 1 } }
    public var originalParameterDimension:Int { 3 }
    public var hasPositiveDimensionalImage:Bool { false }
    public var imageDimension:Int? { isEmpty ? nil:0 }
    public let proofDepth:ExactScalarDepth
    private init(source:OriginalSourceBinding<Source>,target:OriginalSourceBinding<Surface3D>,support:CurveSelection,
        request:CurveSelection,effective:CurveSelection,planeRequest:PlaneSelection,storage:[Int],proofDepth:ExactScalarDepth) {
        self.source=source;self.target=target;self.support=support;self.request=request;self.effective=effective
        self.planeRequest=planeRequest;self.storage=storage;self.proofDepth=proofDepth
    }
    public static func resolve<A:ExactScalarAdmission & ~Copyable>(source:OriginalSourceBinding<Source>,target:OriginalSourceBinding<Surface3D>,
        options:CurveSurfaceIntersectionOptions,limits:OriginalDomainIdentityLimits,using a:inout A) throws -> OriginalSphereConeNodePlaneRelation {
        try a.withProofScope() { a in
            try source.require(limits.source);try target.require(limits.source);try requireLimits(limits)
            guard OriginalCertifiedCoaxialTargetSnapshotProvider.isPlane(target.original) else { throw OriginalDomainIdentityFailure.foreignOwner }
            let s=source.original,f=s.field,zero=try f.integer(0,using:&a),one=try f.integer(1,using:&a)
            let interval=try ExactParameterInterval.checked(field:f,lower:.finite(zero),upper:.finite(one),depth:s.proofDepth,using:&a)
            try a.retainStorage(bytes:exactScalarPayloadBytes(count:2,of:[ExactParameterInterval<Field.Value>].self))
            try a.retainStorage(bytes:exactScalarPayloadBytes(count:2,of:ExactParameterInterval<Field.Value>.self))
            try a.retainStorage(bytes:exactScalarPayloadBytes(count:1,of:OriginalCoordinateSemantics.self))
            let frame=try DefaultOriginalParameterTransporter<Source,Field>().frame(source:source,field:f,support:[[interval]],
                semantics:[.authoredScalar],limits:limits,using:&a)
            let support=try frame.fullSelection(limits:limits,using:&a)
            let requested=try Self.interval(options.curveRange,field:f,using:&a)
            let request=try frame.selection(intervals:[[requested]],limits:limits,using:&a)
            let effective=try request.intersection(support,limits:limits,using:&a)
            let whole=try Self.interval(nil,field:f,using:&a)
            try a.retainStorage(bytes:exactScalarPayloadBytes(count:4,of:[ExactParameterInterval<Field.Value>].self))
            try a.retainStorage(bytes:exactScalarPayloadBytes(count:4,of:ExactParameterInterval<Field.Value>.self))
            try a.retainStorage(bytes:exactScalarPayloadBytes(count:2,of:OriginalCoordinateSemantics.self))
            let planeFrame=try DefaultOriginalParameterTransporter<Surface3D,Field>().frame(source:target,field:f,
                support:[[whole],[whole]],semantics:[.authoredScalar,.authoredScalar],limits:limits,using:&a)
            let u=try Self.interval(options.surfaceURange,field:f,using:&a),v=try Self.interval(options.surfaceVRange,field:f,using:&a)
            let plane=try planeFrame.selection(intervals:[[u],[v]],limits:limits,using:&a)
            var ordinals:[Int]=[]
            // A bounded scratch for the three authored T tuples is admitted before allocation.
            try a.retainStorage(bytes:exactScalarPayloadBytes(count:3,of:Int.self));ordinals.reserveCapacity(3)
            for i in 0..<3 {
                try a.consumeWork(1);let root=try s.critical(ordinal:i,using:&a)
                try a.retainStorage(bytes:exactScalarPayloadBytes(count:3,of:Field.Value.self))
                if try effective.contains([root.parameter],limits:limits,using:&a),
                    try plane.contains([root.x,f.negated(root.z,using:&a)],limits:limits,using:&a) {
                    guard ordinals.count<options.maximumCandidateCount else { throw NativeExactRelationFailure.resultLimit }
                    ordinals.append(i)
                }
            }
            try a.retainStorage(bytes:MemoryLayout<(OriginalSourceBinding<Source>,OriginalSourceBinding<Surface3D>,CurveSelection,CurveSelection,
                CurveSelection,PlaneSelection,[Int],ExactScalarDepth)>.stride+2*MemoryLayout<UnsafeRawPointer>.stride)
            let result=OriginalSphereConeNodePlaneRelation(source:source,target:target,support:support,request:request,effective:effective,
                planeRequest:plane,storage:ordinals,proofDepth:try a.depth)
            try a.checkpoint();return result
        }
    }
    public func admitProof<A:ExactScalarAdmission & ~Copyable>(limits:OriginalDomainIdentityLimits,using a:inout A) throws {
        try a.checkpoint();try source.require(limits.source);try target.require(limits.source);try Self.requireLimits(limits)
        try a.admitDepth(value:proofDepth.value,coefficient:proofDepth.coefficient)
        try request.frame.require(limits,&a);try planeRequest.frame.require(limits,&a);try a.checkpoint()
    }
    public func member<A:ExactScalarAdmission & ~Copyable>(ordinal:Int,coneU:Field.Value?,coneCycle:OriginalParameterCycle,
        sphereCycle:OriginalParameterCycle,limits:OriginalDomainIdentityLimits,using a:inout A) throws -> OriginalSphereConeNodeContact {
        try a.withProofScope() { a in
            try admitProof(limits:limits,using:&a)
            guard storage.contains(ordinal) else { throw OriginalDomainIdentityFailure.outsideSupport }
            let s=source.original,f=s.field,root=try s.critical(ordinal:ordinal,using:&a),period=s.traversal.source.labelPeriod
            let cu:Field.Value
            if root.isApex {
                guard let coneU else { throw OriginalDomainIdentityFailure.invalidDomain };cu=try f.importing(coneU,using:&a)
            } else { cu=try f.adding(root.coneLabel,f.multiplying(period,coneCycle.scalar(in:f,using:&a),using:&a),using:&a) }
            let su=try f.adding(f.multiplying(period,sphereCycle.scalar(in:f,using:&a),using:&a),f.multiplying(period,
                f.dividing(f.integer(3,using:&a),f.integer(4,using:&a),using:&a),using:&a),using:&a)
            try a.retainStorage(bytes:exactScalarPayloadBytes(count:1,of:OriginalSphereConeNodeContact.self))
            let result=OriginalSphereConeNodeContact(relation:self,ordinal:ordinal,parameter:root.parameter,x:root.x,z:root.z,
                coneU:cu,coneV:root.slant,sphereU:su,sphereLatitudeSine:root.z,isApex:root.isApex,proofDepth:try a.depth)
            try a.checkpoint();return result
        }
    }
    private static func interval<A:ExactScalarAdmission & ~Copyable>(_ range:ScalarInterval?,field:Field,using a:inout A) throws -> ExactParameterInterval<Field.Value> {
        let depth=try ExactScalarDepth(value:0,coefficient:0)
        if let r=range { return try .checked(field:field,lower:.finite(field.binary64(exactly:r.lower,using:&a)),
            upper:.finite(field.binary64(exactly:r.upper,using:&a)),depth:depth,using:&a) }
        return try .checked(field:field,lower:.negativeInfinity,upper:.positiveInfinity,depth:depth,using:&a)
    }
    private static func requireLimits(_ limits:OriginalDomainIdentityLimits) throws {
        guard limits.maximumCharts>=2 else { throw OriginalDomainIdentityFailure.chartLimit }
        guard limits.maximumFamilies>=3 else { throw OriginalDomainIdentityFailure.familyLimit }
        guard limits.maximumTransportDepth>=1 else { throw OriginalDomainIdentityFailure.transportDepthLimit }
    }
}
