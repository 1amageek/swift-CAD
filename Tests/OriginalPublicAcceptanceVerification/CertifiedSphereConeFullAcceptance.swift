import CADCore
import CADGeometry
import Synchronization
#if canImport(Darwin)
import Darwin
#else
import WASILibc
#endif

@main struct CertifiedSphereConeFullAcceptance {
    typealias Relation = OriginalCertifiedSphereConePlaneRelation
    struct Failure: Error { let line: Int }
    static func require(_ value: Bool, line: Int = #line) throws { guard value else { throw Failure(line: line) } }
    static func rejects(_ body: () throws -> Void) throws {
        do { try body() } catch let error as Failure { throw error } catch { return }
        throw Failure(line: #line)
    }
    static func ledger(work: Int = 8_388_608, bytes: Int = 268_435_456,
        value: Int = 32, coefficient: Int = 32) throws -> ExactScalarLedger {
        .init(limits: try .init(work: work, storageBytes: bytes, valueDepth: value, coefficientDepth: coefficient))
    }
    static func limits(source: Int = 1, families: Int = 2, charts: Int = 2, transport: Int = 1)
        throws -> OriginalDomainIdentityLimits {
        try .init(source: .init(remainingSourceDepth: source), maximumTransportDepth: transport,
            maximumCharts: charts, maximumFamilies: families, maximumIdentityProofs: 0)
    }
    static func input(_ positive: Bool) throws -> (Curve3D, Surface3D) {
        // The stored bits are the original authored angle, independent of libm.
        let angle = Double(bitPattern: 0x3fddac670561bb50)
        let sphere = Surface3D.analytic(.sphere(center: .origin, radius: 3))
        let cone = Surface3D.analytic(.cone(apex: .init(x: 1, y: 0, z: -4), axis: .unitZ, halfAngle: angle))
        let source = try CertifiedSphereConeIntersectionCurve(sphereSurface: sphere, coneSurface: cone,
            componentKind: positive ? .positiveFullBranch : .negativeFullBranch,
            lowerAngle: 0, upperAngle: 2 * Double.pi, tolerance: .standard)
        return (.certifiedIntersection(.sphereCone(source)), .plane(.init(origin: .origin, normal: .unitY, uDirection: .unitX)))
    }
    static func query(_ curve: Curve3D, _ plane: Surface3D,
        _ request: ScalarInterval? = nil) throws -> CurveSurfaceIntersectionResult {
        try DefaultCurveSurfaceIntersector().intersectionResult(curve: curve, surface: plane,
            options: .init(curveRange: request), tolerance: .standard)
    }
    static func owner(_ result: CurveSurfaceIntersectionResult) throws -> Relation {
        guard let reader = result.originalCertifiedSphereConeRelation else { throw Failure(line: #line) }
        try require(reader.isEmpty == reader.original.isEmpty && !reader.hasPositiveDimensionalSolutions)
        return reader.original
    }
    static func success() throws -> Relation {
        var retained: Relation?
        for positive in [false, true] {
            let (curve, plane) = try input(positive)
            let result = try query(curve, plane, .init(lower: 0, upper: 1))
            let relation = try owner(result)
            try require(result.points.count == 2 && relation.phaseOrdinals.count == 2)
            try require(relation.imageDimension == 0 && relation.fiberDimension == 0)
            for (index, point) in result.points.enumerated() {
                try require(abs(point.curveParameter - (index == 0 ? 0.25 : 0.75)) < 0x1p-50)
                try require(point.point.y == 0 && point.surfaceU == point.point.x && point.surfaceV == -point.point.z)
                try require(abs(point.point.x * point.point.x + point.point.z * point.point.z - 9) < 1e-10)
            }
            try require(positive ? result.points[0].point.x < -2 : result.points[0].point.x > 0.4)
            try require(positive ? result.points[1].point.x > 2.9 : result.points[1].point.x > 1.7)
            try require(DefaultCurveSurfaceIntersector().intersections(curve: curve, surface: plane,
                options: .init(curveRange: try .init(lower: 0, upper: 1)), tolerance: .standard).count == 2)
            try require(owner(query(curve, plane, .init(lower: 0, upper: 0.125))).isEmpty)
            // Mathematical pi exceeds the stored binary pi: these are not exact roots.
            try require(owner(query(curve, plane, .init(lower: 0.25, upper: 0.25))).isEmpty)
            try require(owner(query(curve, plane, .init(lower: 0, upper: 0))).isEmpty)
            try require(owner(query(curve, plane, .init(lower: 1, upper: 1))).isEmpty)
            for root in relation.source.original.roots {
                var a = try ledger(); let f = root.field
                let sphereIdentity = try f.adding(f.multiplying(root.x, root.x, using: &a),
                    f.multiplying(root.z, root.z, using: &a), using: &a)
                try require(f.compare(sphereIdentity, f.integer(9, using: &a), using: &a) == .equal)
                let q = ExactRationalScalarDomain()
                var huge = try q.integer(1, using: &a)
                for _ in 0..<5 { huge = try q.multiplying(huge, q.integer(UInt64(1) << 32, using: &a), using: &a) }
                let cp = try OriginalParameterCycle(exact: huge, using: &a)
                let cn = try OriginalParameterCycle(exact: q.negated(huge, using: &a), using: &a)
                let uv = try relation.parentUV(phaseOrdinal: root.phaseOrdinal, coneCycle: cp, sphereCycle: cn,
                    limits: limits(), using: &a)
                try require(f.compare(uv.cone[1], root.slant, using: &a) == .equal)
                let unit = try f.adding(f.multiplying(uv.sphereV.sine, uv.sphereV.sine, using: &a),
                    f.multiplying(uv.sphereV.cosine, uv.sphereV.cosine, using: &a), using: &a)
                try require(f.compare(unit, f.integer(1, using: &a), using: &a) == .equal)
                try require(uv.sphereV.source.original.original == relation.source.original.original)
                try require(uv.sphereV.phaseOrdinal == root.phaseOrdinal)
            }
            retained = relation
        }
        guard let retained else { throw Failure(line: #line) }; return retained
    }
    static func prepared(_ relation: Relation) throws {
        var a = try ledger(); let phase = relation.source.original.phase.law.field
        let t = relation.source.original.phase.roots[0].parameter
        let interval = try ExactParameterInterval.checked(field: phase, lower: .finite(t), upper: .finite(t),
            depth: relation.source.original.phase.proofDepth, using: &a)
        let single = try Relation.resolve(source: relation.source, target: relation.target,
            curveIntervals: [[interval]], planeRanges: [nil, nil], maximumPoints: 2, limits: limits(), using: &a)
        try require(single.phaseOrdinals.count == 1 && single.phaseOrdinals[0] == 0)
        let end = relation.source.original.phase.roots[1].parameter
        let open = try ExactParameterInterval.checked(field: phase, lower: .finite(t), upper: .finite(end),
            includesLower: false, includesUpper: false, depth: relation.source.original.phase.proofDepth, using: &a)
        let empty = try Relation.resolve(source: relation.source, target: relation.target,
            curveIntervals: [[open]], planeRanges: [nil, nil], maximumPoints: 2, limits: limits(), using: &a)
        try require(empty.isEmpty)
        let roots = relation.source.original.roots
        try rejects { _ = try roots[1].field.importing(roots[0].x, using: &a) }
        for control in 0..<4 {
            let limited = try limits(source: control == 0 ? 0 : 1, families: control == 1 ? 1 : 2,
                charts: control == 2 ? 0 : 2, transport: control == 3 ? 0 : 1)
            try rejects { try relation.admitProof(limits: limited, using: &a) }
        }
        a.cancel(); try rejects { try relation.admitProof(limits: limits(), using: &a) }
    }
    static func rationalBounds() throws {
        var a = try ledger(); let q = ExactRationalScalarDomain()
        for sign in [-1, 0, 1] {
            let value = try q.dividing(q.integer(sign, using: &a), q.integer(3, using: &a), using: &a)
            let b = try q.dyadicNeighbours(value, fractionalBits: 160, using: &a)
            try require(q.compare(b.lower, value, using: &a) != .greater)
            try require(q.compare(value, b.upper, using: &a) != .greater)
        }
        let exact = try q.binary64(exactly: -0.25, using: &a)
        let b = try q.dyadicNeighbours(exact, fractionalBits: 2, using: &a)
        try require(q.compare(b.lower, exact, using: &a) == .equal && q.compare(b.upper, exact, using: &a) == .equal)
        try rejects { _ = try q.dyadicNeighbours(exact, fractionalBits: -1, using: &a) }
        var limited = try ledger(bytes: 0)
        try rejects { _ = try q.dyadicNeighbours(exact, fractionalBits: Int.max, using: &limited) }
        print("PASS exact signed dyadic neighbours without rounded coefficients")
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
        let counts = measured.totals; logCount("sphere-cone work", counts.work); logCount("sphere-cone bytes", counts.bytes)
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
        try rationalBounds(); let relation = try success(); try prepared(relation); try resources()
        try await publicationCancellation()
        var a = try ledger(); try relation.admitProof(limits: limits(), using: &a)
        print("PASS original sphere-cone full branches, complete T/radical/parentUV, requests and detached lifetime")
    }
}
