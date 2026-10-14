import CADCore
import CADGeometry
import Synchronization
#if canImport(Darwin)
import Darwin
#else
import WASILibc
#endif

enum BoundedSphereConeSSIAcceptance {
    typealias Relation = OriginalBoundedSphereConeSurfaceRelation
    struct Failure: Error { let line: Int }
    static func require(_ value: Bool, line: Int = #line) throws { guard value else { throw Failure(line: line) } }
    static func rejects(_ body: () throws -> Void) throws {
        do { try body() } catch let e as Failure { throw e } catch { return }; throw Failure(line: #line)
    }
    static func input(_ reversed: Bool = false) -> (Surface3D, Surface3D) {
        let sphere = Surface3D.analytic(.sphere(center: .origin, radius: 2))
        let cone = Surface3D.analytic(.cone(apex: .init(x: 2, y: 0, z: -4), axis: .unitZ,
            halfAngle: Double(bitPattern: 0x3fddac670561bb50)))
        return reversed ? (cone, sphere) : (sphere, cone)
    }
    static func ledger(work: Int = 8_388_608, bytes: Int = 268_435_456, value: Int = 32, coefficient: Int = 32)
        throws -> ExactScalarLedger {
        .init(limits: try .init(work: work, storageBytes: bytes, valueDepth: value, coefficientDepth: coefficient))
    }
    static func limits(source: Int = 1, transport: Int = 1, charts: Int = 2, families: Int = 2) throws -> OriginalDomainIdentityLimits {
        try .init(source: .init(remainingSourceDepth: source), maximumTransportDepth: transport,
            maximumCharts: charts, maximumFamilies: families, maximumIdentityProofs: 0)
    }
    static func owner(_ result: SurfaceSurfaceIntersectionResult) throws -> Relation {
        guard let reader = result.originalBoundedSphereConeRelation else { throw Failure(line: #line) }
        try require(result.representation == .exactRelation)
        try require(reader.isEmpty == reader.original.isEmpty && reader.hasPositiveDimensionalSolutions == !reader.isEmpty)
        return reader.original
    }
    static func whole(_ reversed: Bool = false) throws -> Relation {
        let (first, second) = input(reversed)
        let result = try DefaultSurfaceSurfaceIntersector().intersectionResult(first: first, second: second, tolerance: .standard)
        let relation = try owner(result)
        try require(!relation.isEmpty && result.intersections.count == 1 && relation.branchCount == 2)
        try require(relation.originalParameterDimension == 4 && relation.imageDimension == 1 && relation.fiberDimension == 0)
        guard case .originalBoundedSphereCone(let component) = result.intersections[0] else { throw Failure(line: #line) }
        try require(component.isClosed && component.relation === relation)
        try require(component.firstSurface == first && component.secondSurface == second)
        return relation
    }
    static func success() throws {
        for reversed in [false, true] {
            let relation = try whole(reversed), source = relation.source.original, f = source.field
            var a = try ledger()
            let section = try relation.section(halfAngle: f.integer(1, using: &a), limits: limits(), using: &a)
            try require(!section.isSharedEndpoint)
            let q = ExactRationalScalarDomain(); var huge = try q.integer(1, using: &a)
            for _ in 0..<5 { huge = try q.multiplying(huge, q.integer(UInt64(1) << 32, using: &a), using: &a) }
            let positive = try OriginalParameterCycle(exact: huge, using: &a)
            let negative = try OriginalParameterCycle(exact: q.negated(huge, using: &a), using: &a)
            for branch in 0..<2 {
                // Each independent reader query readmits the retained proof.
                var a = try ledger()
                let point = try section.member(branch: branch, coneCycle: positive, sphereCycle: negative,
                    limits: limits(), using: &a), g = point.field
                let si = try g.importing(source.sine, using: &a), co = try g.importing(source.cosine, using: &a)
                let two = try g.integer(2, using: &a), b = try g.adding(g.multiplying(two, si, using: &a),
                    g.multiplying(g.integer(4, using: &a), co, using: &a), using: &a)
                let quadratic = try g.adding(g.subtracting(g.multiplying(point.slant, point.slant, using: &a),
                    g.multiplying(g.multiplying(two, b, using: &a), point.slant, using: &a), using: &a), g.integer(16, using: &a), using: &a)
                try require(g.sign(of: quadratic, using: &a) == .zero)
                try require(g.compare(g.adding(point.x, g.multiplying(si, point.slant, using: &a), using: &a), two, using: &a) == .equal)
                try require(g.sign(of: point.y, using: &a) == .zero)
                try require(g.compare(g.subtracting(point.z, g.multiplying(co, point.slant, using: &a), using: &a), g.integer(-4, using: &a), using: &a) == .equal)
                // These exact source bounds and X=2-s*lambda prove the same X signs.
                let baseSine = source.sine
                try require(f.compare(baseSine, f.dividing(f.integer(11, using: &a), f.integer(25, using: &a), using: &a), using: &a) == .greater)
                try require(f.compare(baseSine, f.dividing(f.integer(9, using: &a), f.integer(20, using: &a), using: &a), using: &a) == .less)
                try require(g.compare(point.slant, g.integer(branch == 0 ? 6 : 3, using: &a), using: &a) == (branch == 0 ? .greater : .less))
                let first = try point.firstUV(limits: limits(), using: &a), second = try point.secondUV(limits: limits(), using: &a)
                try require(first.isSphere == !reversed && second.isSphere == reversed)
                let sphere = reversed ? second : first, cone = reversed ? first : second
                guard case .sphereAngularInverse(let ys, let yc, _, let offset) = sphere.u,
                    case .sphereLatitudeLabel(let latitude, _) = sphere.v,
                    case .coneAngularLabel(let half, _, let coneOffset) = cone.u,
                    case .authoredScalar(let slant) = cone.v else { throw Failure(line: #line) }
                try require(g.compare(ys, g.negated(point.x, using: &a), using: &a) == .equal)
                try require(g.compare(yc, point.y, using: &a) == .equal)
                try require(g.compare(g.multiplying(two, latitude, using: &a), point.z, using: &a) == .equal)
                try require(g.compare(half, g.integer(1, using: &a), using: &a) == .equal)
                try require(g.compare(slant, point.slant, using: &a) == .equal)
                try require(g.sign(of: offset, using: &a) == .negative && g.sign(of: coneOffset, using: &a) == .positive)
                try require(sphere.member.section.relation === relation)
            }
            try require(section.field.compare(section.plusSlant, section.minusSlant, using: &a) == .greater)
        }
        print("PASS both parent orders, exact two slants/XYZ, all independent huge UV cycles and retained symbolic UV")
    }
    static func endpoints() throws {
        let relation = try whole(), source = relation.source.original; var a = try ledger()
        let zero = try OriginalParameterCycle(exact: ExactRationalScalarDomain().integer(0, using: &a), using: &a)
        for t in [source.lowerHalfAngle, source.upperHalfAngle] {
            var a = try ledger()
            let section = try relation.section(halfAngle: t, limits: limits(), using: &a)
            try require(section.isSharedEndpoint)
            let plus = try section.member(branch: 0, coneCycle: zero, sphereCycle: zero, limits: limits(), using: &a)
            let minus = try section.member(branch: 1, coneCycle: zero, sphereCycle: zero, limits: limits(), using: &a)
            let f = section.field
            try require(f.compare(plus.slant, f.integer(4, using: &a), using: &a) == .equal)
            try require(f.compare(plus.x, minus.x, using: &a) == .equal && f.compare(plus.y, minus.y, using: &a) == .equal)
            try require(f.compare(plus.z, minus.z, using: &a) == .equal)
        }
        try rejects { _ = try relation.section(halfAngle: source.field.integer(0, using: &a), limits: limits(), using: &a) }
        for index in 0..<4 {
            try rejects { try relation.admitProof(limits: limits(source: index == 0 ? 0 : 1,
                transport: index == 1 ? 0 : 1, charts: index == 2 ? 1 : 2, families: index == 3 ? 1 : 2), using: &a) }
        }
        let other = try whole(true)
        try rejects { _ = try Relation.resolve(source: other.source, firstBox: nil, secondBox: nil,
            maximumComponents: 1, limits: limits(), prepared: relation, using: &a) }
        let depth = relation.proofDepth
        var exactDepth = try ledger(value: depth.value, coefficient: depth.coefficient)
        try relation.admitProof(limits: limits(), using: &exactDepth)
        if depth.value > 0 {
            var low = try ledger(value: depth.value - 1, coefficient: depth.coefficient)
            try rejects { try relation.admitProof(limits: limits(), using: &low) }
        }
        if depth.coefficient > 0 {
            var low = try ledger(value: depth.value, coefficient: depth.coefficient - 1)
            try rejects { try relation.admitProof(limits: limits(), using: &low) }
        }
        var foreign = try ledger(); let physical = try OriginalPhysicalAngleScalarDomain(originalRadians: 0.7, using: &foreign)
        let field = try Relation.Field.base(field: physical, maximumExtensionLevel: 32, using: &foreign)
        let value = try field.integer(1, using: &foreign)
        try rejects { _ = try relation.section(halfAngle: value, limits: limits(), using: &a) }
        let t = try source.field.integer(1, using: &a)
        var cancelledSection = try ledger(); cancelledSection.cancel()
        try rejects { _ = try relation.section(halfAngle: t, limits: limits(), using: &cancelledSection) }
        a.cancel(); try rejects { try relation.admitProof(limits: limits(), using: &a) }
        print("PASS both critical endpoint incidents, outside support, source/transport/chart/family, foreign field and cancel")
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
    static func publication(selected: Int? = nil, check: Int? = nil) throws {
        for reversed in [false, true] where selected == nil || selected! / 2 == (reversed ? 1 : 0) {
            let (first, second) = input(reversed)
            if check == nil || check == 0 {
                try require(DefaultSurfaceSurfaceIntersector().intersections(first: first, second: second, tolerance: .standard).count == 1)
            }
            for empty in [false, true] where selected == nil || selected == (reversed ? 2 : 0) + (empty ? 1 : 0) {
                let measured = Counter(); let result = try admitted(reversed, counter: measured, empty: empty)
                guard let result else { throw Failure(line: #line) }; try require(owner(result).isEmpty == empty)
                let n = measured.totals
                if check == nil || check == 0 { _ = try admitted(reversed, counter: Counter(work: n.work, bytes: n.bytes), empty: empty) }
                if check == nil || check == 1 { _ = try admitted(reversed, counter: Counter(work: n.work, bytes: n.bytes), empty: empty, bare: true) }
                if check == nil || check == 2 { try rejects { _ = try admitted(reversed, counter: Counter(work: n.work - 1, bytes: n.bytes), empty: empty) } }
                if check == nil || check == 3 { try rejects { _ = try admitted(reversed, counter: Counter(work: n.work, bytes: n.bytes - 1), empty: empty) } }
                for (index, at) in [1, n.work / 2, n.work].enumerated() where check == nil || check == index + 4 {
                    try rejects { _ = try admitted(reversed, counter: Counter(cancelAt: at), empty: empty) }
                }
            }
        }
        try rejects { _ = try admitted(counter: Counter(), sourceDepth: 0) }
        try rejects { _ = try admitted(counter: Counter(), scalarDepth: 0) }
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
        if group.hasPrefix("publication-case-") {
            let pieces = group.split(separator: "-")
            guard pieces.count == 4, let selected = Int(pieces[2]), let check = Int(pieces[3]),
                (0..<4).contains(selected), (0..<7).contains(check) else { throw Failure(line: #line) }
            try publication(selected: selected, check: check)
            return
        }
        try require(["all", "success", "endpoints", "publication", "publication-0", "publication-1", "publication-2", "publication-3", "prepared", "terminal"].contains(group))
        if group == "all" || group == "success" { try success() }
        if group == "all" || group == "endpoints" { try endpoints() }
        if group == "all" || group == "publication" { try publication() }
        for index in 0..<4 where group == "publication-" + String(index) { try publication(selected: index) }
        if group == "all" || group == "prepared" { try prepared() }
        if group == "all" || group == "terminal" { try await terminalCancel() }
        print("PASS bounded sphere-cone original parent SSI verification group")
    }
}
