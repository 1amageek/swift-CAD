import CADCore
import CADGeometry
import Synchronization
#if canImport(Darwin)
import Darwin
#else
import WASILibc
#endif

@main struct CertifiedSphereConeBoundedAcceptance {
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
        let angle = Double(bitPattern: 0x3fddac670561bb50)
        let sphere = Surface3D.analytic(.sphere(center: .origin, radius: 2))
        let cone = Surface3D.analytic(.cone(apex: .init(x: 2, y: 0, z: -4), axis: .unitZ, halfAngle: angle))
        // Producer-selected numeric hints identify the exact critical arc.
        let source = try CertifiedSphereConeIntersectionCurve(sphereSurface: sphere, coneSurface: cone,
            componentKind: .boundedAngularInterval, lowerAngle: Double(bitPattern: 4602529519994401816),
            upperAngle: Double(bitPattern: 4613149419042483861), tolerance: .standard)
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
        for positive in [false] {
            let (curve, plane) = try input(positive)
            let result = try query(curve, plane, .init(lower: 0, upper: 1))
            let relation = try owner(result)
            try require(result.points.count == 2 && relation.phaseOrdinals.count == 2)
            try require(relation.imageDimension == 0 && relation.fiberDimension == 0)
            for (index, point) in result.points.enumerated() {
                try require(abs(point.curveParameter - (index == 0 ? 0.25 : 0.75)) < 0x1p-50)
                try require(point.point.y == 0 && point.surfaceU == point.point.x && point.surfaceV == -point.point.z)
                try require(abs(point.point.x * point.point.x + point.point.z * point.point.z - 4) < 1e-10)
            }
            try require(result.points[0].point.x < 0 && result.points[1].point.x > 0)
            try require(relation.source.original.boundedArc != nil)
            try require(DefaultCurveSurfaceIntersector().intersections(curve: curve, surface: plane,
                options: .init(curveRange: try .init(lower: 0, upper: 1)), tolerance: .standard).count == 2)
            try require(owner(query(curve, plane, .init(lower: 0, upper: 0.125))).isEmpty)
            // Migrated bounded traversal has exact quarter preimages.
            try require(owner(query(curve, plane, .init(lower: 0.25, upper: 0.25))).phaseOrdinals.count == 1)
            try require(owner(query(curve, plane, .init(lower: 0.25.nextUp, upper: 0.75.nextDown))).isEmpty)
            try require(owner(query(curve, plane, .init(lower: 0, upper: 0))).isEmpty)
            try require(owner(query(curve, plane, .init(lower: 1, upper: 1))).isEmpty)
            for root in relation.source.original.roots {
                var a = try ledger(); let f = root.field
                // Independent original pair equations, evaluated in a factorized order.
                // Together with s*s+c*c=1 they imply x*x+z*z=4 without
                // materializing an almost-zero intermediate lambda coefficient.
                let physical = relation.source.original.physical
                let si = try f.importingBase(physical.sine(using: &a), using: &a)
                let co = try f.importingBase(physical.cosine(using: &a), using: &a)
                let b = try f.adding(f.multiplying(f.integer(2, using: &a), si, using: &a),
                    f.multiplying(f.integer(4, using: &a), co, using: &a), using: &a)
                let quadratic = try f.adding(f.subtracting(f.multiplying(root.slant, root.slant, using: &a),
                    f.multiplying(f.multiplying(f.integer(2, using: &a), b, using: &a), root.slant, using: &a), using: &a),
                    f.integer(16, using: &a), using: &a)
                try require(f.sign(of: quadratic, using: &a) == .zero)
                try require(f.compare(f.adding(root.x, f.multiplying(si, root.slant, using: &a), using: &a),
                    f.integer(2, using: &a), using: &a) == .equal)
                try require(f.compare(f.subtracting(root.z, f.multiplying(co, root.slant, using: &a), using: &a),
                    f.integer(-4, using: &a), using: &a) == .equal)
                let q = ExactRationalScalarDomain()
                var huge = try q.integer(1, using: &a)
                for _ in 0..<5 { huge = try q.multiplying(huge, q.integer(UInt64(1) << 32, using: &a), using: &a) }
                let cp = try OriginalParameterCycle(exact: huge, using: &a)
                let cn = try OriginalParameterCycle(exact: q.negated(huge, using: &a), using: &a)
                let uv = try relation.parentUV(phaseOrdinal: root.phaseOrdinal, coneCycle: cp, sphereCycle: cn,
                    limits: limits(), using: &a)
                try require(f.compare(uv.cone[1], root.slant, using: &a) == .equal)
                let radius = try f.integer(2, using: &a)
                try require(f.compare(f.multiplying(uv.sphereV.sine, radius, using: &a), root.z, using: &a) == .equal)
                let absoluteX = root.phaseOrdinal == 0 ? try f.negated(root.x, using: &a) : root.x
                try require(f.compare(f.multiplying(uv.sphereV.cosine, radius, using: &a), absoluteX, using: &a) == .equal)
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
        // Both signs retain the same original radical/field owner.
        let shared = try roots[1].field.importing(roots[0].x, using: &a)
        try require(roots[1].field.compare(shared, roots[0].x, using: &a) == .equal)
        let foreignPhysical = try OriginalPhysicalAngleScalarDomain(originalRadians: 0.7, using: &a)
        let foreign = try OriginalCertifiedSphereConePlaneRoot.Field.base(field: foreignPhysical,
            maximumExtensionLevel: 32, using: &a)
        try rejects { _ = try foreign.importing(roots[0].x, using: &a) }
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
    static func resources(group: Int? = nil) throws {
        let (curve, plane) = try input(false); let request = try ScalarInterval(lower: 0, upper: 1)
        let measured = Counter(); _ = try admitted(curve, plane, request: request, counter: measured)
        let counts = measured.totals; logCount("sphere-cone work", counts.work); logCount("sphere-cone bytes", counts.bytes)
        if group == nil || group == 0 {
        let bareCounter = Counter(work: counts.work, bytes: counts.bytes)
        let bare = try DefaultCurveSurfaceIntersector().intersections(curve: curve, surface: plane,
            options: .init(curveRange: request), tolerance: .standard, maximumSpanCount: 262_144,
            maximumSubdivisionDepth: 8, remainingSourceDepth: 1,
            consumeWork: { try bareCounter.consume($0) }, consumeStorage: { try bareCounter.retain($0) },
            maximumAlgebraicDepth: 32)
        try require(bare.count == 2)
        for (index, point) in bare.enumerated() {
            try require(point.curveParameter == (index == 0 ? 0.25 : 0.75))
            try require(point.point.y == 0 && point.surfaceU == point.point.x && point.surfaceV == -point.point.z)
            try require(abs(point.point.x * point.point.x + point.point.z * point.point.z - 4) < 1e-10)
            try require(index == 0 ? point.point.x < 0 : point.point.x > 0)
        }
        try require(bareCounter.totals.work == counts.work && bareCounter.totals.bytes == counts.bytes)
        print("PASS callback bare complete two contacts, exact quarter T, target UV and same admission")
        }
        if group == nil || group == 1 {
        _ = try admitted(curve, plane, request: request, counter: Counter(work: counts.work, bytes: counts.bytes))
        }
        if group == nil || group == 2 {
        try rejects { _ = try admitted(curve, plane, request: request, counter: Counter(work: counts.work - 1, bytes: counts.bytes)) }
        }
        if group == nil || group == 3 {
        try rejects { _ = try admitted(curve, plane, request: request, counter: Counter(work: counts.work, bytes: counts.bytes - 1)) }
        }
        for (index, at) in [1, counts.work / 2, counts.work].enumerated() where group == nil || group == index + 4 {
            try rejects { _ = try admitted(curve, plane, request: request, counter: Counter(cancelAt: at)) }
        }
        if group == nil || group == 7 {
        try rejects { _ = try admitted(curve, plane, request: request, counter: Counter(), sourceDepth: 0) }
        try rejects { _ = try admitted(curve, plane, request: request, counter: Counter(), scalarDepth: 0) }
        }
        if group == nil || group == 8 {
        let empty = try ScalarInterval(lower: 0, upper: 0.125)
        let emptyMeasured = Counter(); let emptyResult = try admitted(curve, plane, request: empty, counter: emptyMeasured)
        try require(owner(emptyResult).isEmpty)
        let ec = emptyMeasured.totals
        _ = try admitted(curve, plane, request: empty, counter: Counter(work: ec.work, bytes: ec.bytes))
        try rejects { _ = try admitted(curve, plane, request: empty, counter: Counter(work: ec.work - 1, bytes: ec.bytes)) }
        try rejects { _ = try admitted(curve, plane, request: empty, counter: Counter(work: ec.work, bytes: ec.bytes - 1)) }
        }
        print("PASS original caller N/N-1 work/storage for full and empty, depth and cancellation")
    }
    static func publicationCancellation(selected: Bool? = nil) async throws {
        for empty in [false, true] where selected == nil || selected == empty {
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
        if CommandLine.arguments.count > 1 {
            let group = CommandLine.arguments[1]
            if group == "success" {
                try rationalBounds(); let relation = try success(); try prepared(relation)
                var a = try ledger(); try relation.admitProof(limits: limits(), using: &a)
            } else if group == "publication-full" || group == "publication-empty" {
                try await publicationCancellation(selected: group == "publication-empty")
            } else if let index = Int(group), (0...8).contains(index) {
                try resources(group: index)
            } else { throw Failure(line: #line) }
            print("PASS bounded independent verification group")
            return
        }
        try rationalBounds(); let relation = try success(); try prepared(relation); try resources()
        try await publicationCancellation()
        var a = try ledger(); try relation.admitProof(limits: limits(), using: &a)
        print("PASS original sphere-cone bounded branch, complete T/radical/parentUV, requests and detached lifetime")
    }
}
