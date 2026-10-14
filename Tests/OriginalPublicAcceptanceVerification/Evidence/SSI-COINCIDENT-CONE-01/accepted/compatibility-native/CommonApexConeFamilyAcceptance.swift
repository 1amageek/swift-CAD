import CADCore
import CADGeometry
import Synchronization
#if canImport(Darwin)
import Darwin
#else
import WASILibc
#endif

@main struct CommonApexConeFamilyAcceptance {
    typealias Relation = OriginalCommonApexConeRelation
    struct Failure: Error { let line: Int }
    static func require(_ value: Bool, line: Int = #line) throws { guard value else { throw Failure(line: line) } }
    static func rejects(_ body: () throws -> Void) throws {
        do { try body() } catch let e as Failure { throw e } catch { return }; throw Failure(line: #line)
    }
    static func input(_ reversed: Bool = false, caseIndex: Int = 0) -> (Surface3D, Surface3D) {
        let alpha=Double(bitPattern:0x3fddac670561bb50),beta=Double(bitPattern:0x3fd6f61941e4def1)
        let apex=caseIndex==4 ? Point3D(x:2,y:4,z:-7):.origin
        let first=Surface3D.analytic(.cone(apex:apex,axis:caseIndex==4 ? .unitX:.unitZ,
            halfAngle:caseIndex==1 ? 0.5:caseIndex==4 ? 0.25:alpha))
        let second=Surface3D.analytic(.cone(apex:apex,
            axis:caseIndex==2 || caseIndex==3 ? .unitZ:caseIndex==4 ? .init(x:0,y:0,z:-1):.unitY,
            halfAngle:caseIndex==1 || caseIndex==4 ? 0.5:caseIndex==3 ? alpha.nextUp:beta))
        return reversed ? (second,first):(first,second)
    }
    static func ledger(work: Int = 8_388_608, bytes: Int = 268_435_456, value: Int = 32, coefficient: Int = 32)
        throws -> ExactScalarLedger {
        .init(limits: try .init(work: work, storageBytes: bytes, valueDepth: value, coefficientDepth: coefficient))
    }
    static func limits(source: Int = 1, transport: Int = 1, charts: Int = 2, families: Int = 2) throws -> OriginalDomainIdentityLimits {
        try .init(source: .init(remainingSourceDepth: source), maximumTransportDepth: transport,
            maximumCharts: charts, maximumFamilies: families, maximumIdentityProofs: 2)
    }
    static func owner(_ result: SurfaceSurfaceIntersectionResult) throws -> Relation {
        guard let reader = result.originalCommonApexConeRelation else { throw Failure(line: #line) }
        try require(result.representation == .exactRelation)
        try require(reader.isEmpty == reader.original.isEmpty && reader.hasPositiveDimensionalSolutions == ((reader.original.fiberDimension ?? 0)>0))
        return reader.original
    }
    static func whole(_ reversed: Bool = false, caseIndex: Int = 0) throws -> Relation {
        let (first, second)=input(reversed,caseIndex:caseIndex)
        let result=try DefaultSurfaceSurfaceIntersector().intersectionResult(first:first,second:second,tolerance:.standard)
        let relation=try owner(result)
        try require(!relation.isEmpty && result.intersections.count == 1 && relation.imageDimension == 0 && relation.fiberDimension == 2)
        try require(relation.originalParameterDimension == 4 && relation.firstIdentity?.kind == .collapsedSubset && relation.secondIdentity?.kind == .collapsedSubset)
        guard case .originalCommonApexCone(let c)=result.intersections[0] else { throw Failure(line:#line) }
        try require(c.relation === relation && c.imageDimension == 0 && c.fiberDimension == 2)
        try require(relation.source.original.original.first == first && relation.source.original.original.second == second)
        return relation
    }
    static func success(selected: Int? = nil) throws {
        for caseIndex in 0..<5 where selected == nil || selected == caseIndex {
        for reverse in [false,true] {
            let relation=try whole(reverse,caseIndex:caseIndex), f=relation.source.original.field
            var a=try ledger();let huge=try f.binary64(exactly:1e100,using:&a)
            for n in [-7,0,11] {
                let u=try f.dividing(f.integer(n,using:&a),f.integer(3,using:&a),using:&a)
                let m=try relation.member(firstU:u,secondU:huge,limits:limits(),using:&a)
                try require(f.compare(m.firstUV.u,u,using:&a) == .equal && f.compare(m.secondUV.u,huge,using:&a) == .equal)
                try require(f.sign(of:m.firstUV.v,using:&a) == .zero && f.sign(of:m.secondUV.v,using:&a) == .zero)
            }
            let expected = caseIndex==4 ? Point3D(x:2,y:4,z:-7):.origin
            let point=try relation.member(firstU:f.integer(0,using:&a),secondU:f.integer(0,using:&a),limits:limits(),using:&a)
            try require(f.compare(point.position.x,f.binary64(exactly:expected.x,using:&a),using:&a) == .equal)
            try require(f.compare(point.position.y,f.binary64(exactly:expected.y,using:&a),using:&a) == .equal)
            try require(f.compare(point.position.z,f.binary64(exactly:expected.z,using:&a),using:&a) == .equal)
            switch relation.source.original.exclusion {
            case .orthogonalDirections: try require(caseIndex != 2 && caseIndex != 3)
            case .distinctPhysicalAngles: try require(caseIndex==2 || caseIndex==3)
            }
            if caseIndex==1 {
                let u=try ScalarInterval(lower: -2*Double.pi,upper:2*Double.pi)
                let v=try ScalarInterval(lower:-2,upper:2), box=SurfaceParameterBox(u:u,v:v)
                let (first,second)=input(reverse,caseIndex:caseIndex)
                let selected=try owner(DefaultSurfaceSurfaceIntersector().intersectionResult(first:first,over:box,
                    second:second,over:box,tolerance:.standard,maximumSpanCount:32,maximumSubdivisionDepth:8,
                    remainingSourceDepth:1,consumeWork:{},consumeStorage:{_ in},maximumAlgebraicDepth:32))
                try require(selected.fiberDimension==2)
                let endpoint=try selected.member(firstU:f.binary64(exactly:u.lower,using:&a),secondU:f.binary64(exactly:u.upper,using:&a),limits:limits(),using:&a)
                try require(endpoint.relation === selected)
                try rejects { _=try selected.member(firstU:f.binary64(exactly:u.upper.nextUp,using:&a),secondU:f.integer(0,using:&a),limits:limits(),using:&a) }
            }
            let i=try ScalarInterval(lower:-2,upper:3), z=try ScalarInterval(lower:0,upper:0)
            let box=SurfaceParameterBox(u:i,v:z), pointBox=SurfaceParameterBox(u:z,v:z)
            let window=try Relation.resolve(source:relation.source,firstBox:box,secondBox:pointBox,maximumComponents:1,limits:limits(),prepared:relation,using:&a)
            try require(!window.isEmpty && window.fiberDimension == 1)
            let m=try window.member(firstU:f.integer(1,using:&a),secondU:f.integer(0,using:&a),limits:limits(),using:&a)
            try require(m.relation === window)
            try rejects { _=try window.member(firstU:f.integer(4,using:&a),secondU:f.integer(0,using:&a),limits:limits(),using:&a) }
            let singleton=try Relation.resolve(source:relation.source,firstBox:pointBox,secondBox:pointBox,maximumComponents:1,limits:limits(),using:&a)
            try require(singleton.fiberDimension == 0 && !singleton.hasPositiveDimensionalSolutions)
            let reader=try DefaultSurfaceSurfaceIntersector().intersectionResult(first:input(reverse,caseIndex:caseIndex).0,over:pointBox,second:input(reverse,caseIndex:caseIndex).1,over:pointBox,tolerance:.standard,maximumSpanCount:32,maximumSubdivisionDepth:8,remainingSourceDepth:1,consumeWork:{},consumeStorage:{_ in},maximumAlgebraicDepth:32)
            try require(owner(reader).fiberDimension == 0)
        }
        }
        print("PASS complete original apex product, real UV, finite/singleton scope and dimensions")
    }
    static func endpoints() throws {
        let relation=try whole();var a=try ledger()
        for index in 0..<4 {
            try rejects { try relation.admitProof(limits:limits(source:index==0 ? 0:1,transport:index==1 ? 0:1,charts:index==2 ? 1:2,families:index==3 ? 1:2),using:&a) }
        }
        let other=try whole(true)
        try rejects { _=try Relation.resolve(source:other.source,firstBox:nil,secondBox:nil,maximumComponents:1,limits:limits(),prepared:relation,using:&a) }
        let restricted=try OriginalDomainIdentityLimits(source:.init(remainingSourceDepth:1),maximumTransportDepth:1,maximumCharts:2,maximumFamilies:2,maximumIdentityProofs:1)
        try rejects { try relation.admitProof(limits:restricted,using:&a) }
        var cancelled=try ledger();cancelled.cancel()
        try rejects { _=try relation.member(firstU:relation.source.original.field.integer(0,using:&a),secondU:relation.source.original.field.integer(0,using:&a),limits:limits(),using:&cancelled) }
        let same=Surface3D.analytic(.cone(apex:.origin,axis:.unitZ,halfAngle:0.5))
        try require(OriginalCommonApexConeSnapshotProvider.pair(.init(first:same,second:same)) == nil)
        let foreign=Surface3D.analytic(.cone(apex:.init(x:2,y:0,z:4),axis:.unitY,halfAngle:0.5))
        try require(OriginalCommonApexConeSnapshotProvider.pair(.init(first:same,second:foreign)) == nil)
        print("PASS scoped identities, finite support and foreign/limit/cancel refusal")
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
        sourceDepth: Int = 1, scalarDepth: Int = 32, caseIndex: Int = 0) throws -> SurfaceSurfaceIntersectionResult? {
        let (first, second) = input(reversed,caseIndex:caseIndex); let i = try ScalarInterval(lower: 0.25, upper: 0.75)
        let box = SurfaceParameterBox(u: i, v: i); let solver = DefaultSurfaceSurfaceIntersector()
        if empty {
            if bare {
                let values = try solver.intersections(first: first, over: box, second: second, over: box,
                    options: .init(), tolerance: .standard, maximumSpanCount: 262_144, maximumSubdivisionDepth: 8,
                    remainingSourceDepth: sourceDepth, consumeWork: { try counter.consume() }, consumeStorage: { try counter.retain($0) }, maximumAlgebraicDepth: scalarDepth)
                try require(values.isEmpty); return nil
            }
            return try solver.intersectionResult(first: first, over: box, second: second, over: box,
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
    static func publication(selected: Int? = nil) throws {
        for caseIndex in 0..<5 where selected == nil || selected == caseIndex {
        for reversed in [false, true] {
            let (first, second) = input(reversed,caseIndex:caseIndex)
            try require(DefaultSurfaceSurfaceIntersector().intersections(first: first, second: second, tolerance: .standard).count == 1)
            for empty in [false, true] {
                let measured = Counter(); let result = try admitted(reversed, counter: measured, empty: empty, caseIndex:caseIndex)
                guard let result else { throw Failure(line: #line) }; try require(owner(result).isEmpty == empty)
                let n = measured.totals
                _ = try admitted(reversed, counter: Counter(work: n.work, bytes: n.bytes), empty: empty, caseIndex:caseIndex)
                _ = try admitted(reversed, counter: Counter(work: n.work, bytes: n.bytes), empty: empty, bare: true, caseIndex:caseIndex)
                try rejects { _ = try admitted(reversed, counter: Counter(work: n.work - 1, bytes: n.bytes), empty: empty, caseIndex:caseIndex) }
                try rejects { _ = try admitted(reversed, counter: Counter(work: n.work, bytes: n.bytes - 1), empty: empty, caseIndex:caseIndex) }
                for at in [1, n.work / 2, n.work] {
                    try rejects { _ = try admitted(reversed, counter: Counter(cancelAt: at), empty: empty, caseIndex:caseIndex) }
                }
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
    static func prepared(selected: Int? = nil) throws {
        for caseIndex in 0..<5 where selected == nil || selected == caseIndex {
        for reversed in [false, true] {
            let (first, second) = input(reversed,caseIndex:caseIndex), counter = Counter()
            let session = try DefaultSurfaceSurfaceIntersector().prepareOriginalPair(first: first, second: second,
                tolerance: .standard, maximumSpanCount: 262_144, maximumSubdivisionDepth: 8, remainingSourceDepth: 1,
                consumeWork: { try counter.consume() }, consumeStorage: { try counter.retain($0) }, maximumAlgebraicDepth: 32)
            let afterPrepare = counter.totals
#if !hasFeature(Embedded)
            print("prepared source work", afterPrepare.work); fflush(nil)
#endif
            let i = try ScalarInterval(lower: 0.25, upper: 0.75), box = SurfaceParameterBox(u: i, v: i)
            let result = try session.intersectionResult(firstBox: box, secondBox: box, options: .init())
#if !hasFeature(Embedded)
            print("prepared first query work", counter.totals.work); fflush(nil)
#endif
            let relation = try owner(result)
            try require(relation.isEmpty && result.intersections.isEmpty)
            try require(session.intersections(firstBox: box, secondBox: box, options: .init()).isEmpty)
            try require(counter.totals.work - afterPrepare.work < afterPrepare.work)
            var a = try ledger(); try relation.admitProof(limits: limits(), using: &a)
        }
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
        let group = getenv("CAD_PROOF_GROUP").map { String(cString: $0) } ?? "all"
#else
        let group = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "all"
#endif
        let known=["all","success","endpoints","publication","prepared","terminal"].contains(group)
            || (0..<5).contains { group=="success-"+String($0) || group=="publication-"+String($0) || group=="prepared-"+String($0) }
        try require(known)
        if group=="all" || group=="success" { try success() }
        if group=="all" || group=="endpoints" { try endpoints() }
        if group=="all" || group=="publication" { try publication() }
        if group=="all" || group=="prepared" { try prepared() }
        if group=="all" || group=="terminal" { try await terminalCancel() }
        for index in 0..<5 {
            if group=="success-"+String(index) { try success(selected:index) }
            if group=="publication-"+String(index) { try publication(selected:index) }
            if group=="prepared-"+String(index) { try prepared(selected:index) }
        }
#if hasFeature(Embedded)
        print("PASS common-apex cone family group")
#else
        print("PASS common-apex cone family group",group)
#endif
    }
}
