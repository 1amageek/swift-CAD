import CADCore
import CADGeometry
import Synchronization
#if canImport(Darwin)
import Darwin
#else
import WASILibc
#endif

@main struct CertifiedCoaxialPublicAcceptance {
    typealias Relation = OriginalCertifiedCoaxialCurveSurfaceRelation
    typealias Base = Relation.Base
    typealias Interval = Relation.Interval
    struct Failure: Error { let line: Int }
    static func require(_ value: Bool, line: Int = #line) throws {
        guard value else { throw Failure(line: line) }
    }
    #if !COAXIAL_ORDINARY_ONLY
    static func ledger(work: Int = 8_388_608, bytes: Int = 268_435_456) throws -> ExactScalarLedger {
        .init(limits: try .init(work: work, storageBytes: bytes, valueDepth: 32, coefficientDepth: 32))
    }
    static func limits(source: Int = 1, charts: Int = 2, families: Int = 2, transport: Int = 1)
        throws -> OriginalDomainIdentityLimits {
        try .init(source: .init(remainingSourceDepth: source), maximumTransportDepth: transport,
            maximumCharts: charts, maximumFamilies: families, maximumIdentityProofs: 0)
    }
    #endif
    static func input(_ positive: Bool) throws -> (Curve3D, Surface3D, Surface3D) {
        let cone = Surface3D.analytic(.cone(apex: .origin, axis: .unitZ, halfAngle: atan(0.5)))
        let cylinder = Surface3D.analytic(.cylinder(origin: .origin, axis: .unitZ, radius: 1))
        let original = try CertifiedConeCylinderIntersectionCurve(coneSurface: cone, cylinderSurface: cylinder,
            componentKind: positive ? .positiveFullBranch : .negativeFullBranch,
            lowerAngle: 0, upperAngle: 2 * Double.pi, tolerance: .standard)
        let plane = Surface3D.plane(.init(origin: .origin, normal: .unitY, uDirection: .unitX))
        return (.certifiedIntersection(.coneCylinder(original)), cylinder, plane)
    }
    #if !COAXIAL_ORDINARY_ONLY
    static func interval(_ lower: Double, _ upper: Double, field: Base,
        closed: Bool = true, using a: inout ExactScalarLedger) throws -> Interval {
        try .checked(field: field, lower: .finite(field.binary64(exactly: lower, using: &a)),
            upper: .finite(field.binary64(exactly: upper, using: &a)), includesLower: closed,
            includesUpper: closed, depth: .init(value: 0, coefficient: 0), using: &a)
    }
    #endif
    static func options(_ lower: Double = 0, _ upper: Double = 1) throws -> CurveSurfaceIntersectionOptions {
        .init(curveRange: try .init(lower: lower, upper: upper))
    }
    static func query(_ curve: Curve3D, _ surface: Surface3D,
        _ options: CurveSurfaceIntersectionOptions) throws -> CurveSurfaceIntersectionResult {
        try DefaultCurveSurfaceIntersector().intersectionResult(curve: curve, surface: surface,
            options: options, tolerance: .standard)
    }
    static func reading(_ result: CurveSurfaceIntersectionResult) throws -> Relation {
        guard let reader = result.originalCertifiedCoaxialRelation else { throw Failure(line: #line) }
        try require(reader.isEmpty == reader.original.isEmpty)
        try require(reader.hasPositiveDimensionalSolutions == reader.original.hasPositiveDimensionalSolutions)
        return reader.original
    }
    static func rejects(_ body: () throws -> Void) throws {
        do { try body() } catch let error as Failure { throw error } catch { return }
        throw Failure(line: #line)
    }

    #if !COAXIAL_ORDINARY_ONLY && !COAXIAL_SELECTION_ONLY
    static func success() throws -> Relation {
        var retained: Relation?
        for positive in [false, true] {
            let (curve, cylinder, plane) = try input(positive)
            let result = try query(curve, plane, options())
            let relation = try reading(result)
            try require(result.points.count == 2 && !result.hasPositiveDimensionalSolutions)
            try require(relation.imageDimension == 0 && relation.fiberDimension == 0)
            try require(result.points[0].curveParameter == 0.25 && result.points[1].curveParameter == 0.75)
            for (index, point) in result.points.enumerated() {
                try require(point.point.x == (index == 0 ? -1 : 1) && point.point.y == 0)
                try require(positive ? point.point.z < 0 : point.point.z > 0)
                try require(abs(point.point.z) > 1.99 && abs(point.point.z) < 2.01)
                try require(point.surfaceU == point.point.x && point.surfaceV == -point.point.z)
            }
            var a = try ledger(); let f = relation.source.original.field, l = try limits()
            let quarter = try relation.source.original.planeRoot(at: 0, using: &a)
            try require(relation.contains(parameter: quarter, u: f.integer(-1, using: &a),
                v: f.negated(relation.source.original.height, using: &a), limits: l, using: &a))
            let q = ExactRationalScalarDomain()
            // 2^160 exceeds every machine integer and keeps independent parent indices.
            var enormous = try q.integer(1, using: &a)
            for _ in 0..<5 { enormous = try q.multiplying(enormous, q.integer(UInt64(1) << 32, using: &a), using: &a) }
            let cp = try OriginalParameterCycle(exact: enormous, using: &a)
            let cn = try OriginalParameterCycle(exact: q.negated(enormous, using: &a), using: &a)
            let parents = try relation.parentUV(parameter: quarter, cylinderCycle: cp, coneCycle: cn, limits: l, using: &a)
            var exactCycle = try f.integer(1, using: &a)
            for _ in 0..<5 { exactCycle = try f.multiplying(exactCycle, f.integer(UInt64(1) << 32, using: &a), using: &a) }
            let period = relation.source.original.labelPeriod
            let expectedCylinder = try f.multiplying(period, f.adding(quarter, exactCycle, using: &a), using: &a)
            var expectedCone = try f.multiplying(period, f.subtracting(quarter, exactCycle, using: &a), using: &a)
            if positive { expectedCone = try f.adding(expectedCone, f.dividing(period, f.integer(2, using: &a), using: &a), using: &a) }
            try require(f.compare(parents[0], expectedCylinder, using: &a) == .equal)
            try require(f.compare(parents[2], expectedCone, using: &a) == .equal)
            let sign = try f.integer(positive ? -1 : 1, using: &a)
            let sine = try f.sine(using: &a), cosine = try f.cosine(using: &a)
            try require(f.compare(f.multiplying(parents[3], sine, using: &a), sign, using: &a) == .equal)
            try require(f.compare(f.multiplying(parents[1], sine, using: &a), f.multiplying(sign, cosine, using: &a), using: &a) == .equal)
            let empty = try reading(query(curve, plane, options(0, 0.125)))
            try require(empty.isEmpty && empty.imageDimension == nil)
            let singleton = try query(curve, plane, options(0.25, 0.25))
            try require(singleton.points.count == 1 && !singleton.hasPositiveDimensionalSolutions)
            try require(DefaultCurveSurfaceIntersector().intersections(curve: curve, surface: plane,
                options: options(), tolerance: .standard).count == 2)
            let continuousResult = try query(curve, cylinder, options())
            let continuous = try reading(continuousResult)
            try require(!continuous.isEmpty && continuousResult.hasPositiveDimensionalSolutions)
            try require(continuous.imageDimension == 1 && continuous.fiberDimension == 0)
            try require(continuousResult.representation == .exactRelation)
            try require(continuousResult.points.isEmpty && continuous.planeParameters.isEmpty)
            var b = try ledger(); let g = continuous.source.original.field
            let zeroCycle = try OriginalParameterCycle(exact: q.integer(0, using: &b), using: &b)
            let oneCycle = try OriginalParameterCycle(exact: q.integer(1, using: &b), using: &b)
            let zero = try g.integer(0, using: &b), one = try g.integer(1, using: &b)
            let end = try continuous.cylinderUV(parameter: one, cycle: zeroCycle, limits: l, using: &b)
            let start = try continuous.cylinderUV(parameter: zero, cycle: oneCycle, limits: l, using: &b)
            try require(g.compare(end[0], start[0], using: &b) == .equal)
            try require(continuous.effective.contains([zero], limits: l, using: &b)
                && continuous.effective.contains([one], limits: l, using: &b))
            _ = try continuous.cylinderUV(parameter: g.dividing(one, g.integer(4, using: &b), using: &b),
                cycle: cp, limits: l, using: &b)
            try rejects { _ = try DefaultCurveSurfaceIntersector().intersections(curve: curve, surface: cylinder,
                options: options(), tolerance: .standard) }
            var axial = try options()
            axial.surfaceVRange = try .init(lower: 1, upper: 3)
            let axialResult = try reading(query(curve, cylinder, axial))
            try require(positive ? axialResult.isEmpty : axialResult.hasPositiveDimensionalSolutions)
            retained = continuous
        }
        guard let retained else { throw Failure(line: #line) }; return retained
    }

    #endif
    #if !COAXIAL_ORDINARY_ONLY && !COAXIAL_RECEIPT_ONLY
    static func selections(_ original: Relation) throws {
        var a = try ledger(); let f = original.source.original.field, l = try limits()
        let whole = try Interval.checked(field: f, lower: .negativeInfinity, upper: .positiveInfinity,
            depth: .init(value: 0, coefficient: 0), using: &a)
        for control in 0..<3 {
            var b = try ledger()
            let t = try interval(control == 2 ? 0.25 : 0, control == 2 ? 0.25 : 0.125,
                field: f, closed: control != 1, using: &b)
            let u = try interval(1, 1, field: f, using: &b)
            let relation = try Relation.resolve(source: original.source, target: original.targetSupport.frame.source,
                curveIntervals: [[t]], targetIntervals: [[u], [whole]], maximumPoints: 2, limits: l, using: &b)
            // U=1 is strictly above B/8 and below B/4.
            try require(relation.isEmpty && !relation.hasPositiveDimensionalSolutions)
        }
        var b = try ledger()
        let period = original.source.original.labelPeriod
        let half = try f.dividing(period, f.integer(2, using: &b), using: &b)
        let u = try Interval.checked(field: f, lower: .finite(half), upper: .finite(half),
            depth: .init(value: 0, coefficient: 0), using: &b)
        let pieces = [try interval(0, 0.125, field: f, using: &b), try interval(0.5, 0.5, field: f, using: &b)]
        let selected = try Relation.resolve(source: original.source, target: original.targetSupport.frame.source,
            curveIntervals: [pieces], targetIntervals: [[u], [whole]], maximumPoints: 2, limits: l, using: &b)
        try require(!selected.isEmpty && !selected.hasPositiveDimensionalSolutions && selected.imageDimension == 0)
        let open = try interval(0, 0.5, field: f, closed: false, using: &b)
        let excluded = try Relation.resolve(source: original.source, target: original.targetSupport.frame.source,
            curveIntervals: [[open]], targetIntervals: [[u], [whole]], maximumPoints: 2, limits: l, using: &b)
        try require(excluded.isEmpty)
        let foreign = try Base(originalRadians: atan(0.5), using: &b)
        try rejects { _ = try selected.contains(parameter: foreign.integer(0, using: &b),
            u: half, v: selected.source.original.height, limits: l, using: &b) }
        for control in 0..<4 {
            let limited = try limits(source: control == 0 ? 0 : 1, charts: control == 1 ? 0 : 2,
                families: control == 2 ? 1 : 2, transport: control == 3 ? 0 : 1)
            try rejects { try selected.admitProof(limits: limited, using: &b) }
        }
    }

    #endif
    #if !COAXIAL_SELECTION_ONLY && !COAXIAL_RECEIPT_ONLY
    final class Counter: Sendable {
        struct State: Sendable { var work = 0; var bytes = 0 }
        private let state = Mutex(State())
        let workLimit: Int; let byteLimit: Int; let cancelAt: Int?; let cancelStorageAt: Int?
        init(work: Int = 8_388_608, bytes: Int = 268_435_456, cancelAt: Int? = nil, cancelStorageAt: Int? = nil) {
            workLimit = work; byteLimit = bytes; self.cancelAt = cancelAt; self.cancelStorageAt = cancelStorageAt
        }
        func consume(_ depth: Int) throws {
            let reached = try state.withLock { s in
                guard s.work < workLimit else { throw ExactScalarFailure.resourceLimit(.work) }
                s.work += 1; return s.work
            }
            if reached == cancelAt { throw CancellationError() }
        }
        func retain(_ bytes: Int) throws {
            let reached = try state.withLock { s in
                let next = s.bytes.addingReportingOverflow(bytes)
                guard bytes >= 0, !next.overflow, next.partialValue <= byteLimit else { throw ExactScalarFailure.resourceLimit(.storage) }
                s.bytes = next.partialValue; return s.bytes
            }
            if reached == cancelStorageAt { withUnsafeCurrentTask { $0?.cancel() } }
        }
        var totals: State { state.withLock { $0 } }
    }
    static func admitted(_ curve: Curve3D, _ target: Surface3D, _ options: CurveSurfaceIntersectionOptions,
        _ counter: Counter, sourceDepth: Int = 1) throws -> CurveSurfaceIntersectionResult {
        try DefaultCurveSurfaceIntersector().intersectionResult(curve: curve, surface: target,
            options: options, tolerance: .standard, maximumSpanCount: 262_144,
            maximumSubdivisionDepth: 8, remainingSourceDepth: sourceDepth,
            consumeWork: { try counter.consume($0) }, consumeStorage: { try counter.retain($0) },
            maximumAlgebraicDepth: 32)
    }
    static func logCount(_ label: StaticString, _ value: Int) {
        print(label, terminator: ": ")
        var divisor = 1
        while divisor <= value / 10 { divisor *= 10 }
        repeat { putchar(Int32(48 + value / divisor % 10)); divisor /= 10 } while divisor > 0
        putchar(10); fflush(nil)
    }
    static func resources() throws {
        let (curve, _, plane) = try input(false), options = try options()
        let counted = Counter(); _ = try admitted(curve, plane, options, counted)
        let totals = counted.totals
        logCount("original coaxial public work", totals.work)
        logCount("original coaxial public bytes", totals.bytes)
        _ = try admitted(curve, plane, options, Counter(work: totals.work, bytes: totals.bytes))
        try rejects { _ = try admitted(curve, plane, options, Counter(work: totals.work - 1, bytes: totals.bytes)) }
        try rejects { _ = try admitted(curve, plane, options, Counter(work: totals.work, bytes: totals.bytes - 1)) }
        for at in [1, totals.work / 2, totals.work] {
            try rejects { _ = try admitted(curve, plane, options, Counter(cancelAt: at)) }
        }
        try rejects { _ = try admitted(curve, plane, options, Counter(), sourceDepth: 0) }
        var limited = options; limited.maximumCandidateCount = 1
        try rejects { _ = try query(curve, plane, limited) }
        print("PASS exact caller work/storage boundary and entry/processing/final-work cancellation")
    }
    static func publicationCancellation() async throws {
        for empty in [false, true] {
            let task = Task {
                let (curve, _, plane) = try input(false)
                let request = try options(0, empty ? 0.125 : 1)
                let counted = Counter(); _ = try admitted(curve, plane, request, counted)
                let counter = Counter(cancelStorageAt: counted.totals.bytes)
                try rejects { _ = try admitted(curve, plane, request, counter) }
                try require(Task<Never, Never>.isCancelled)
            }
            try await task.value
        }
        print("PASS terminal publication cancellation including complete empty result")
    }
    #endif
    #if COAXIAL_ORDINARY_ONLY
    static func ordinarySuccess() throws {
        for positive in [false, true] {
            let (curve, cylinder, plane) = try input(positive)
            let result = try query(curve, plane, options())
            let owner = try reading(result)
            try require(result.points.count == 2 && owner.imageDimension == 0 && owner.fiberDimension == 0)
            try require(result.points[0].curveParameter == 0.25 && result.points[1].curveParameter == 0.75)
            for (i, point) in result.points.enumerated() {
                try require(point.point.x == (i == 0 ? -1 : 1) && point.point.y == 0)
                try require(positive ? point.point.z < 0 : point.point.z > 0)
                try require(abs(point.point.z) > 1.99 && abs(point.point.z) < 2.01)
                try require(point.surfaceU == point.point.x && point.surfaceV == -point.point.z)
            }
            try require(reading(query(curve, plane, options(0, 0.125))).isEmpty)
            try require(query(curve, plane, options(0.25, 0.25)).points.count == 1)
            try require(DefaultCurveSurfaceIntersector().intersections(curve: curve, surface: plane,
                options: options(), tolerance: .standard).count == 2)
            let continuousResult = try query(curve, cylinder, options())
            let continuous = try reading(continuousResult)
            try require(!continuous.isEmpty && continuousResult.hasPositiveDimensionalSolutions)
            try require(continuous.imageDimension == 1 && continuous.fiberDimension == 0)
            try require(continuousResult.representation == .exactRelation && continuousResult.points.isEmpty)
            try rejects { _ = try DefaultCurveSurfaceIntersector().intersections(curve: curve, surface: cylinder,
                options: options(), tolerance: .standard) }
            var axial = try options(); axial.surfaceVRange = try .init(lower: 1, upper: 3)
            let clipped = try reading(query(curve, cylinder, axial))
            try require(positive ? clipped.isEmpty : clipped.hasPositiveDimensionalSolutions)
        }
    }
    #endif
    static func main() async throws {
        #if COAXIAL_ORDINARY_ONLY
        try ordinarySuccess(); try resources(); try await publicationCancellation()
        print("PASS certified coaxial ordinary public roots and complete interval families")
        #elseif COAXIAL_SELECTION_ONLY
        let (curve, cylinder, _) = try input(true)
        try selections(reading(query(curve, cylinder, options())))
        print("PASS certified coaxial prepared open/disconnected/singleton and foreign scopes")
        #else
        let retained = try success()
        #if !COAXIAL_RECEIPT_ONLY
        try selections(retained); try resources()
        #endif
        // All temporary inputs/results have gone out of scope; the relation owns the source.
        var a = try ledger(); try retained.admitProof(limits: limits(), using: &a)
        a.cancel(); try rejects { try retained.admitProof(limits: limits(), using: &a) }
        #if !COAXIAL_RECEIPT_ONLY
        try await publicationCancellation()
        #endif
        print("PASS both certified coaxial public roots, whole continuous family, all UV and lifetime")
        #endif
    }
}
