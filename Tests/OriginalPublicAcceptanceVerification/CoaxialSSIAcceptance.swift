import CADCore
import CADGeometry
import Synchronization
#if canImport(Darwin)
import Darwin
#else
import WASILibc
#endif
@main struct CoaxialSSIAcceptance {
    typealias Relation=OriginalCoaxialSurfaceSurfaceRelation
    typealias F=OriginalPhysicalAngleScalarDomain
    typealias V=OriginalPhysicalAngleValue
    struct Failure:Error {let line:Int}
    static func require(_ v:Bool,line:Int = #line) throws {guard v else {throw Failure(line:line)}}
    static func rejects(_ body:() throws -> Void) throws {do{try body()}catch let e as Failure{throw e}catch{return};throw Failure(line:#line)}
    static func ledger(work:Int=8388608,bytes:Int=268435456,coefficient:Int=32) throws -> ExactScalarLedger {
        .init(limits:try .init(work:work,storageBytes:bytes,valueDepth:32,coefficientDepth:coefficient))
    }
    static func limits(source:Int=1,charts:Int=2,families:Int=2,transport:Int=1) throws -> OriginalDomainIdentityLimits {
        try .init(source:.init(remainingSourceDepth:source),maximumTransportDepth:transport,maximumCharts:charts,maximumFamilies:families,maximumIdentityProofs:0)
    }
    static func input(radius:Double=1,angle:Double=Double(bitPattern:0x3fddac670561bb50),shift:Bool=false,reverse:Bool=false) -> (Surface3D,Surface3D) {
        let cone=Surface3D.analytic(.cone(apex:shift ? .init(x:2,y:-3,z:4):.origin,axis:.unitZ,halfAngle:angle))
        let cylinder=Surface3D.analytic(.cylinder(origin:shift ? .init(x:2,y:-3,z:1):.origin,axis:.unitZ,radius:radius))
        return reverse ? (cylinder,cone):(cone,cylinder)
    }
    static func owner(_ r:SurfaceSurfaceIntersectionResult) throws -> Relation {
        guard let r=r.originalCoaxialSurfaceRelation else {throw Failure(line:#line)};return r.original
    }
    static func query(_ x:(Surface3D,Surface3D)) throws -> SurfaceSurfaceIntersectionResult {
        try DefaultSurfaceSurfaceIntersector().intersectionResult(first:x.0,second:x.1,tolerance:.standard)
    }
    static func success() throws -> Relation {
        var retained:Relation?
        for radius in [0.25,1,2] {
            for reverse in [false,true] {
                for shift in [false,true] {
                    let input=input(radius:radius,shift:shift,reverse:reverse);let result=try query(input);let r=try owner(result)
                    try require(result.representation == .exactRelation && result.intersections.isEmpty)
                    try require(r.branches.count == 2 && r.hasPositiveDimensionalSolutions && r.hasPositiveDimensionalImage)
                    try require(r.source.original.coneIsFirst != reverse)
                    var a=try ledger();let f=r.source.original.field,q=ExactRationalScalarDomain()
                    var huge=try q.integer(1,using:&a)
                    for _ in 0..<5 {huge=try q.multiplying(huge,q.integer(UInt64(1)<<32,using:&a),using:&a)}
                    let cp=try OriginalParameterCycle(exact:huge,using:&a),cn=try OriginalParameterCycle(exact:q.negated(huge,using:&a),using:&a)
                    let phase=try f.dividing(f.integer(1,using:&a),f.integer(4,using:&a),using:&a)
                    for i in 0..<2 {
                        try require(r.branches[i].imageDimension == 1 && r.branches[i].fiberDimension == 0)
                        let m=try r.member(branch:i,phase:phase,coneCycle:cp,cylinderCycle:cn,limits:limits(),using:&a)
                        let coneUV=reverse ? m.secondUV:m.firstUV,cylinderUV=reverse ? m.firstUV:m.secondUV
                        let sine=try f.sine(using:&a),cosine=try f.cosine(using:&a)
                        let radial=try f.multiplying(coneUV[1],sine,using:&a)
                        try require(f.compare(f.multiplying(radial,radial,using:&a),f.multiplying(r.source.original.radius,r.source.original.radius,using:&a),using:&a) == .equal)
                        let expected=try f.adding(r.source.original.coneOriginZ,f.multiplying(coneUV[1],cosine,using:&a),using:&a)
                        try require(f.compare(expected,f.adding(r.source.original.cylinderOriginZ,cylinderUV[1],using:&a),using:&a) == .equal)
                        try require(m.position.source.original.original.first == input.0)
                    }
                    try rejects {_ = try DefaultSurfaceSurfaceIntersector().intersections(first:input.0,second:input.1,tolerance:.standard)}
                    retained=r
                }
            }
        }
        for angle in [0.3,0.7] {try require(owner(query(input(angle:angle))).branches.count == 2)}
        guard let retained else {throw Failure(line:#line)};return retained
    }
    static func box(_ u0:Double,_ u1:Double,_ v0:Double,_ v1:Double) throws -> SurfaceParameterBox {
        try .init(u:.init(lower:u0,upper:u1),v:.init(lower:v0,upper:v1))
    }
    static func bounded() throws {
        let x=input();let empty=try box(-1,1,-1,1)
        let c=Counter();let e=try admitted(x,first:empty,second:empty,counter:c);try require(owner(e).isEmpty)
        try require(DefaultSurfaceSurfaceIntersector().intersections(first:x.0,over:empty,second:x.1,over:empty,
            options:.init(),tolerance:.standard,maximumSpanCount:262144,maximumSubdivisionDepth:12,remainingSourceDepth:1,
            consumeWork:{try c.consume(0)},consumeStorage:{try c.retain($0)},maximumAlgebraicDepth:32).isEmpty)
        let full=try box(0,Double.pi*0.5,0,10)
        let r=try owner(admitted(x,first:full,second:full,counter:Counter()))
        try require(r.branches.count == 1 && r.branches[0].positive && r.branches[0].imageDimension == 1)
        var a=try ledger();let f=r.source.original.field,q=ExactRationalScalarDomain()
        let zero=try OriginalParameterCycle(exact:q.integer(0,using:&a),using:&a)
        _ = try r.member(branch:0,phase:f.dividing(f.integer(1,using:&a),f.integer(8,using:&a),using:&a),coneCycle:zero,cylinderCycle:zero,limits:limits(),using:&a)
        let single=try box(0,0,0,10)
        let s=try owner(admitted(x,first:single,second:single,counter:Counter()))
        try require(s.branches.count == 1 && s.branches[0].imageDimension == 0 && !s.hasPositiveDimensionalSolutions)
        let near=Surface3D.analytic(.cylinder(origin:.init(x:1e-12,y:0,z:0),axis:.unitZ,radius:1))
        try rejects {_ = try query((x.0,near))}
    }
    static func prepared(_ r:Relation) throws {
        var a=try ledger();let f=r.source.original.field
        let all=try ExactParameterInterval<V>.checked(field:f,lower:.negativeInfinity,upper:.positiveInfinity,depth:.init(value:0,coefficient:0),using:&a)
        let b=r.source.original.labelPeriod,z=try f.integer(0,using:&a)
        let open=try ExactParameterInterval.checked(field:f,lower:.finite(z),upper:.finite(b),includesLower:false,includesUpper:false,depth:r.proofDepth,using:&a)
        let q=ExactRationalScalarDomain(),zero=try OriginalParameterCycle(exact:q.integer(0,using:&a),using:&a)
        let p=try Relation.resolve(source:r.source,firstIntervals:[[open],[all]],secondIntervals:[[open],[all]],maximumComponents:2,limits:limits(),using:&a)
        // Open one-period windows exclude their seam phase for the zero index.
        let positive=p.branches.firstIndex {$0.positive}!
        try rejects {_ = try p.member(branch:positive,phase:z,coneCycle:zero,cylinderCycle:zero,limits:limits(),using:&a)}
        let half=try f.dividing(b,f.integer(2,using:&a),using:&a)
        let phaseHalf=try f.dividing(f.integer(1,using:&a),f.integer(2,using:&a),using:&a)
        _ = half
        _ = try p.member(branch:positive,phase:phaseHalf,coneCycle:zero,cylinderCycle:zero,limits:limits(),using:&a)
        for control in 0..<4 {
            let l=try limits(source:control == 0 ? 0:1,charts:control == 1 ? 1:2,families:control == 2 ? 1:2,transport:control == 3 ? 0:1)
            try rejects {try r.admitProof(limits:l,using:&a)}
        }
        if r.proofDepth.coefficient > 0 {var shallow=try ledger(coefficient:r.proofDepth.coefficient-1);try rejects {try r.admitProof(limits:limits(),using:&shallow)}}
        a.cancel();try rejects {try r.admitProof(limits:limits(),using:&a)}
    }
    final class Counter: Sendable {
        struct State: Sendable { var work = 0; var bytes = 0 }
        private let state = Mutex(State())
        let workLimit: Int; let byteLimit: Int; let cancelAt: Int?; let cancelStorageAt: Int?
        init(work: Int = 8_388_608, bytes: Int = 268_435_456, cancelAt: Int? = nil, cancelStorageAt: Int? = nil) {
            workLimit = work; byteLimit = bytes; self.cancelAt = cancelAt; self.cancelStorageAt = cancelStorageAt
        }
        func consume(_ depth: Int) throws {
            let count = try state.withLock { s in
                guard s.work < workLimit else { throw ExactScalarFailure.resourceLimit(.work) }
                s.work += 1; return s.work
            }
            if count == cancelAt { throw CancellationError() }
        }
        func retain(_ bytes: Int) throws {
            let count = try state.withLock { s in
                let next = s.bytes.addingReportingOverflow(bytes)
                guard bytes >= 0, !next.overflow, next.partialValue <= byteLimit else { throw ExactScalarFailure.resourceLimit(.storage) }
                s.bytes = next.partialValue; return s.bytes
            }
            if count == cancelStorageAt { withUnsafeCurrentTask { $0?.cancel() } }
        }
        var totals: State { state.withLock { $0 } }
    }
    static func admitted(_ x:(Surface3D,Surface3D),first:SurfaceParameterBox?=nil,second:SurfaceParameterBox?=nil,
        counter:Counter,sourceDepth:Int=1,scalarDepth:Int=32) throws -> SurfaceSurfaceIntersectionResult {
        let engine=DefaultSurfaceSurfaceIntersector()
        if let first,let second {return try engine.intersectionResult(first:x.0,over:first,second:x.1,over:second,
            options:.init(),tolerance:.standard,maximumSpanCount:262144,maximumSubdivisionDepth:12,remainingSourceDepth:sourceDepth,
            consumeWork:{try counter.consume(0)},consumeStorage:{try counter.retain($0)},maximumAlgebraicDepth:scalarDepth)}
        return try engine.intersectionResult(first:x.0,second:x.1,options:.init(),tolerance:.standard,
            maximumSpanCount:262144,maximumSubdivisionDepth:12,remainingSourceDepth:sourceDepth,
            consumeWork:{try counter.consume(0)},consumeStorage:{try counter.retain($0)},maximumAlgebraicDepth:scalarDepth)
    }
    static func resources() throws {
        let x=input()
        for empty in [false,true] {
            let b=empty ? try box(-1,1,-1,1):nil
            let measured=Counter();_ = try admitted(x,first:b,second:b,counter:measured)
            let n=measured.totals
            _ = try admitted(x,first:b,second:b,counter:Counter(work:n.work,bytes:n.bytes))
            try rejects {_ = try admitted(x,first:b,second:b,counter:Counter(work:n.work-1,bytes:n.bytes))}
            try rejects {_ = try admitted(x,first:b,second:b,counter:Counter(work:n.work,bytes:n.bytes-1))}
            for at in [1,n.work/2,n.work] {try rejects {_ = try admitted(x,first:b,second:b,counter:Counter(cancelAt:at))}}
        }
        try rejects {_ = try admitted(x,counter:Counter(),sourceDepth:0)}
        try rejects {_ = try admitted(x,counter:Counter(),scalarDepth:0)}
        print("PASS coaxial SSI full/empty N/N-1 work/storage, source/scalar and cancellation")
    }
    static func publicationCancellation() async throws {
        for empty in [false,true] {
            let task=Task {
                let x=input();let b=empty ? try box(-1,1,-1,1):nil
                let measured=Counter();_ = try admitted(x,first:b,second:b,counter:measured)
                try rejects {_ = try admitted(x,first:b,second:b,counter:Counter(cancelStorageAt:measured.totals.bytes))}
                try require(Task<Never,Never>.isCancelled)
            }
            try await task.value
        }
        print("PASS terminal complete SSI family/empty cancellation")
    }
    static func session() throws {
        let x=input(),c=Counter()
        let p=try DefaultSurfaceSurfaceIntersector().prepareOriginalPair(first:x.0,second:x.1,tolerance:.standard,
            maximumSpanCount:262144,maximumSubdivisionDepth:12,remainingSourceDepth:1,
            consumeWork:{try c.consume(0)},consumeStorage:{try c.retain($0)},maximumAlgebraicDepth:32)
        let b=try box(0,Double.pi*0.5,0,10)
        let a=try owner(p.intersectionResult(firstBox:b,secondBox:b,options:.init()))
        let d=try owner(p.intersectionResult(firstBox:b,secondBox:b,options:.init()))
        var usage=try ledger()
        let chart=try d.source.chart(0,limits:limits().source,using:&usage)
        try require(a.source.owns(chart))
        try require(a.branches.count == 1 && d.branches.count == 1)
    }
    static func main() async throws {
        let r=try success();try bounded();try prepared(r);try session();try resources();try await publicationCancellation()
        var a=try ledger();try r.admitProof(limits:limits(),using:&a)
        print("PASS complete coaxial primitive SSI, both UV/integer families, symbolic XYZ, selections and lifetime")
    }
}
