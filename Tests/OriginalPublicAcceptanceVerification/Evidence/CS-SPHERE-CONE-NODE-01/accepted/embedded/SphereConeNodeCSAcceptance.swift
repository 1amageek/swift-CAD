import CADCore
import Synchronization
#if canImport(Darwin)
import Darwin
#else
import WASILibc
#endif

@main struct SphereConeNodeCSAcceptance {
    typealias Relation=OriginalSphereConeNodePlaneRelation
    struct Failure:Error { let line:Int }
    static func require(_ b:Bool,line:Int = #line) throws { guard b else { throw Failure(line:line) } }
    static func rejects(line:Int = #line,_ body:() throws -> Void) throws { do { try body() } catch let f as Failure { throw f } catch { return };throw Failure(line:line) }
    static func resource(_ body:() throws -> Void) throws {
        do { try body();throw Failure(line:#line) }
        catch let error as KernelError { try require(error.code == .resourceLimitExceeded) }
    }
    static func cancelled(_ body:() throws -> Void) throws {
        do { try body();throw Failure(line:#line) }
        catch is CancellationError {}
    }
    static func ledger(work:Int=8_388_608,bytes:Int=268_435_456,value:Int=32,coefficient:Int=32) throws -> ExactScalarLedger {
        .init(limits:try .init(work:work,storageBytes:bytes,valueDepth:value,coefficientDepth:coefficient))
    }
    static func limits(source:Int=2,transport:Int=1,charts:Int=2,families:Int=3) throws -> OriginalDomainIdentityLimits {
        try .init(source:.init(remainingSourceDepth:source),maximumTransportDepth:transport,maximumCharts:charts,maximumFamilies:families,maximumIdentityProofs:0)
    }
    static func plane() throws -> Surface3D { .plane(try .init(origin:.origin,normal:.unitY,uDirection:.unitX)) }
    static func curve(_ branch:Int) throws -> Curve3D {
        let sphere=Surface3D.analytic(.sphere(center:.origin,radius:1))
        let cone=Surface3D.analytic(.cone(apex:.init(x:1,y:0,z:0),axis:.unitZ,halfAngle:0.5))
        let result=try DefaultSurfaceSurfaceIntersector().intersectionResult(first:sphere,second:cone,tolerance:.standard)
        guard case .originalApexSphereCone(let component)=result.intersections[0] else { throw Failure(line:#line) }
        var a=try ledger()
        return try component.nodeCurve(branch:branch,tolerance:.standard,limits:limits(source:1),using:&a)
    }
    static func owner(_ result:CurveSurfaceIntersectionResult) throws -> Relation {
        guard let r=result.originalSphereConeNodeRelation else { throw Failure(line:#line) }
        try require(result.representation == .exactRelation)
        return r.original
    }
    static func options(empty:Bool=false) throws -> CurveSurfaceIntersectionOptions {
        var o=CurveSurfaceIntersectionOptions();o.curveRange=try .init(lower:empty ? 0.125:0,upper:empty ? 0.375:1)
        o.surfaceURange=try .init(lower:-2,upper:2);o.surfaceVRange=try .init(lower:-2,upper:2);return o
    }
    static func success(selected:Int?=nil) throws {
        for branch in 0..<2 where selected==nil || selected==branch {
            let c=try curve(branch),result=try DefaultCurveSurfaceIntersector().intersectionResult(curve:c,surface:plane(),options:options(),tolerance:.standard)
            let r=try owner(result)
            try require(r.ordinals.count==3 && result.points.count==3 && !r.hasPositiveDimensionalSolutions && !result.hasPositiveDimensionalSolutions && r.hasPositiveDimensionalParentCorrespondence && r.originalParameterDimension==3 && !r.hasPositiveDimensionalImage)
            try require(result.points[0].curveParameter==0 && result.points[1].curveParameter==0.5 && result.points[2].curveParameter==1)
            try require(result.points[0].point==result.points[2].point)
            var a=try ledger();let f=r.source.original.field,q=ExactRationalScalarDomain()
            let zero=try OriginalParameterCycle(exact:q.integer(0,using:&a),using:&a)
            var huge=try q.integer(1,using:&a)
            for _ in 0..<5 { huge=try q.multiplying(huge,q.integer(UInt64(1)<<32,using:&a),using:&a) }
            let big=try OriginalParameterCycle(exact:huge,using:&a)
            for ordinal in r.ordinals {
                let u=try f.dividing(f.integer(-7,using:&a),f.integer(3,using:&a),using:&a)
                let m=try r.member(ordinal:ordinal,coneU:ordinal==1 ? nil:u,coneCycle:big,sphereCycle:big,limits:limits(),using:&a)
                try require(m.parameter.depth.value<=32 && m.imageDimension==0 && m.fiberDimension==0 && m.parameterDimension==0 && m.parentFiberDimension==(ordinal==1 ? 0:1))
                if ordinal==1 {
                    let parent=r.source.original.traversal.source
                    let expectedX=try f.subtracting(f.integer(1,using:&a),f.multiplying(f.integer(2,using:&a),f.multiplying(parent.sine,parent.sine,using:&a),using:&a),using:&a)
                    let expectedZ=try f.multiplying(f.integer(branch==0 ? 2:-2,using:&a),f.multiplying(parent.sine,parent.cosine,using:&a),using:&a)
                    try require(f.compare(m.x,expectedX,using:&a) == .equal && f.compare(m.z,expectedZ,using:&a) == .equal)
                    try require(f.sign(of:m.coneV,using:&a) == (branch==0 ? .positive:.negative))
                } else {
                    try require(f.compare(m.x,f.integer(1,using:&a),using:&a) == .equal && f.sign(of:m.z,using:&a) == .zero)
                    try require(f.compare(m.coneU,u,using:&a) == .equal && m.incidentSide==(ordinal==0 ? 1:-1))
                }
                let published=result.points[ordinal].point,tol=ModelingTolerance.standard.distance
                try require(f.compare(m.x,f.binary64(exactly:published.x-tol,using:&a),using:&a) != .less &&
                    f.compare(m.x,f.binary64(exactly:published.x+tol,using:&a),using:&a) != .greater)
                try require(f.compare(m.z,f.binary64(exactly:published.z-tol,using:&a),using:&a) != .less &&
                    f.compare(m.z,f.binary64(exactly:published.z+tol,using:&a),using:&a) != .greater)
                try require(f.compare(m.planeV(using:&a),f.negated(m.z,using:&a),using:&a) == .equal)
                let period=r.source.original.traversal.source.labelPeriod
                var exactCycle=try f.integer(1,using:&a)
                for _ in 0..<5 { exactCycle=try f.multiplying(exactCycle,f.integer(UInt64(1)<<32,using:&a),using:&a) }
                let lifted=try f.multiplying(period,exactCycle,using:&a)
                let expectedSphereU=try f.adding(lifted,f.dividing(f.multiplying(period,f.integer(3,using:&a),using:&a),f.integer(4,using:&a),using:&a),using:&a)
                try require(f.compare(m.sphereU,expectedSphereU,using:&a) == .equal && f.compare(m.sphereLatitudeSine,m.z,using:&a) == .equal)
                if ordinal==1 {
                    let expectedConeU=try f.adding(lifted,f.dividing(f.multiplying(period,f.integer(branch==0 ? 1:3,using:&a),using:&a),f.integer(4,using:&a),using:&a),using:&a)
                    let expectedConeV=try f.multiplying(f.integer(branch==0 ? 2:-2,using:&a),r.source.original.traversal.source.sine,using:&a)
                    try require(f.compare(m.coneU,expectedConeU,using:&a) == .equal && f.compare(m.coneV,expectedConeV,using:&a) == .equal)
                }
            }
            try rejects { _=try r.member(ordinal:3,coneU:nil,coneCycle:zero,sphereCycle:zero,limits:limits(),using:&a) }
            let empty=try DefaultCurveSurfaceIntersector().intersectionResult(curve:c,surface:plane(),options:options(empty:true),tolerance:.standard)
            try require(owner(empty).isEmpty && empty.points.isEmpty)
            guard case .certifiedIntersection(.sphereCone(let rendered))=c else { throw Failure(line:#line) }
            try require(rendered.originalNodeTraversal != nil)
            try require(rendered.point(atNormalizedFraction:0,tolerance:.standard)==Point3D(x:1,y:0,z:0))
            try require(rendered.point(atNormalizedFraction:1,tolerance:.standard)==Point3D(x:1,y:0,z:0))
        }
        print("PASS public SSI-issued node curves, all3 distinct T/parentUV/germs, original positions and complete empty")
    }
    static func controls() throws {
        for branch in 0..<2 {
            var c=try curve(branch)
            let solver=DefaultCurveSurfaceIntersector()
            for (lo,hi,expected) in [(0.0,0.0,[0]),(0.5,0.5,[1]),(1.0,1.0,[2]),(0.125,0.75,[1]),(-2.0,-1.0,[])] {
                var o=try options();o.curveRange=try .init(lower:lo,upper:hi)
                let r=try owner(solver.intersectionResult(curve:c,surface:plane(),options:o,tolerance:.standard))
                try require(Array(r.ordinals)==expected && r.imageDimension==(expected.isEmpty ? nil:0))
            }
            var o=try options();o.surfaceURange=try .init(lower:1,upper:1);o.surfaceVRange=try .init(lower:0,upper:0)
            let endpoints=try owner(solver.intersectionResult(curve:c,surface:plane(),options:o,tolerance:.standard))
            try require(Array(endpoints.ordinals)==[0,2])
            o.surfaceURange=try .init(lower:2,upper:3)
            try require(owner(solver.intersectionResult(curve:c,surface:plane(),options:o,tolerance:.standard)).isEmpty)
            let r=try owner(solver.intersectionResult(curve:c,surface:plane(),options:options(),tolerance:.standard))
            var a=try ledger();let f=r.source.original.field,q=ExactRationalScalarDomain()
            let zero=try OriginalParameterCycle(exact:q.integer(0,using:&a),using:&a)
            try rejects { try r.admitProof(limits:limits(source:1),using:&a) }
            try rejects { try r.admitProof(limits:limits(transport:0),using:&a) }
            try rejects { try r.admitProof(limits:limits(charts:1),using:&a) }
            try rejects { try r.admitProof(limits:limits(families:2),using:&a) }
            try rejects { _=try r.member(ordinal:0,coneU:nil,coneCycle:zero,sphereCycle:zero,limits:limits(),using:&a) }
            var shallow=try ledger(value:0,coefficient:0)
            try rejects { try r.admitProof(limits:limits(),using:&shallow) }
            try rejects { _=try solver.intersectionResult(curve:c,surface:.plane(.init(origin:.origin,normal:.unitZ,uDirection:.unitX)),options:options(),tolerance:.standard) }
            guard case .certifiedIntersection(.sphereCone(let original))=c else { throw Failure(line:#line) }
            let copy=c;c = .line(try .init(origin:.origin,direction:.unitX))
            try require(r.source.original.original==copy && r.source.original.original != c && original.originalNodeTraversal != nil)
            let root=try r.member(ordinal:0,coneU:f.integer(4,using:&a),coneCycle:zero,sphereCycle:zero,limits:limits(),using:&a)
            try require(root.fiberDimension==0 && root.parentFiberDimension==1)
            let other=try solver.intersectionResult(curve:copy,surface:plane(),options:options(),tolerance:.standard)
            try require(other.originalSphereConeNodeRelation?.original !== r)
        }
        print("PASS finite/singleton/target clipping, retained/COW ownership, limits and explicit unsupported target")
    }
    final class Counter: Sendable {
        struct State: Sendable { var work = 0; var bytes = 0 }
        private let state = Mutex(State())
        let workLimit: Int; let byteLimit: Int; let cancelAt: Int?; let cancelStorageAt: Int?
        init(work: Int = 8_388_608, bytes: Int = 268_435_456, cancelAt: Int? = nil, cancelStorageAt: Int? = nil) {
            workLimit = work; byteLimit = bytes; self.cancelAt = cancelAt; self.cancelStorageAt = cancelStorageAt
        }
        func consume(_ depth:Int=0) throws {
            let count = try state.withLock { s in
                let next=s.work.addingReportingOverflow(1)
                guard depth>=0,!next.overflow,next.partialValue <= workLimit else { throw ExactScalarFailure.resourceLimit(.work) }
                s.work=next.partialValue;return s.work
            }
            if let cancelAt, count >= cancelAt { throw CancellationError() }
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
    static func admitted(_ c:Curve3D,counter:Counter,empty:Bool=false,bare:Bool=false,depth:Int=2,scalar:Int=32) throws -> CurveSurfaceIntersectionResult? {
        let solver=DefaultCurveSurfaceIntersector()
        if bare {
            let values=try solver.intersections(curve:c,surface:plane(),options:options(empty:empty),tolerance:.standard,
                maximumSpanCount:32,maximumSubdivisionDepth:8,remainingSourceDepth:depth,consumeWork:{try counter.consume($0)},
                consumeStorage:{try counter.retain($0)},maximumAlgebraicDepth:scalar)
            try require(values.count==(empty ? 0:3));return nil
        }
        return try solver.intersectionResult(curve:c,surface:plane(),options:options(empty:empty),tolerance:.standard,
            maximumSpanCount:32,maximumSubdivisionDepth:8,remainingSourceDepth:depth,consumeWork:{try counter.consume($0)},
            consumeStorage:{try counter.retain($0)},maximumAlgebraicDepth:scalar)
    }
    static func publication() throws {
        for branch in 0..<2 {
            let c=try curve(branch)
            try require(DefaultCurveSurfaceIntersector().intersections(curve:c,surface:plane(),options:options(),tolerance:.standard).count==3)
            for empty in [false,true] {
                let counter=Counter(),r=try admitted(c,counter:counter,empty:empty)
                try require(owner(r!).isEmpty==empty);let n=counter.totals
                _=try admitted(c,counter:Counter(work:n.work,bytes:n.bytes),empty:empty)
                _=try admitted(c,counter:Counter(work:n.work,bytes:n.bytes),empty:empty,bare:true)
                try resource { _=try admitted(c,counter:Counter(work:n.work-1,bytes:n.bytes),empty:empty) }
                try resource { _=try admitted(c,counter:Counter(work:n.work,bytes:n.bytes-1),empty:empty) }
                try cancelled { _=try admitted(c,counter:Counter(cancelAt:1),empty:empty) }
                try cancelled { _=try admitted(c,counter:Counter(cancelAt:n.work),empty:empty) }
            }
            try resource { _=try admitted(c,counter:Counter(),depth:1) }
            try resource { _=try admitted(c,counter:Counter(),scalar:0) }
        }
        print("PASS all4 public CS entries, exact N-N1 work/storage/source/depth and cancellation")
    }
    static func terminal() async throws {
        for branch in 0..<2 {
            let c=try curve(branch)
            for empty in [false,true] {
                let task=Task {
                    let n=Counter();_=try admitted(c,counter:n,empty:empty)
                    try cancelled { _=try admitted(c,counter:Counter(cancelStorageAt:n.totals.bytes),empty:empty) }
                    try require(Task<Never,Never>.isCancelled)
                }
                try await task.value
            }
        }
        print("PASS final nonempty/empty publication cancellation")
    }
    static func main() async throws {
#if hasFeature(Embedded)
        let group=getenv("CAD_PROOF_GROUP").map {String(cString:$0)} ?? "all"
#else
        let group=CommandLine.arguments.count>1 ? CommandLine.arguments[1]:"all"
#endif
        try require(["all","success","success-0","success-1","publication","terminal","controls"].contains(group))
        if group=="all" || group=="success" { try success() }
        if group=="success-0" { try success(selected:0) }
        if group=="success-1" { try success(selected:1) }
        if group=="all" || group=="controls" { try controls() }
        if group=="all" || group=="publication" { try publication() }
        if group=="all" || group=="terminal" { try await terminal() }
        print("PASS source-issued sphere-cone node CS group")
    }
}
