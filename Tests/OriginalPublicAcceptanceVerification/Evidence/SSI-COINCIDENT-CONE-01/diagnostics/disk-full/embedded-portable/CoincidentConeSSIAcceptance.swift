import CADCore
import Synchronization
#if canImport(Darwin)
import Darwin
#else
import WASILibc
#endif

@main struct CoincidentConeSSIAcceptance {
    typealias Relation=OriginalCoincidentConeRelation
    struct Failure:Error { let line:Int }
    static func require(_ value:Bool,line:Int = #line) throws { guard value else { throw Failure(line:line) } }
    static func rejects(_ body:() throws -> Void) throws { do { try body() } catch let f as Failure { throw f } catch { return };throw Failure(line:#line) }
    static func input(_ moved:Bool=false) -> Surface3D {
        .analytic(.cone(apex:moved ? .init(x:2,y:4,z:-7):.origin,axis:moved ? .init(x:0,y:0,z:-1):.unitZ,halfAngle:0.5))
    }
    static func ledger(work:Int=8_388_608,bytes:Int=268_435_456,value:Int=32,coefficient:Int=32) throws -> ExactScalarLedger {
        .init(limits:try .init(work:work,storageBytes:bytes,valueDepth:value,coefficientDepth:coefficient))
    }
    static func limits(source:Int=1,transport:Int=1,charts:Int=2,families:Int=2) throws -> OriginalDomainIdentityLimits {
        try .init(source:.init(remainingSourceDepth:source),maximumTransportDepth:transport,maximumCharts:charts,maximumFamilies:families,maximumIdentityProofs:2)
    }
    static func owner(_ result:SurfaceSurfaceIntersectionResult) throws -> Relation {
        guard let r=result.originalCoincidentConeRelation else { throw Failure(line:#line) }
        try require(result.representation == .exactRelation && r.isEmpty==r.original.isEmpty)
        return r.original
    }
    static func whole(_ moved:Bool=false) throws -> Relation {
        let s=input(moved),result=try DefaultSurfaceSurfaceIntersector().intersectionResult(first:s,second:s,tolerance:.standard)
        let r=try owner(result)
        try require(result.intersections.count==1 && r.hasApex && r.hasRegular && r.apexFiberDimension==2)
        guard case .originalCoincidentCone(let c)=result.intersections[0] else { throw Failure(line:#line) }
        try require(c.includesApex && c.imageDimension==2 && c.fiberDimension==nil && c.relation === r)
        return r
    }
    static func success(selected:Int?=nil) throws {
        for index in 0..<2 where selected==nil || selected==index {
            let r=try whole(index==1),f=r.source.original.field
            var a=try ledger();let q=ExactRationalScalarDomain()
            var huge=try q.integer(1,using:&a)
            for _ in 0..<5 { huge=try q.multiplying(huge,q.integer(UInt64(1)<<32,using:&a),using:&a) }
            let positive=try OriginalParameterCycle(exact:huge,using:&a),negative=try OriginalParameterCycle(exact:q.negated(huge,using:&a),using:&a)
            for n in [0,1,2,4] {
                let p=try f.dividing(f.integer(n,using:&a),f.integer(4,using:&a),using:&a)
                for v in [-2,2] {
                    let m=try r.regular(phase:p,slant:f.integer(v,using:&a),firstCycle:positive,secondCycle:negative,limits:limits(),using:&a)
                    try require(!m.isApex && m.fiberDimension==0 && m.position.source.original.first==input(index==1))
                    try require(f.compare(m.firstUV.v,m.secondUV.v,using:&a) == .equal)
                    try require(f.sign(of:m.firstU,using:&a) == .positive && f.sign(of:m.secondU,using:&a) == .negative)
                    let s=r.source.original.sine,c=r.source.original.cosine
                    try require(f.compare(f.adding(f.multiplying(s,s,using:&a),f.multiplying(c,c,using:&a),using:&a),f.integer(1,using:&a),using:&a) == .equal)
                    let x=try m.position.coordinate(row:0,using:&a),y=try m.position.coordinate(row:1,using:&a),z=try m.position.coordinate(row:2,using:&a)
                    let sign=try f.integer(index==1 ? -1:1,using:&a),origin=try f.integer(index==1 ? -7:0,using:&a)
                    try require(f.compare(z.offset,f.adding(origin,f.multiplying(sign,m.position.axial,using:&a),using:&a),using:&a) == .equal)
                    try require(f.sign(of:z.cosineCoefficient,using:&a) == .zero && f.sign(of:z.sineCoefficient,using:&a) == .zero)
                    // The actual source row coefficients satisfy the complete unit-circle radial law.
                    let radialSquare=try f.multiplying(m.position.radial,m.position.radial,using:&a)
                    let cc=try f.adding(f.multiplying(x.cosineCoefficient,x.cosineCoefficient,using:&a),f.multiplying(y.cosineCoefficient,y.cosineCoefficient,using:&a),using:&a)
                    let ss=try f.adding(f.multiplying(x.sineCoefficient,x.sineCoefficient,using:&a),f.multiplying(y.sineCoefficient,y.sineCoefficient,using:&a),using:&a)
                    let cs=try f.adding(f.multiplying(x.cosineCoefficient,x.sineCoefficient,using:&a),f.multiplying(y.cosineCoefficient,y.sineCoefficient,using:&a),using:&a)
                    try require(f.compare(cc,radialSquare,using:&a) == .equal && f.compare(ss,radialSquare,using:&a) == .equal && f.sign(of:cs,using:&a) == .zero)
                }
            }
            let u=try f.dividing(f.integer(-7,using:&a),f.integer(3,using:&a),using:&a)
            let apex=try r.apex(firstU:u,secondU:f.integer(11,using:&a),limits:limits(),using:&a)
            try require(apex.isApex && apex.fiberDimension==2 && f.compare(apex.firstU,u,using:&a) == .equal)
            try require(f.sign(of:apex.position.radial,using:&a) == .zero && f.sign(of:apex.position.axial,using:&a) == .zero)
            try require(r.firstIdentity?.kind == .collapsedSubset && r.secondIdentity?.kind == .collapsedSubset)
        }
        print("PASS complete cone surface/UV families, source coefficients, independent huge lifts and apex fibers")
    }
    static func box(_ ul:Double,_ uh:Double,_ vl:Double,_ vh:Double) throws -> SurfaceParameterBox {
        .init(u:try .init(lower:ul,upper:uh),v:try .init(lower:vl,upper:vh))
    }
    static func selected(_ first:SurfaceParameterBox,_ second:SurfaceParameterBox) throws -> Relation {
        let s=input()
        return try owner(DefaultSurfaceSurfaceIntersector().intersectionResult(first:s,over:first,second:s,over:second,
            tolerance:.standard,maximumSpanCount:32,maximumSubdivisionDepth:8,remainingSourceDepth:1,consumeWork:{},consumeStorage:{_ in},maximumAlgebraicDepth:32))
    }
    static func endpoints() throws {
        let b=2*Double.pi
        let finite=try selected(box(0,b,-2,2),box(-b,0,-1,1))
        try require(finite.hasRegular && finite.hasApex && finite.pieces.count==1)
        let apexOnly=try selected(box(0,0.25,0,1),box(b/2,b/2+0.25,0,1))
        try require(apexOnly.hasApex && !apexOnly.hasRegular && apexOnly.pieces[0].imageDimension==0)
        let empty=try selected(box(0,0.25,1,2),box(b/2,b/2+0.25,1,2))
        try require(empty.isEmpty)
        let seam=try selected(box(-b/4,b/4,1,2),box(-b/4,b/4,1,2))
        try require(seam.pieces.count==1 && seam.pieces[0].otherPhase != nil && !seam.hasApex)
        let split=try selected(box(-b/4,b/4,1,2),box(b/8,7*b/8,1,2))
        try require(split.pieces.count==2)
        let ring=try selected(box(0,b,1,1),box(0,b,1,1))
        try require(ring.pieces[0].imageDimension==1)
        let ruling=try selected(box(0,0,1,2),box(b,b,1,2))
        try require(ruling.pieces[0].imageDimension==1)
        let point=try selected(box(0,0,1,1),box(b,b,1,1))
        try require(point.pieces[0].imageDimension==0)
        let r=try whole();var a=try ledger();let f=r.source.original.field,zero=try OriginalParameterCycle(exact:ExactRationalScalarDomain().integer(0,using:&a),using:&a)
        try rejects { _=try r.regular(phase:f.integer(0,using:&a),slant:f.integer(0,using:&a),firstCycle:zero,secondCycle:zero,limits:limits(),using:&a) }
        for i in 0..<4 { try rejects { try r.admitProof(limits:limits(source:i==0 ? 0:1,transport:i==1 ? 0:1,charts:i==2 ? 1:2,families:i==3 ? 1:2),using:&a) } }
        let plane=Surface3D.analytic(.plane(origin:.origin,normal:.unitZ))
        try require(OriginalCoincidentConeSnapshotProvider.angle(.init(first:plane,second:plane)) == nil)
        print("PASS exact selected connectivity, seam, apex-only/empty, circle/ruling/point dimensions and refusals")
    }
    final class Counter: Sendable {
        struct State: Sendable { var work = 0; var bytes = 0 }
        private let state = Mutex(State())
        let workLimit: Int; let byteLimit: Int; let cancelAt: Int?; let cancelStorageAt: Int?
        init(work: Int = 8_388_608, bytes: Int = 268_435_456, cancelAt: Int? = nil, cancelStorageAt: Int? = nil) {
            workLimit = work; byteLimit = bytes; self.cancelAt = cancelAt; self.cancelStorageAt = cancelStorageAt
        }
        func consume() throws {
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
    static func admitted(_ reversed: Bool = false, counter: Counter, empty: Bool = false, bare: Bool = false,
        sourceDepth: Int = 1, scalarDepth: Int = 32) throws -> SurfaceSurfaceIntersectionResult? {
        let first=input(reversed),second=first; let i = try ScalarInterval(lower: 0.25, upper: 0.75)
        let box = SurfaceParameterBox(u: i, v: i); let secondBox=try Self.box(2,2.25,0.25,0.75); let solver = DefaultSurfaceSurfaceIntersector()
        if empty {
            if bare {
                let values = try solver.intersections(first: first, over: box, second: second, over: secondBox,
                    options: .init(), tolerance: .standard, maximumSpanCount: 262_144, maximumSubdivisionDepth: 8,
                    remainingSourceDepth: sourceDepth, consumeWork: { try counter.consume() }, consumeStorage: { try counter.retain($0) }, maximumAlgebraicDepth: scalarDepth)
                try require(values.isEmpty); return nil
            }
            return try solver.intersectionResult(first: first, over: box, second: second, over: secondBox,
                options: .init(), tolerance: .standard, maximumSpanCount: 262_144, maximumSubdivisionDepth: 8,
                remainingSourceDepth: sourceDepth, consumeWork: { try counter.consume() }, consumeStorage: { try counter.retain($0) }, maximumAlgebraicDepth: scalarDepth)
        }
        if bare {
            let values = try solver.intersections(first: first, second: second, options: .init(), tolerance: .standard,
                maximumSpanCount: 262_144, maximumSubdivisionDepth: 8, remainingSourceDepth: sourceDepth,
                consumeWork: { try counter.consume() }, consumeStorage: { try counter.retain($0) }, maximumAlgebraicDepth: scalarDepth)
            try require(values.count == 1); return nil
        }
        return try solver.intersectionResult(first: first, second: second, options: .init(), tolerance: .standard,
            maximumSpanCount: 262_144, maximumSubdivisionDepth: 8, remainingSourceDepth: sourceDepth,
            consumeWork: { try counter.consume() }, consumeStorage: { try counter.retain($0) }, maximumAlgebraicDepth: scalarDepth)
    }
    static func publication() throws {
        for reversed in [false, true] {
            let first=input(reversed),second=first
            try require(DefaultSurfaceSurfaceIntersector().intersections(first: first, second: second, tolerance: .standard).count == 1)
            for empty in [false, true] {
                let measured = Counter(); let result = try admitted(reversed, counter: measured, empty: empty)
                guard let result else { throw Failure(line: #line) }; try require(owner(result).isEmpty == empty)
                let n = measured.totals
                _ = try admitted(reversed, counter: Counter(work: n.work, bytes: n.bytes), empty: empty)
                _ = try admitted(reversed, counter: Counter(work: n.work, bytes: n.bytes), empty: empty, bare: true)
                try rejects { _ = try admitted(reversed, counter: Counter(work: n.work - 1, bytes: n.bytes), empty: empty) }
                try rejects { _ = try admitted(reversed, counter: Counter(work: n.work, bytes: n.bytes - 1), empty: empty) }
                for at in [1, n.work / 2, n.work] {
                    try rejects { _ = try admitted(reversed, counter: Counter(cancelAt: at), empty: empty) }
                }
            }
        }
        try rejects { _ = try admitted(counter: Counter(), sourceDepth: 0) }
        try rejects { _ = try admitted(counter: Counter(), scalarDepth: 0) }
        let limited = try whole(); var a = try ledger()
        try rejects { _ = try Relation.resolve(source: limited.source, firstBox: nil, secondBox: nil,
            maximumComponents: 0, limits: limits(), using: &a) }
        print("PASS all six SSI entries, full/quarter-empty N-N1 resources, depth and cancellation")
    }
    static func prepared() throws {
        for reversed in [false, true] {
            let first=input(reversed),second=first, counter = Counter()
            let session = try DefaultSurfaceSurfaceIntersector().prepareOriginalPair(first: first, second: second,
                tolerance: .standard, maximumSpanCount: 262_144, maximumSubdivisionDepth: 8, remainingSourceDepth: 1,
                consumeWork: { try counter.consume() }, consumeStorage: { try counter.retain($0) }, maximumAlgebraicDepth: 32)
            let afterPrepare = counter.totals
#if !hasFeature(Embedded)
            print("prepared source work", afterPrepare.work); fflush(nil)
#endif
            let i = try ScalarInterval(lower: 0.25, upper: 0.75), box = SurfaceParameterBox(u: i, v: i), secondBox=try Self.box(2,2.25,0.25,0.75)
            let result = try session.intersectionResult(firstBox: box, secondBox: secondBox, options: .init())
#if !hasFeature(Embedded)
            print("prepared first query work", counter.totals.work); fflush(nil)
#endif
            let relation = try owner(result)
            try require(relation.isEmpty && result.intersections.isEmpty)
            try require(session.intersections(firstBox: box, secondBox: secondBox, options: .init()).isEmpty)
            let next=try owner(session.intersectionResult(firstBox:box,secondBox:secondBox,options:.init()))
            var a=try ledger();let chart=try next.source.chart(0,limits:limits().source,using:&a)
            try require(relation.source.owns(chart) && relation.firstRequest.sharesFrame(with:next.firstRequest)
                && relation.secondRequest.sharesFrame(with:next.secondRequest))
            try relation.admitProof(limits:limits(),using:&a)
        }
        print("PASS actual prepared reuse, complete selected exclusion and detached authority")
    }
    static func terminalCancel() async throws {
        for empty in [false, true] {
            let task = Task {
                let measured = Counter(); _ = try admitted(counter: measured, empty: empty)
                try rejects { _ = try admitted(counter: Counter(cancelStorageAt: measured.totals.bytes), empty: empty) }
                try require(Task<Never, Never>.isCancelled)
            }
            try await task.value
        }
        print("PASS terminal nonempty and empty publication cancel")
    }
    static func main() async throws {
#if hasFeature(Embedded)
        let group=getenv("CAD_PROOF_GROUP").map { String(cString:$0) } ?? "all"
#else
        let group=CommandLine.arguments.count>1 ? CommandLine.arguments[1]:"all"
#endif
        try require(["all","success","success-0","success-1","endpoints","publication","prepared","terminal"].contains(group))
        if group=="all" || group=="success" { try success() }
        if group=="success-0" { try success(selected:0) }
        if group=="success-1" { try success(selected:1) }
        if group=="all" || group=="endpoints" { try endpoints() }
        if group=="all" || group=="publication" { try publication() }
        if group=="all" || group=="prepared" { try prepared() }
        if group=="all" || group=="terminal" { try await terminalCancel() }
        print("PASS coincident cone SSI verification group")
    }
}
