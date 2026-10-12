import CADCore
@testable import CADGeometry
import Synchronization
#if canImport(Darwin)
import Darwin
#elseif canImport(WASILibc)
import WASILibc
#endif

@main struct PeriodicOffsetCSAcceptance {
    typealias Base = OriginalExactScalarDomain
    typealias Field = ExactAlgebraicScalarDomain<Base>
    struct Admission: ~Copyable, ExactScalarAdmission {
        var ledger: ExactScalarLedger
        init(work: Int = 50_000_000, bytes: Int = 1_073_741_824) throws {
            ledger = .init(limits:try .init(work:work,storageBytes:bytes,valueDepth:32,coefficientDepth:32))
        }
        mutating func checkpoint() throws(ExactScalarFailure) { try ledger.checkpoint() }
        mutating func consumeWork(_ n: Int) throws(ExactScalarFailure) { try ledger.consumeWork(n) }
        mutating func retainStorage(bytes: Int) throws(ExactScalarFailure) { try ledger.retainStorage(bytes:bytes) }
        mutating func visitCell(axis: ExactScalarRootAxis, depth: Int) throws(ExactScalarFailure) { try ledger.visitCell(axis:axis,depth:depth) }
        mutating func admitDepth(value: Int, coefficient: Int) throws(ExactScalarFailure) { try ledger.admitDepth(value:value,coefficient:coefficient) }
    }
    struct Counts: Sendable { var work = 0; var bytes = 0; var storageCalls = 0 }
    final class Counter: Sendable {
        let state = Mutex(Counts())
        let workLimit: Int, byteLimit: Int, cancelWork: Int?, cancelStorage: Int?
        init(work: Int = 8_388_608, bytes: Int = Int.max, cancelWork: Int? = nil, cancelStorage: Int? = nil) {
            workLimit = work; byteLimit = bytes; self.cancelWork = cancelWork; self.cancelStorage = cancelStorage
        }
        func work() throws {
            let cancel = try state.withLock { s in
                guard s.work < workLimit else { throw ExactScalarFailure.resourceLimit(.work) }
                s.work += 1; return s.work == cancelWork
            }
            if cancel { withUnsafeCurrentTask { $0?.cancel() } }
        }
        func storage(_ n: Int) throws {
            let cancel = try state.withLock { s in
                let next = s.bytes.addingReportingOverflow(n)
                guard n >= 0, !next.overflow, next.partialValue <= byteLimit else { throw ExactScalarFailure.resourceLimit(.storage) }
                s.bytes = next.partialValue; s.storageCalls += 1; return s.storageCalls == cancelStorage
            }
            if cancel { withUnsafeCurrentTask { $0?.cancel() } }
        }
        var counts: Counts { state.withLock { $0 } }
    }
    static func log(_ s: String) { s.withCString { _ = puts($0) } }
    struct Assertion: Error { let line: Int }
    static func require(_ test: Bool, line: Int = #line) throws { if !test { throw Assertion(line:line) } }
    static func native() -> BSplineSurface3D {
        let xy:[(Double,Double)]=[(0,0),(1,0),(0,1),(0,0)]
        return .init(uDegree:1,vDegree:1,uKnots:[-1,0,1,2,3,4],vKnots:[-1,0,1,2,3,4],
            controlPoints:xy.map { v in xy.map { u in .init(x:u.0,y:u.1+v.0,z:v.1) } },isUPeriodic:true,isVPeriodic:true)
    }
    static func shape(_ native:BSplineSurface3D?=nil) -> Surface3D { .procedural(.offset(.init(source:.bSpline(native ?? self.native()),distance:0))) }
    static func curve(_ z:Double=0) -> Curve3D {
        let p=Point3D(x:0.25,y:0.5,z:z)
        return .bSpline(.init(degree:1,knots:[0,0,1,1],controlPoints:[p,p]))
    }
    static func query(_ options:CurveSurfaceIntersectionOptions = .init(),z:Double=0,counter:Counter?=nil,
        spans:Int=262144,sourceDepth:Int=8,depth:Int=32,surface:Surface3D?=nil) throws -> CurveSurfaceIntersectionResult {
        let solver=DefaultCurveSurfaceIntersector(),host=surface ?? shape()
        guard let c=counter else { return try solver.intersectionResult(curve:curve(z),surface:host,options:options,tolerance:.standard) }
        return try solver.intersectionResult(curve:curve(z),surface:host,options:options,tolerance:.standard,
            maximumSpanCount:spans,maximumSubdivisionDepth:8,remainingSourceDepth:sourceDepth,
            consumeWork:{ _ in try c.work() },consumeStorage:{ try c.storage($0) },maximumAlgebraicDepth:depth)
    }
    static func failure(_ body:()throws->Void,code:KernelErrorCode = .resourceLimitExceeded) throws {
        do { try body() } catch let e as KernelError { try require(e.code==code);return }
        throw ExactScalarFailure.invalidEvidence
    }
    static func limits() throws -> OriginalDomainIdentityLimits {
        try .init(source:.init(remainingSourceDepth:8),maximumTransportDepth:32,maximumCharts:32,maximumFamilies:2,maximumIdentityProofs:0)
    }
    static func zeroCycles(_ a:inout Admission) throws -> [OriginalParameterCycle] {
        let zero=try OriginalParameterCycle(exact:ExactRationalScalarDomain().integer(0,using:&a),using:&a)
        return [zero,zero]
    }
    static func oracle(_ result:CurveSurfaceIntersectionResult,empty:Bool=false,dimension:Int=1) throws {
        guard let receipt=result.originalIssuedGeometricRelation as? OriginalPeriodicOffsetGeometricRelations else { throw ExactScalarFailure.invalidEvidence }
        try require(result.representation == .exactRelation && result.points.isEmpty && result.overlaps.isEmpty)
        try require(receipt.isEmpty==empty && !receipt.hasPositiveDimensionalImage)
        try require(receipt.hasPositiveDimensionalSolutions == (!empty && dimension>0))
        try require(receipt.originalGraphs.count==9 && receipt.surfaceCover.integerFamilyRank==2)
        var a=try Admission();let f=receipt.surfaceCover.space.family.field
        let squares=[[1,2,1],[1,3,2],[0,1,1]]
        for g in receipt.originalGraphs {
            let spans=g.evidence.child.chart.selection.spans,uSpan=spans[0],vSpan=spans[1],r=g.polynomials
            let u=try r.variable(0,using:&a),v=try r.variable(1,using:&a)
            func k(_ n:Int) throws -> ExactPolynomial<Base> { try r.constant(f.integer(n,using:&a),using:&a) }
            func first(_ t:ExactPolynomial<Base>,_ span:Int) throws -> ExactPolynomial<Base> {
                if span==1 { return t };if span==2 { return try r.subtracting(k(2),t,using:&a) };return try k(0)
            }
            func second(_ t:ExactPolynomial<Base>,_ span:Int) throws -> ExactPolynomial<Base> {
                if span==1 { return try k(0) };if span==2 { return try r.subtracting(t,k(1),using:&a) };return try r.subtracting(k(3),t,using:&a)
            }
            let expected=[try first(u,uSpan),try r.adding(second(u,uSpan),first(v,vSpan),using:&a),try second(v,vSpan)]
            for axis in 0..<3 { try require(try r.equals(g.homogeneous[axis],r.multiplying(g.homogeneous[3],expected[axis],using:&a),using:&a)) }
            try require(try r.equals(g.evidence.normalSquared,k(squares[uSpan-1][vSpan-1]),using:&a))
            let root=try r.variable(2,using:&a)
            try require(try r.equals(g.evidence.positiveRootEquation,r.subtracting(r.multiplying(root,root,using:&a),k(squares[uSpan-1][vSpan-1]),using:&a),using:&a))
        }
        if !empty {
            try require(receipt.periodicOffsetContacts.count==1)
            let t=receipt.periodicOffsetContacts[0]
            try require(t.parameterDimension==dimension && t.imageDimension==0 && t.fiberDimension==dimension)
            for (value,expected) in zip(t.fundamentalUV+[t.normalLength]+t.position,[0.25,0.5,1,0.25,0.5,0]) {
                try require(try f.compare(value,f.binary64(exactly:expected,using:&a),using:&a) == .equal)
            }
        }
    }
    static func run(_ group:String) async throws {
        switch group {
        case "success":
            try oracle(query());let c=Counter();try oracle(query(counter:c));log("COUNTS \(c.counts.work) \(c.counts.bytes) \(c.counts.storageCalls)")
            let receipt=try query().originalIssuedGeometricRelation!,template=receipt.periodicOffsetContacts[0]
            for axis in template.cycleDomains { guard let interval=axis.intervals.first,case .negativeInfinity=interval.lower,case .positiveInfinity=interval.upper else { throw ExactScalarFailure.invalidEvidence } }
        case "cycles":
            let template=try query().originalIssuedGeometricRelation!.periodicOffsetContacts[0],f=template.field,l=try limits()
            var a=try Admission()
            for sign in [-1,1] {
                let q=ExactRationalScalarDomain(),base=try q.integer(UInt64(1)<<32,using:&a)
                let magnitude=try q.adding(q.multiplying(q.multiplying(base,base,using:&a),base,using:&a),q.integer(7,using:&a),using:&a)
                let big=try sign<0 ? q.negated(magnitude,using:&a):magnitude
                let other=try ExactRationalScalarDomain().negated(big,using:&a)
                let cycles=[try OriginalParameterCycle(exact:big,using:&a),try OriginalParameterCycle(exact:other,using:&a)]
                let member=try template.member(cycles:cycles,limits:l,using:&a)
                try require(!member.isEmpty && member.parameterDimension==1 && member.fiberDimension==1 && member.imageDimension==0)
                for axis in 0..<2 {
                    let expected=try f.adding(template.fundamentalUV[axis],f.multiplying(f.integer(3,using:&a),f.rational(exactly:cycles[axis].original,using:&a),using:&a),using:&a)
                    try require(try f.compare(member.originalUV[axis],expected,using:&a) == .equal)
                }
                for t in [0.0,0.5,1.0] { try require(try member.contains([f.binary64(exactly:t,using:&a)]+member.originalUV+[member.normalLength],limits:l,using:&a)) }
                try require(try !member.contains([f.integer(0,using:&a)]+member.originalUV+[f.integer(-1,using:&a)],limits:l,using:&a))
            }
        case "requests":
            let options=CurveSurfaceIntersectionOptions(curveRange:try .init(lower:0.25,upper:0.75),surfaceURange:try .init(lower:-5.75,upper:6.25),surfaceVRange:try .init(lower:-2.5,upper:3.5))
            let result=try query(options);try oracle(result)
            let template=result.originalIssuedGeometricRelation!.periodicOffsetContacts[0]
            var a=try Admission();let q=ExactRationalScalarDomain(),l=try limits()
            for axis in 0..<2 {
                guard let interval=template.cycleDomains[axis].intervals.first,case .finite(let lo)=interval.lower,case .finite(let hi)=interval.upper else { throw ExactScalarFailure.invalidEvidence }
                try require(try q.compare(lo,q.integer(axis==0 ? -2:-1,using:&a),using:&a) == .equal)
                try require(try q.compare(hi,q.integer(axis==0 ? 2:1,using:&a),using:&a) == .equal)
            }
            for k in -3...3 { for j in -2...2 {
                let member=try template.member(cycles:[OriginalParameterCycle(exact:q.integer(k,using:&a),using:&a),OriginalParameterCycle(exact:q.integer(j,using:&a),using:&a)],limits:l,using:&a)
                try require(member.isEmpty == (abs(k)>2 || abs(j)>1))
            } }
            try oracle(query(.init(curveRange:try .init(lower:0.5,upper:0.5))),dimension:0)
        case "empty":
            try oracle(query(z:2),empty:true)
            try oracle(query(.init(surfaceURange:try .init(lower:0,upper:0))),empty:true)
            try oracle(query(.init(curveRange:try .init(lower:2,upper:3))),empty:true)
        case "bare":
            let solver=DefaultCurveSurfaceIntersector(),c=Counter()
            try failure({ _=try solver.intersections(curve:curve(),surface:shape(),options:.init(),tolerance:.standard) },code:.nonDiscreteIntersection)
            try failure({ _=try solver.intersections(curve:curve(),surface:shape(),options:.init(),tolerance:.standard,maximumSpanCount:32,maximumSubdivisionDepth:8,remainingSourceDepth:8,consumeWork:{ _ in try c.work() },consumeStorage:{ try c.storage($0) }) },code:.nonDiscreteIntersection)
            try require(try solver.intersections(curve:curve(2),surface:shape(),options:.init(),tolerance:.standard).isEmpty)
        case "resources":
            let c=Counter();_=try query(counter:c);let n=c.counts
            try oracle(query(counter:Counter(work:n.work,bytes:n.bytes)))
            try failure { _=try query(counter:Counter(work:n.work-1)) }
            try failure { _=try query(counter:Counter(bytes:n.bytes-1)) }
            try failure { _=try query(counter:Counter(work:0)) }
            try failure { _=try query(counter:Counter(bytes:0)) }
            log("BOUNDARY \(n.work) \(n.bytes)")
        case "limits":
            try failure { _=try query(counter:Counter(),spans:8) }
            try failure { _=try query(counter:Counter(),sourceDepth:0) }
            try failure { _=try query(counter:Counter(),depth:0) }
            try failure { _=try query(.init(maximumPolynomialDegree:1),counter:Counter()) }
            let template=try query().originalIssuedGeometricRelation!.periodicOffsetContacts[0]
            var a=try Admission();let l=try limits()
            do { _=try template.member(cycles:[],limits:l,using:&a);throw ExactScalarFailure.invalidEvidence } catch OriginalDomainIdentityFailure.invalidDomain { }
            let member=try template.member(cycles:zeroCycles(&a),limits:l,using:&a)
            let shallow=try OriginalDomainIdentityLimits(source:.init(remainingSourceDepth:0),maximumTransportDepth:32,maximumCharts:32,maximumFamilies:2,maximumIdentityProofs:0)
            let f=template.field
            do { _=try member.contains([f.integer(0,using:&a)]+member.originalUV+[member.normalLength],limits:shallow,using:&a);throw ExactScalarFailure.invalidEvidence } catch OriginalSourceIssuanceFailure.sourceDepthLimit { }
            let foreign=try Base(maximumValueDepth:32,maximumCoefficientDepth:32,using:&a)
            do { _=try member.contains([foreign.integer(0,using:&a)]+member.originalUV+[member.normalLength],limits:l,using:&a);throw ExactScalarFailure.invalidEvidence } catch ExactScalarFailure.incompatibleDomain { }
        case "cancel":
            let c=Counter();_=try query(counter:c)
            for counter in [Counter(cancelWork:1),Counter(cancelWork:c.counts.work/2),Counter(cancelStorage:c.counts.storageCalls)] {
                let task=Task { () -> Bool in
                    do { _=try query(counter:counter);return false } catch is CancellationError { return true } catch let e as KernelError { return e.code == .cancelled } catch { return false }
                };try require(await task.value)
            }
            let cEmpty=Counter();_=try query(z:2,counter:cEmpty)
            let task=Task { () -> Bool in
                do { _=try query(z:2,counter:Counter(cancelStorage:cEmpty.counts.storageCalls));return false } catch is CancellationError { return true } catch let e as KernelError { return e.code == .cancelled } catch { return false }
            };try require(await task.value)
            let entry=Task { () -> Bool in
                withUnsafeCurrentTask { $0?.cancel() };do { _=try query();return false } catch is CancellationError { return true } catch let e as KernelError { return e.code == .cancelled } catch { return false }
            };try require(await entry.value)
            let template=try query().originalIssuedGeometricRelation!.periodicOffsetContacts[0]
            var a=try Admission();let cycles=try zeroCycles(&a),l=try limits();a.ledger.cancel()
            do { _=try template.member(cycles:cycles,limits:l,using:&a);throw ExactScalarFailure.invalidEvidence } catch ExactScalarFailure.cancelled { }
        case "lifetime":
            var input=native();let host=shape(input),retained=try query(surface:host)
            input.controlPoints[0][0] = .init(x:99,y:99,z:99)
            try require(input != native())
            let one=Task { try oracle(retained) },two=Task { try oracle(retained) };try await one.value;try await two.value
            var a=try Admission();let template=retained.originalIssuedGeometricRelation!.periodicOffsetContacts[0],l=try limits()
            let member=try template.member(cycles:zeroCycles(&a),limits:l,using:&a)
            try require(try member.contains([template.field.integer(0,using:&a)]+member.originalUV+[member.normalLength],limits:l,using:&a))
        default: throw ExactScalarFailure.invalidEvidence
        }
        log("PASS \(group)")
    }
    static func main() async {
        do { try await run(getenv("CAD_PROOF_GROUP").map { String(cString:$0) } ?? "success") }
        catch let e as KernelError { log("FAIL Kernel \(e.code.rawValue) \(e.message)");exit(1) }
        catch let e as Assertion { log("FAIL assertion \(e.line)");exit(1) }
        catch { log("FAIL exact proof");exit(1) }
    }
}
