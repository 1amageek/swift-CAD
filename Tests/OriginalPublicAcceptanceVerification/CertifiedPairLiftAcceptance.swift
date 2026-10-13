import CADCore
import CADGeometry
import Synchronization
#if canImport(Darwin)
import Darwin
#else
import WASILibc
#endif
@main struct CertifiedPairLiftAcceptance {
    typealias Relation = OriginalCertifiedPairLiftPlaneRelation
    struct Failure: Error { let line: Int }
    static func require(_ v: Bool, line: Int = #line) throws { guard v else { throw Failure(line: line) } }
    static func rejects(_ body: () throws -> Void) throws {
        do { try body() } catch let e as Failure { throw e } catch { return }; throw Failure(line: #line)
    }
    static func ledger(work: Int = 8_388_608, bytes: Int = 268_435_456, coefficient: Int = 32) throws -> ExactScalarLedger {
        .init(limits: try .init(work: work, storageBytes: bytes, valueDepth: 32, coefficientDepth: coefficient))
    }
    static func limits(source: Int = 3, charts: Int = 2, families: Int = 2, transport: Int = 2) throws -> OriginalDomainIdentityLimits {
        try .init(source: .init(remainingSourceDepth: source), maximumTransportDepth: transport,
            maximumCharts: charts, maximumFamilies: families, maximumIdentityProofs: 0)
    }
    static func input(_ positive: Bool, coneRole: Bool = true, reverse: Bool = false,
        start: Double? = nil, end: Double? = nil, swap: Bool = false) throws -> (Curve3D, Surface3D) {
        let cone=Surface3D.analytic(.cone(apex:.origin,axis:.unitZ,halfAngle:Double(bitPattern:0x3fddac670561bb50)))
        let cylinder=Surface3D.analytic(.cylinder(origin:.origin,axis:.unitZ,radius:1))
        let curve=try CertifiedConeCylinderIntersectionCurve(coneSurface:cone,cylinderSurface:cylinder,
            componentKind:positive ? .positiveFullBranch:.negativeFullBranch,lowerAngle:0,upperAngle:2*Double.pi,tolerance:.standard)
        let pair=try CertifiedAnalyticAnalyticIntersectionCurve(coneCylinderCurve:curve,
            firstSurface:swap ? cylinder:cone,secondSurface:swap ? cone:cylinder,tolerance:.standard)
        let role:SurfaceIntersectionSurfaceRole = coneRole != swap ? .first:.second
        let pcurve=try CertifiedAnalyticPairSurfaceParameterCurve(intersection:pair,role:role,
            startFraction:start ?? (reverse ? 0.75:0),endFraction:end ?? (reverse ? 0.25:1),tolerance:.standard)
        return (.surfaceLift(.init(surface:pair.surface(for:role),parameterCurve:.certifiedAnalyticPair(pcurve))),
            .plane(.init(origin:.origin,normal:.unitY,uDirection:.unitX)))
    }
    static func query(_ c:Curve3D,_ p:Surface3D,_ request:ScalarInterval? = nil,u:ScalarInterval? = nil) throws -> CurveSurfaceIntersectionResult {
        try DefaultCurveSurfaceIntersector().intersectionResult(curve:c,surface:p,
            options:.init(curveRange:request,surfaceURange:u),tolerance:.standard)
    }
    static func owner(_ result:CurveSurfaceIntersectionResult) throws -> Relation {
        guard let r=result.originalCertifiedPairLiftRelation else {throw Failure(line:#line)}
        try require(r.isEmpty == r.original.isEmpty && !r.hasPositiveDimensionalSolutions);return r.original
    }
    static func success() throws -> Relation {
        var retained:Relation?
        for positive in [false,true] {
            for coneRole in [false,true] {
                for reverse in [false,true] {
                    let (c,p)=try input(positive,coneRole:coneRole,reverse:reverse)
                    let result=try query(c,p,.init(lower:0,upper:1));let r=try owner(result)
                    try require(result.points.count == 2 && r.contacts.count == 2 && r.imageDimension == 0 && r.fiberDimension == 0)
                    try require(r.source.sourceDepth == 3 && r.source.original.isConeRole == coneRole)
                    for (i,point) in result.points.enumerated() {
                        try require(point.point.y == 0 && point.surfaceU == point.point.x && point.surfaceV == -point.point.z)
                        try require(point.curveParameter == (reverse ? Double(i):(i == 0 ? 0.25:0.75)))
                        try require(point.point.x == (reverse ? (i == 0 ? 1:-1):(i == 0 ? -1:1)))
                    }
                    try require(DefaultCurveSurfaceIntersector().intersections(curve:c,surface:p,
                        options:.init(curveRange:try .init(lower:0,upper:1)),tolerance:.standard).count == 2)
                    try require(owner(query(c,p,reverse ? .init(lower:0.25,upper:0.75):.init(lower:0,upper:0.125))).isEmpty)
                    try require(owner(query(c,p,nil,u:.init(lower:-1,upper:-1))).contacts.count == 1)
                    var a=try ledger();let f=r.source.original.child.original.field;let q=ExactRationalScalarDomain()
                    var huge=try q.integer(1,using:&a)
                    for _ in 0..<5 {huge=try q.multiplying(huge,q.integer(UInt64(1)<<32,using:&a),using:&a)}
                    let cp=try OriginalParameterCycle(exact:huge,using:&a)
                    let cn=try OriginalParameterCycle(exact:q.negated(huge,using:&a),using:&a)
                    let zero=try OriginalParameterCycle(exact:q.integer(0,using:&a),using:&a)
                    for i in 0..<2 {
                        let uv=try r.parentUV(contact:i,cylinderCycle:cp,coneCycle:cn,limits:limits(),using:&a)
                        let law=r.source.original.child.original
                        let cu=try law.cylinderLabel(parameter:r.contacts[i].childParameter,cycle:scalar(positive:true,field:f,using:&a),using:&a)
                        let ku=try law.coneLabel(parameter:r.contacts[i].childParameter,cycle:scalar(positive:false,field:f,using:&a),using:&a)
                        try require(f.compare(uv[0],cu,using:&a) == .equal && f.compare(uv[2],ku,using:&a) == .equal)
                        try require(f.compare(uv[1],law.height,using:&a) == .equal && f.compare(uv[3],law.coneSlant,using:&a) == .equal)
                        let local=try r.liftUV(contact:i,cycle:zero,limits:limits(),using:&a)
                        try require(local.count == 2 && f.compare(local.last!,coneRole ? law.coneSlant:law.height,using:&a) == .equal)
                    }
                    retained=r
                }
            }
        }
        for role in [false,true] {
            let (c,p)=try input(true,coneRole:role,swap:true)
            try require(owner(query(c,p)).source.original.isConeRole == role)
        }
        // Exact binary authored coefficients give rational root2/5 in this window.
        let (fractional,p)=try input(false,start:0.125,end:0.4375)
        let fractionalResult=try owner(query(fractional,p));try require(fractionalResult.contacts.count == 1)
        var a=try ledger();let f=fractionalResult.source.original.child.original.field
        let expected=try f.dividing(f.integer(2,using:&a),f.integer(5,using:&a),using:&a)
        try require(f.compare(fractionalResult.contacts[0].parameter,expected,using:&a) == .equal)
        try require(owner(query(fractional,p,.init(lower:0.4,upper:0.4))).isEmpty)
        let (wrong,p2)=try input(false)
        if case .surfaceLift(let lift)=wrong,case .certifiedAnalyticPair(let curve)=lift.parameterCurve {
            let opposite=curve.intersection.surface(for:curve.role == .first ? .second:.first)
            try rejects {_ = try query(.surfaceLift(.init(surface:opposite,parameterCurve:lift.parameterCurve)),p2)}
        } else {throw Failure(line:#line)}
        guard let retained else {throw Failure(line:#line)};return retained
    }
    static func scalar<A:ExactScalarAdmission & ~Copyable>(positive:Bool,field:OriginalPhysicalAngleScalarDomain,using a:inout A) throws -> OriginalPhysicalAngleValue {
        var value=try field.integer(1,using:&a)
        for _ in 0..<5 {value=try field.multiplying(value,field.integer(UInt64(1)<<32,using:&a),using:&a)}
        return positive ? value:try field.negated(value,using:&a)
    }
    static func prepared(_ r:Relation) throws {
        var a=try ledger();let f=r.source.original.child.original.field;let t=r.contacts[0].parameter
        let single=try ExactParameterInterval.checked(field:f,lower:.finite(t),upper:.finite(t),depth:r.proofDepth,using:&a)
        let full=try ExactParameterInterval<OriginalPhysicalAngleValue>.checked(field:f,lower:.negativeInfinity,upper:.positiveInfinity,depth:.init(value:0,coefficient:0),using:&a)
        let target=r.childRelation.targetSupport.frame.source
        let selected=try Relation.resolve(source:r.source,target:target,targetIntervals:[[full],[full]],requested:[[single]],maximumPoints:1,limits:limits(),using:&a)
        try require(selected.contacts.count == 1)
        let open=try ExactParameterInterval.checked(field:f,lower:.finite(r.contacts[0].parameter),upper:.finite(r.contacts[1].parameter),includesLower:false,includesUpper:false,depth:r.proofDepth,using:&a)
        let empty=try Relation.resolve(source:r.source,target:target,targetIntervals:[[full],[full]],requested:[[open]],maximumPoints:2,limits:limits(),using:&a)
        try require(empty.isEmpty)
        let copied=try input(false)
        let other=try owner(query(copied.0,copied.1))
        try rejects {_ = try f.importing(other.source.original.start,using:&a)}
        for control in 0..<4 {
            let l=try limits(source:control == 0 ? 2:3,charts:control == 1 ? 0:2,families:control == 2 ? 0:2,transport:control == 3 ? 1:2)
            try rejects {try r.admitProof(limits:l,using:&a)}
        }
        if r.proofDepth.coefficient > 0 {
            var shallow=try ledger(coefficient:r.proofDepth.coefficient-1)
            try rejects {try r.admitProof(limits:limits(),using:&shallow)}
        }
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
    static func admitted(_ curve: Curve3D, _ plane: Surface3D, request: ScalarInterval?, counter: Counter,
        sourceDepth: Int = 3, scalarDepth: Int = 32) throws -> CurveSurfaceIntersectionResult {
        try DefaultCurveSurfaceIntersector().intersectionResult(curve: curve, surface: plane,
            options: .init(curveRange: request), tolerance: .standard, maximumSpanCount: 262_144,
            maximumSubdivisionDepth: 8, remainingSourceDepth: sourceDepth,
            consumeWork: { try counter.consume($0) }, consumeStorage: { try counter.retain($0) },
            maximumAlgebraicDepth: scalarDepth)
    }
    static func logCount(_ label: StaticString, _ value: Int) {
        print(label, terminator: ": ")
        var divisor = 1
        while divisor <= value / 10 { divisor *= 10 }
        repeat { putchar(Int32(48 + value / divisor % 10)); divisor /= 10 } while divisor > 0
        putchar(10); fflush(nil)
    }
    static func resources() throws {
        let (curve, plane) = try input(false); let request = try ScalarInterval(lower: 0, upper: 1)
        let measured = Counter(); _ = try admitted(curve, plane, request: request, counter: measured)
        let counts = measured.totals; logCount("pair-lift work", counts.work); logCount("pair-lift bytes", counts.bytes)
        _ = try admitted(curve, plane, request: request, counter: Counter(work: counts.work, bytes: counts.bytes))
        try rejects { _ = try admitted(curve, plane, request: request, counter: Counter(work: counts.work - 1, bytes: counts.bytes)) }
        try rejects { _ = try admitted(curve, plane, request: request, counter: Counter(work: counts.work, bytes: counts.bytes - 1)) }
        for at in [1, counts.work / 2, counts.work] {
            try rejects { _ = try admitted(curve, plane, request: request, counter: Counter(cancelAt: at)) }
        }
        try rejects { _ = try admitted(curve, plane, request: request, counter: Counter(), sourceDepth: 0) }
        try rejects { _ = try admitted(curve, plane, request: request, counter: Counter(), scalarDepth: 0) }
        let empty = try ScalarInterval(lower: 0, upper: 0.125)
        let emptyMeasured = Counter(); let emptyResult = try admitted(curve, plane, request: empty, counter: emptyMeasured)
        try require(owner(emptyResult).isEmpty)
        let ec = emptyMeasured.totals
        _ = try admitted(curve, plane, request: empty, counter: Counter(work: ec.work, bytes: ec.bytes))
        try rejects { _ = try admitted(curve, plane, request: empty, counter: Counter(work: ec.work - 1, bytes: ec.bytes)) }
        try rejects { _ = try admitted(curve, plane, request: empty, counter: Counter(work: ec.work, bytes: ec.bytes - 1)) }
        print("PASS original caller N/N-1 work/storage for full and empty, depth and cancellation")
    }
    static func publicationCancellation() async throws {
        for empty in [false, true] {
            let task = Task {
                let (curve, plane) = try input(false)
                let request = try ScalarInterval(lower: 0, upper: empty ? 0.125 : 1)
                let measured = Counter(); _ = try admitted(curve, plane, request: request, counter: measured)
                try rejects { _ = try admitted(curve, plane, request: request,
                    counter: Counter(cancelStorageAt: measured.totals.bytes)) }
                try require(Task<Never, Never>.isCancelled)
            }
            try await task.value
        }
        print("PASS terminal cancellation of nonempty and complete empty publication")
    }
    static func main() async throws {
        let r=try success();try prepared(r);try resources();try await publicationCancellation()
        var a=try ledger();try r.admitProof(limits:limits(),using:&a)
        print("PASS certified role lifts, all local/child/parentUV, reverse endpoints, requests and lifetime")
    }
}
