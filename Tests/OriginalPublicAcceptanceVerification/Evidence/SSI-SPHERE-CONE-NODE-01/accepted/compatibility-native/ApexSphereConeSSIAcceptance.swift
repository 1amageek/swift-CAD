import CADCore
import CADGeometry
import Synchronization
#if canImport(Darwin)
import Darwin
#else
import WASILibc
#endif

@main struct ApexSphereConeSSIAcceptance {
    typealias Relation = OriginalApexSphereConeSurfaceRelation
    struct Failure: Error { let line: Int }
    static func require(_ value: Bool, line: Int = #line) throws { guard value else { throw Failure(line: line) } }
    static func rejects(_ body: () throws -> Void) throws {
        do { try body() } catch let e as Failure { throw e } catch { return }; throw Failure(line: #line)
    }
    static func input(_ reversed: Bool = false) -> (Surface3D, Surface3D) {
        let sphere = Surface3D.analytic(.sphere(center: .origin, radius: 1))
        let cone = Surface3D.analytic(.cone(apex: .init(x: 1, y: 0, z: 0), axis: .unitZ,
            halfAngle: Double(bitPattern: 0x3fddac670561bb50)))
        return reversed ? (cone, sphere) : (sphere, cone)
    }
    static func ledger(work: Int = 8_388_608, bytes: Int = 268_435_456, value: Int = 32, coefficient: Int = 32)
        throws -> ExactScalarLedger {
        .init(limits: try .init(work: work, storageBytes: bytes, valueDepth: value, coefficientDepth: coefficient))
    }
    static func limits(source: Int = 1, transport: Int = 1, charts: Int = 2, families: Int = 3) throws -> OriginalDomainIdentityLimits {
        try .init(source: .init(remainingSourceDepth: source), maximumTransportDepth: transport,
            maximumCharts: charts, maximumFamilies: families, maximumIdentityProofs: 0)
    }
    static func owner(_ result: SurfaceSurfaceIntersectionResult) throws -> Relation {
        guard let reader = result.originalApexSphereConeRelation else { throw Failure(line: #line) }
        try require(result.representation == .exactRelation)
        try require(reader.isEmpty == reader.original.isEmpty && reader.hasPositiveDimensionalSolutions == !reader.isEmpty)
        return reader.original
    }
    static func whole(_ reversed: Bool = false) throws -> Relation {
        let (first, second) = input(reversed)
        let result = try DefaultSurfaceSurfaceIntersector().intersectionResult(first: first, second: second, tolerance: .standard)
        let relation = try owner(result)
        try require(!relation.isEmpty && result.intersections.count == 1 && relation.branchCount == 2)
        try require(relation.originalParameterDimension == 4 && relation.imageDimension == 1 && relation.fiberDimension == nil && relation.stratumCount == 3)
        guard case .originalApexSphereCone(let component) = result.intersections[0] else { throw Failure(line: #line) }
        try require(component.relation === relation && component.firstSurface == first && component.secondSurface == second)
        let strata = component.strata
        try require(strata.0.imageDimension == 0 && strata.0.fiberDimension == 1)
        try require(strata.1.imageDimension == 1 && strata.1.fiberDimension == 0 && !strata.1.isClosed)
        try require(strata.2.imageDimension == 1 && strata.2.fiberDimension == 0 && !strata.2.isClosed)
        let i = component.apexIncidents
        try require(i.0.chart == 0 && i.0.parameterSide == -1 && i.0.stratum == .negativeArc)
        try require(i.1.chart == 0 && i.1.parameterSide == 1 && i.1.stratum == .positiveArc)
        try require(i.2.chart == 1 && i.2.parameterSide == -1 && i.2.stratum == .positiveArc)
        try require(i.3.chart == 1 && i.3.parameterSide == 1 && i.3.stratum == .negativeArc)
        return relation
    }
    static func success(selected: Int? = nil) throws {
        for reversed in [false, true] {
            let relation = try whole(reversed), source = relation.source.original
            var a = try ledger(); let f = source.field, zero = try f.integer(0, using: &a), one = try f.integer(1, using: &a)
            let rational = ExactRationalScalarDomain()
            var huge = try rational.integer(1, using: &a)
            for _ in 0..<5 { huge = try rational.multiplying(huge, rational.integer(UInt64(1)<<32, using: &a), using: &a) }
            let positive = try OriginalParameterCycle(exact: huge, using: &a)
            let negative = try OriginalParameterCycle(exact: rational.negated(huge, using: &a), using: &a)
            for chart in 0..<2 where selected == nil || selected == (reversed ? 2 : 0)+chart {
                for n in [-3, -1, 0, 1, 3] {
                    var a = try ledger()
                    let t = try f.dividing(f.integer(n, using: &a), f.integer(3, using: &a), using: &a)
                    let section = try relation.section(chart: chart, halfAngle: t, limits: limits(), using: &a)
                    let point = try section.member(coneCycle: positive, sphereCycle: negative, limits: limits(), using: &a)
                    let norm = try f.adding(f.adding(f.multiplying(point.x, point.x, using: &a), f.multiplying(point.y, point.y, using: &a), using: &a), f.multiplying(point.z, point.z, using: &a), using: &a)
                    try require(f.compare(norm, one, using: &a) == .equal)
                    let dx = try f.subtracting(point.x, one, using: &a)
                    let radialSquare = try f.adding(f.multiplying(dx, dx, using: &a), f.multiplying(point.y, point.y, using: &a), using: &a)
                    let metric = try f.subtracting(f.multiplying(f.multiplying(source.cosine, source.cosine, using: &a), radialSquare, using: &a), f.multiplying(f.multiplying(source.sine, source.sine, using: &a), f.multiplying(point.z, point.z, using: &a), using: &a), using: &a)
                    try require(f.sign(of: metric, using: &a) == .zero)
                    try require(f.compare(point.slant, f.multiplying(f.multiplying(f.integer(2, using: &a), source.sine, using: &a), section.sourceValues.sine, using: &a), using: &a) == .equal)
                    try require(point.stratum == (n == 0 ? .apex : ((chart == 0 ? n : -n)>0 ? .positiveArc : .negativeArc)))
                    let first = try point.firstUV(limits: limits(), using: &a), second = try point.secondUV(limits: limits(), using: &a)
                    try require(first.isSphere == !reversed && second.isSphere == reversed)
                    let sphere = reversed ? second : first, cone = reversed ? first : second
                    guard case .coneAngularLabel(let half, _, let offset) = cone.u,
                        case .authoredScalar(let slant) = cone.v else { throw Failure(line: #line) }
                    try require(f.compare(half, t, using: &a) == .equal && f.compare(slant, point.slant, using: &a) == .equal && f.sign(of: offset, using: &a) == .positive)
                    if n != 0 {
                        guard case .sphereAzimuthLabel(let ys, let yc, _, let so) = sphere.u,
                            case .sphereLatitudeLabel(let latitude, _) = sphere.v else { throw Failure(line: #line) }
                        try require(f.compare(ys, f.negated(point.x, using: &a), using: &a) == .equal && f.compare(yc, point.y, using: &a) == .equal)
                        try require(f.compare(latitude, point.z, using: &a) == .equal && f.sign(of: so, using: &a) == .negative)
                    }
                    try require(sphere.member.relation === relation)
                }
            }
            // The apex retains arbitrary authored real U, including non-cycle values.
            var arbitrary = try ledger()
            let largeU = try f.dividing(f.binary64(exactly: 1e100, using: &arbitrary), f.integer(3, using: &arbitrary), using: &arbitrary)
            for u in [largeU, try f.negated(largeU, using: &arbitrary)] {
                let apex = try relation.apex(coneU: u, sphereCycle: negative, limits: limits(), using: &arbitrary)
                try require(f.compare(apex.apexConeU!, u, using: &arbitrary) == .equal)
            }
            for n in [-7, 0, 11] {
                var a = try ledger(); let u = try f.dividing(f.integer(n, using: &a), f.integer(3, using: &a), using: &a)
                let apex = try relation.apex(coneU: u, sphereCycle: negative, limits: limits(), using: &a)
                try require(apex.stratum == .apex && apex.section == nil)
                try require(f.compare(apex.x, one, using: &a) == .equal && f.compare(apex.slant, zero, using: &a) == .equal)
                let first = try apex.firstUV(limits: limits(), using: &a), second = try apex.secondUV(limits: limits(), using: &a)
                let cone = reversed ? first : second, sphere = reversed ? second : first
                guard case .authoredScalar(let actual) = cone.u, case .authoredScalar(let sphereU) = sphere.u, case .authoredScalar(let sphereV) = sphere.v else { throw Failure(line: #line) }
                try require(f.compare(actual, u, using: &a) == .equal && f.compare(sphereV, zero, using: &a) == .equal)
                try require(f.compare(sphereU, f.subtracting(apex.sphereLabelOffset, f.dividing(source.labelPeriod, f.integer(4, using: &a), using: &a), using: &a), using: &a) == .equal)
            }
        }
        print("PASS exact original metrics, both arcs, all apex UV and independent huge cycles")
    }
    static func endpoints() throws {
        let relation = try whole(), source = relation.source.original
        var a = try ledger(); let f = source.field, zero = try OriginalParameterCycle(exact: ExactRationalScalarDomain().integer(0, using: &a), using: &a)
        for n in [-1, 1] {
            let section = try relation.section(chart: 0, halfAngle: f.integer(n, using: &a), limits: limits(), using: &a)
            let other = try section.otherIncident(limits: limits(), using: &a)
            let first = try section.member(coneCycle: zero, sphereCycle: zero, limits: limits(), using: &a)
            let second = try other.member(coneCycle: zero, sphereCycle: zero, limits: limits(), using: &a)
            try require(first.stratum == second.stratum && f.compare(first.x, second.x, using: &a) == .equal && f.compare(first.y, second.y, using: &a) == .equal && f.compare(first.z, second.z, using: &a) == .equal)
            try require(other.chart == 1 && f.compare(other.halfAngle, f.integer(-n, using: &a), using: &a) == .equal)
        }
        let middle = try relation.section(chart: 0, halfAngle: f.integer(0, using: &a), limits: limits(), using: &a)
        try rejects { _ = try middle.otherIncident(limits: limits(), using: &a) }
        try rejects { _ = try relation.section(chart: 2, halfAngle: f.integer(0, using: &a), limits: limits(), using: &a) }
        try rejects { _ = try relation.section(chart: 0, halfAngle: f.integer(2, using: &a), limits: limits(), using: &a) }
        for index in 0..<4 {
            try rejects { try relation.admitProof(limits: limits(source: index == 0 ? 0 : 1, transport: index == 1 ? 0 : 1, charts: index == 2 ? 1 : 2, families: index == 3 ? 2 : 3), using: &a) }
        }
        let other = try whole(true)
        try rejects { _ = try Relation.resolve(source: other.source, firstBox: nil, secondBox: nil, maximumComponents: 1, limits: limits(), prepared: relation, using: &a) }
        var foreign = try ledger(); let physical = try OriginalPhysicalAngleScalarDomain(originalRadians: 0.7, using: &foreign)
        let field = try Relation.Field.base(field: physical, maximumExtensionLevel: 32, using: &foreign)
        try rejects { _ = try relation.apex(coneU: field.integer(0, using: &foreign), sphereCycle: zero, limits: limits(), using: &a) }
        var cancelled = try ledger(); cancelled.cancel()
        try rejects { _ = try relation.section(chart: 0, halfAngle: f.integer(0, using: &a), limits: limits(), using: &cancelled) }
        let i = try ScalarInterval(lower: -0.2, upper: 0.2), box = SurfaceParameterBox(u: i, v: i)
        try rejects { _ = try Relation.resolve(source: relation.source, firstBox: box, secondBox: box, maximumComponents: 1, limits: limits(), using: &a) }
        print("PASS all seam/apex incidents and invalid owner, scope, depth, cancel refusals")
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
            try require(values.count == 1); return nil
        }
        return try solver.intersectionResult(first: first, second: second, options: .init(), tolerance: .standard,
            maximumSpanCount: 262_144, maximumSubdivisionDepth: 8, remainingSourceDepth: sourceDepth,
            consumeWork: { try counter.consume() }, consumeStorage: { try counter.retain($0) }, maximumAlgebraicDepth: scalarDepth)
    }
    static func publication() throws {
        for reversed in [false, true] {
            let (first, second) = input(reversed)
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
