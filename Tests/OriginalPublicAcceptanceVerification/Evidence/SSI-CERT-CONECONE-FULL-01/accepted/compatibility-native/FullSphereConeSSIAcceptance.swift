import CADCore
import CADGeometry
import Synchronization
#if canImport(Darwin)
import Darwin
#else
import WASILibc
#endif

@main struct FullSphereConeSSIAcceptance {
    typealias Relation = OriginalFullSphereConeSurfaceRelation
    struct Failure: Error { let line: Int }
    static func require(_ value: Bool, line: Int = #line) throws { guard value else { throw Failure(line: line) } }
    static func rejects(_ body: () throws -> Void) throws {
        do { try body() } catch let e as Failure { throw e } catch { return }; throw Failure(line: #line)
    }
    static func input(_ reversed: Bool = false) -> (Surface3D, Surface3D) {
        let sphere = Surface3D.analytic(.sphere(center: .origin, radius: 3))
        let cone = Surface3D.analytic(.cone(apex: .init(x: 1, y: 0, z: -4), axis: .unitZ,
            halfAngle: Double(bitPattern: 0x3fddac670561bb50)))
        return reversed ? (cone, sphere) : (sphere, cone)
    }
    static func ledger(work: Int = 8_388_608, bytes: Int = 268_435_456, value: Int = 32, coefficient: Int = 32)
        throws -> ExactScalarLedger {
        .init(limits: try .init(work: work, storageBytes: bytes, valueDepth: value, coefficientDepth: coefficient))
    }
    static func limits(source: Int = 1, transport: Int = 1, charts: Int = 4, families: Int = 2) throws -> OriginalDomainIdentityLimits {
        try .init(source: .init(remainingSourceDepth: source), maximumTransportDepth: transport,
            maximumCharts: charts, maximumFamilies: families, maximumIdentityProofs: 0)
    }
    static func owner(_ result: SurfaceSurfaceIntersectionResult) throws -> Relation {
        guard let reader = result.originalFullSphereConeRelation else { throw Failure(line: #line) }
        try require(result.representation == .exactRelation)
        try require(reader.isEmpty == reader.original.isEmpty && reader.hasPositiveDimensionalSolutions == !reader.isEmpty)
        return reader.original
    }
    static func whole(_ reversed: Bool = false) throws -> Relation {
        let (first, second) = input(reversed)
        let result = try DefaultSurfaceSurfaceIntersector().intersectionResult(first: first, second: second, tolerance: .standard)
        let relation = try owner(result)
        try require(!relation.isEmpty && result.intersections.count == 2 && relation.branchCount == 2)
        try require(relation.originalParameterDimension == 4 && relation.imageDimension == 1 && relation.fiberDimension == 0)
        guard case .originalFullSphereCone(let component) = result.intersections[0] else { throw Failure(line: #line) }
        try require(component.isClosed && component.relation === relation && component.branch == 0)
        guard case .originalFullSphereCone(let secondComponent) = result.intersections[1] else { throw Failure(line: #line) }
        try require(secondComponent.isClosed && secondComponent.relation === relation && secondComponent.branch == 1)
        try require(component != secondComponent)
        try require(component.firstSurface == first && component.secondSurface == second)
        return relation
    }
    static func success(selected: Int? = nil) throws {
        for reversed in [false, true] {
            let relation = try whole(reversed), source = relation.source.original
            var make = try ledger(); let q = ExactRationalScalarDomain()
            var huge = try q.integer(1, using: &make)
            for _ in 0..<5 { huge = try q.multiplying(huge, q.integer(UInt64(1) << 32, using: &make), using: &make) }
            let positive = try OriginalParameterCycle(exact: huge, using: &make)
            let negative = try OriginalParameterCycle(exact: q.negated(huge, using: &make), using: &make)
            for chart in 0..<2 where selected == nil || selected == (reversed ? 2 : 0) + chart {
                for parameter in [-1, 0, 1] {
                    var a = try ledger()
                    let t = try source.field.integer(parameter, using: &a)
                    let section = try relation.section(chart: chart, halfAngle: t, limits: limits(), using: &a)
                    for branch in 0..<2 {
                        var reader = try ledger()
                        let point = try section.member(branch: branch, coneCycle: positive, sphereCycle: negative, limits: limits(), using: &reader)
                        let f = point.field, two = try f.integer(2, using: &reader)
                        let s = try f.importing(source.sine, using: &reader), c = try f.importing(source.cosine, using: &reader)
                        let b = try f.adding(f.multiplying(s, section.sine, using: &reader), f.multiplying(f.integer(4, using: &reader), c, using: &reader), using: &reader)
                        let polynomial = try f.adding(f.subtracting(f.multiplying(point.slant, point.slant, using: &reader),
                            f.multiplying(f.multiplying(two, b, using: &reader), point.slant, using: &reader), using: &reader), f.integer(8, using: &reader), using: &reader)
                        try require(f.sign(of: polynomial, using: &reader) == .zero)
                        try require(f.compare(f.adding(point.x, f.multiplying(f.multiplying(s, point.slant, using: &reader), section.sine, using: &reader), using: &reader), f.integer(1, using: &reader), using: &reader) == .equal)
                        try require(f.compare(point.y, f.multiplying(f.multiplying(s, point.slant, using: &reader), section.cosine, using: &reader), using: &reader) == .equal)
                        try require(f.compare(f.subtracting(point.z, f.multiplying(c, point.slant, using: &reader), using: &reader), f.integer(-4, using: &reader), using: &reader) == .equal)
                        try require(f.sign(of: point.slant, using: &reader) == .positive)
                        let first = try point.firstUV(limits: limits(), using: &reader), second = try point.secondUV(limits: limits(), using: &reader)
                        try require(first.isSphere == !reversed && second.isSphere == reversed)
                        let sphere = reversed ? second : first, cone = reversed ? first : second
                        guard case .sphereAzimuthLabel(let ys, let yc, _, let so) = sphere.u,
                            case .sphereLatitudeLabel(let latitude, _) = sphere.v,
                            case .coneAngularLabel(let half, _, let co) = cone.u,
                            case .authoredScalar(let slant) = cone.v else { throw Failure(line: #line) }
                        try require(f.compare(ys, f.negated(point.x, using: &reader), using: &reader) == .equal)
                        try require(f.compare(yc, point.y, using: &reader) == .equal)
                        try require(f.compare(f.multiplying(f.integer(3, using: &reader), latitude, using: &reader), point.z, using: &reader) == .equal)
                        try require(f.compare(half, section.halfAngle, using: &reader) == .equal && f.compare(slant, point.slant, using: &reader) == .equal)
                        try require(f.sign(of: so, using: &reader) == .negative && f.sign(of: co, using: &reader) == .positive)
                        try require(sphere.member.section.relation === relation)
                    }
                    try require(section.field.compare(section.plusSlant, section.minusSlant, using: &a) == .greater)
                }
            }
        }
        print("PASS both full parents, all charts/root branches, exact positions and independent huge UV cycles")
    }
    static func endpoints() throws {
        let relation = try whole(), source = relation.source.original
        var make = try ledger(); let zero = try OriginalParameterCycle(exact: ExactRationalScalarDomain().integer(0, using: &make), using: &make)
        for parameter in [-1, 1] {
            var a = try ledger()
            let section = try relation.section(chart: 0, halfAngle: source.field.integer(parameter, using: &a), limits: limits(), using: &a)
            let other = try section.otherIncident(limits: limits(), using: &a)
            try require(other.chart == 1)
            let f = section.field
            try require(f.compare(other.halfAngle, f.integer(-parameter, using: &a), using: &a) == .equal)
            for branch in 0..<2 {
                let first = try section.member(branch: branch, coneCycle: zero, sphereCycle: zero, limits: limits(), using: &a)
                let second = try other.member(branch: branch, coneCycle: zero, sphereCycle: zero, limits: limits(), using: &a)
                try require(f.compare(first.x, second.x, using: &a) == .equal && f.compare(first.y, second.y, using: &a) == .equal && f.compare(first.z, second.z, using: &a) == .equal)
                try require(f.compare(f.subtracting(second.coneLabelOffset, first.coneLabelOffset, using: &a),
                    f.dividing(f.importing(source.labelPeriod, using: &a), f.integer(2, using: &a), using: &a), using: &a) == .equal)
            }
            let back = try other.otherIncident(limits: limits(), using: &a)
            try require(back.chart == 0 && f.compare(back.halfAngle, section.halfAngle, using: &a) == .equal)
        }
        var a = try ledger(); let t = try source.field.integer(0, using: &a)
        let middle = try relation.section(chart: 0, halfAngle: t, limits: limits(), using: &a)
        try rejects { _ = try middle.otherIncident(limits: limits(), using: &a) }
        try rejects { _ = try relation.section(chart: 2, halfAngle: t, limits: limits(), using: &a) }
        try rejects { _ = try relation.section(chart: 0, halfAngle: source.field.integer(2, using: &a), limits: limits(), using: &a) }
        for index in 0..<4 {
            try rejects { try relation.admitProof(limits: limits(source: index == 0 ? 0 : 1,
                transport: index == 1 ? 0 : 1, charts: index == 2 ? 3 : 4, families: index == 3 ? 1 : 2), using: &a) }
        }
        let other = try whole(true)
        try rejects { _ = try Relation.resolve(source: other.source, firstBox: nil, secondBox: nil, maximumComponents: 2, limits: limits(), prepared: relation, using: &a) }
        var foreign = try ledger(); let physical = try OriginalPhysicalAngleScalarDomain(originalRadians: 0.7, using: &foreign)
        let field = try Relation.Field.base(field: physical, maximumExtensionLevel: 32, using: &foreign)
        let value = try field.integer(0, using: &foreign)
        try rejects { _ = try relation.section(chart: 0, halfAngle: value, limits: limits(), using: &a) }
        var cancelled = try ledger(); cancelled.cancel()
        try rejects { _ = try relation.section(chart: 0, halfAngle: t, limits: limits(), using: &cancelled) }
        print("PASS paired seam incidents reuse exact roots, complete chart support and foreign/limit/cancel refusal")
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
        let (first, second) = input(reversed); let i = try ScalarInterval(lower: 0.25, upper: 0.75)
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
            try require(values.count == 2); return nil
        }
        return try solver.intersectionResult(first: first, second: second, options: .init(), tolerance: .standard,
            maximumSpanCount: 262_144, maximumSubdivisionDepth: 8, remainingSourceDepth: sourceDepth,
            consumeWork: { try counter.consume() }, consumeStorage: { try counter.retain($0) }, maximumAlgebraicDepth: scalarDepth)
    }
    static func publication() throws {
        for reversed in [false, true] {
            let (first, second) = input(reversed)
            try require(DefaultSurfaceSurfaceIntersector().intersections(first: first, second: second, tolerance: .standard).count == 2)
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
            maximumComponents: 1, limits: limits(), using: &a) }
        print("PASS all six SSI entries, full/quarter-empty N-N1 resources, depth and cancellation")
    }
    static func prepared() throws {
        for reversed in [false, true] {
            let (first, second) = input(reversed), counter = Counter()
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
#if hasFeature(Embedded)
        if group.hasPrefix("bounded-") {
            switch group {
            case "bounded-success": try BoundedSphereConeSSIAcceptance.success()
            case "bounded-endpoints": try BoundedSphereConeSSIAcceptance.endpoints()
            case "bounded-publication": try BoundedSphereConeSSIAcceptance.publication()
            case "bounded-prepared": try BoundedSphereConeSSIAcceptance.prepared()
            case "bounded-terminal": try await BoundedSphereConeSSIAcceptance.terminalCancel()
            default: throw Failure(line: #line)
            }
            print("PASS shared source section bounded regression")
            return
        }
#endif
        try require(["all", "success", "success-0", "success-1", "success-2", "success-3", "endpoints", "publication", "prepared", "terminal"].contains(group))
        if group == "all" || group == "success" { try success() }
        for index in 0..<4 where group == "success-" + String(index) { try success(selected: index) }
        if group == "all" || group == "endpoints" { try endpoints() }
        if group == "all" || group == "publication" { try publication() }
        if group == "all" || group == "prepared" { try prepared() }
        if group == "all" || group == "terminal" { try await terminalCancel() }
        print("PASS full sphere-cone original parent SSI verification group")
    }
}
