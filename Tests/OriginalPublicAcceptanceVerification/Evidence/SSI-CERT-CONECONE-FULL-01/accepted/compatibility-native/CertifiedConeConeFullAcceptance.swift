import CADCore
import CADGeometry
import Synchronization
#if canImport(Darwin)
import Darwin
#else
import WASILibc
#endif
@main struct CertifiedConeConeFullAcceptance {
    typealias Relation = OriginalCertifiedConeConePlaneRelation
    struct Failure: Error { let line: Int }
    static func require(_ value: Bool, line: Int = #line) throws { guard value else { throw Failure(line: line) } }
    static func rejects(_ body: () throws -> Void) throws {
        do { try body() } catch let e as Failure { throw e } catch { return }; throw Failure(line: #line)
    }
    static func ledger(work: Int = 8_388_608, bytes: Int = 268_435_456) throws -> ExactScalarLedger {
        .init(limits: try .init(work: work, storageBytes: bytes, valueDepth: 32, coefficientDepth: 32))
    }
    static func limits(source: Int = 1, families: Int = 2, charts: Int = 1, transport: Int = 1) throws -> OriginalDomainIdentityLimits {
        try .init(source: .init(remainingSourceDepth: source), maximumTransportDepth: transport,
            maximumCharts: charts, maximumFamilies: families, maximumIdentityProofs: 0)
    }
    static func input(_ positive: Bool) throws -> (Curve3D, Surface3D) {
        let source = try CertifiedConeConeIntersectionCurve(
            referenceSurface: .analytic(.cone(apex: .origin, axis: .unitZ, halfAngle: Double(bitPattern: 0x3fddac670561bb50))),
            parameterizedSurface: .analytic(.cone(apex: .init(x: 0, y: 0, z: 4), axis: .unitY, halfAngle: Double(bitPattern: 0x3fd6f61941e4def1))),
            componentKind: positive ? .positiveFullBranch : .negativeFullBranch,
            lowerAngle: 0, upperAngle: 2 * Double.pi, tolerance: .standard)
        return (.certifiedIntersection(.coneCone(source)), .plane(.init(origin: .origin, normal: .unitX, uDirection: .unitZ)))
    }
    static func query(_ curve: Curve3D, _ plane: Surface3D, _ request: ScalarInterval? = nil,
        u: ScalarInterval? = nil, v: ScalarInterval? = nil) throws -> CurveSurfaceIntersectionResult {
        try DefaultCurveSurfaceIntersector().intersectionResult(curve: curve, surface: plane,
            options: .init(curveRange: request, surfaceURange: u, surfaceVRange: v), tolerance: .standard)
    }
    static func owner(_ result: CurveSurfaceIntersectionResult) throws -> Relation {
        guard let r = result.originalCertifiedConeConeRelation else { throw Failure(line: #line) }
        try require(r.isEmpty == r.original.isEmpty && !r.hasPositiveDimensionalSolutions); return r.original
    }
    static func success() throws -> Relation {
        var retained: Relation?
        for positive in [false, true] {
            let (curve, plane) = try input(positive)
            let result = try query(curve, plane, .init(lower: 0, upper: 1)); let r = try owner(result)
            try require(result.points.count == 2 && r.phaseOrdinals.count == 2 && r.imageDimension == 0 && r.fiberDimension == 0)
            try require(result.points[0].curveParameter == 0 && abs(result.points[1].curveParameter - 0.5) < 0x1p-50)
            for p in result.points { try require(p.point.x == 0 && p.surfaceU == p.point.z && p.surfaceV == -p.point.y) }
            try require(positive ? result.points.allSatisfy { $0.point.y > 0 } : result.points.allSatisfy { $0.point.y < 0 })
            try require(DefaultCurveSurfaceIntersector().intersections(curve: curve, surface: plane,
                options: .init(curveRange: try .init(lower: 0, upper: 1)), tolerance: .standard).count == 2)
            try require(owner(query(curve, plane, .init(lower: 0, upper: 0))).phaseOrdinals.count == 1)
            try require(owner(query(curve, plane, .init(lower: 1, upper: 1))).isEmpty)
            try require(owner(query(curve, plane, .init(lower: 0.5, upper: 0.5))).isEmpty)
            try require(owner(query(curve, plane, .init(lower: 0.125, upper: 0.375))).isEmpty)
            try require(owner(query(curve, plane, nil, u: .init(lower: 0, upper: 0.25))).isEmpty)
            try require(owner(query(curve, plane, nil, u: .init(lower: 3, upper: 4))).phaseOrdinals.count == 1)
            var a = try ledger(); let q = ExactRationalScalarDomain(); let f = r.source.original.phaseField
            var huge = try q.integer(1, using: &a)
            for _ in 0..<5 { huge = try q.multiplying(huge, q.integer(UInt64(1) << 32, using: &a), using: &a) }
            let cp = try OriginalParameterCycle(exact: huge, using: &a)
            let cn = try OriginalParameterCycle(exact: q.negated(huge, using: &a), using: &a)
            let b = try f.binary64(exactly: 2 * Double.pi, using: &a)
            let half = try f.dividing(b, f.integer(2, using: &a), using: &a)
            // Original integer data is imported exactly; no finite cycle window.
            var scalar = try f.integer(1, using: &a)
            for _ in 0..<5 { scalar = try f.multiplying(scalar, f.integer(UInt64(1) << 32, using: &a), using: &a) }
            let lift = try f.multiplying(b, scalar, using: &a)
            for ordinal in 0..<2 {
                let uv = try r.parentUV(phaseOrdinal: ordinal, referenceCycle: cp, parameterizedCycle: cn, limits: limits(), using: &a)
                let er = try f.adding(positive ? f.integer(0, using: &a) : half, lift, using: &a)
                let ep = try f.subtracting(ordinal == 0 ? f.integer(0, using: &a) : half, lift, using: &a)
                try require(f.compare(uv.referenceU, er, using: &a) == .equal && f.compare(uv.parameterizedU, ep, using: &a) == .equal)
                let rv = try uv.referenceV.bounds(limits: limits().source, tolerance: .standard, using: &a)
                let pv = try uv.parameterizedV.bounds(limits: limits().source, tolerance: .standard, using: &a)
                try require(rv.lower > 0 && (positive ? pv.lower > 0 : pv.upper < 0))
                try require(uv.referenceV.source.original.original == r.source.original.original && uv.referenceV.phaseOrdinal == ordinal)
            }
            try rejects { _ = try r.source.original.referenceField.importing(r.source.original.parameterizedSine, using: &a) }
            retained = r
        }
        guard let retained else { throw Failure(line: #line) }; return retained
    }
    static func prepared(_ r: Relation) throws {
        var a = try ledger(); let f = r.source.original.phaseField
        let first = r.source.original.parameters[0], last = r.source.original.parameters[1]
        let single = try ExactParameterInterval.checked(field: f, lower: .finite(last), upper: .finite(last), depth: r.proofDepth, using: &a)
        let selected = try Relation.resolve(source: r.source, target: r.target, curveIntervals: [[single]], planeRanges: [nil,nil], maximumPoints: 2, limits: limits(), tolerance: .standard, using: &a)
        try require(selected.phaseOrdinals.count == 1 && selected.phaseOrdinals[0] == 1)
        let open = try ExactParameterInterval.checked(field: f, lower: .finite(first), upper: .finite(last), includesLower: false, includesUpper: false, depth: r.proofDepth, using: &a)
        let empty = try Relation.resolve(source: r.source, target: r.target, curveIntervals: [[open]], planeRanges: [nil,nil], maximumPoints: 2, limits: limits(), tolerance: .standard, using: &a)
        try require(empty.isEmpty)
        for control in 0..<4 {
            let l = try limits(source: control == 0 ? 0 : 1, families: control == 1 ? 1 : 2, charts: control == 2 ? 0 : 1, transport: control == 3 ? 0 : 1)
            try rejects { try r.admitProof(limits: l, using: &a) }
        }
        let other = Surface3D.plane(.init(origin: .origin, normal: .unitY, uDirection: .unitX))
        let foreignTarget = try DefaultOriginalSourceBindingIssuer(provider: OriginalCertifiedCoaxialTargetSnapshotProvider(tolerance: .standard))
            .bind(other, limits: limits().source, using: &a)
        try rejects { _ = try Relation.resolve(source: r.source, target: foreignTarget, curveIntervals: [[single]],
            planeRanges: [nil,nil], maximumPoints: 2, limits: limits(), tolerance: .standard, using: &a) }
        try rejects { _ = try Relation.resolve(source: r.source, target: r.target, curveIntervals: [[single]],
            planeRanges: [nil,nil], maximumPoints: 0, limits: limits(), tolerance: .standard, using: &a) }
        a.cancel(); try rejects { try r.admitProof(limits: limits(), using: &a) }
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
        sourceDepth: Int = 1, scalarDepth: Int = 32) throws -> CurveSurfaceIntersectionResult {
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
        let counts = measured.totals; logCount("cone-cone work", counts.work); logCount("cone-cone bytes", counts.bytes)
        _ = try admitted(curve, plane, request: request, counter: Counter(work: counts.work, bytes: counts.bytes))
        try rejects { _ = try admitted(curve, plane, request: request, counter: Counter(work: counts.work - 1, bytes: counts.bytes)) }
        try rejects { _ = try admitted(curve, plane, request: request, counter: Counter(work: counts.work, bytes: counts.bytes - 1)) }
        for at in [1, counts.work / 2, counts.work] {
            try rejects { _ = try admitted(curve, plane, request: request, counter: Counter(cancelAt: at)) }
        }
        try rejects { _ = try admitted(curve, plane, request: request, counter: Counter(), sourceDepth: 0) }
        try rejects { _ = try admitted(curve, plane, request: request, counter: Counter(), scalarDepth: 0) }
        let empty = try ScalarInterval(lower: 0.125, upper: 0.375)
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
                let request = try ScalarInterval(lower: empty ? 0.125 : 0, upper: empty ? 0.375 : 1)
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
        let r = try success(); try prepared(r); try resources(); try await publicationCancellation()
        var a = try ledger(); try r.admitProof(limits: limits(), using: &a)
        print("PASS original cone-cone full branches, complete T/parentUV, requests and detached lifetime")
    }
}
