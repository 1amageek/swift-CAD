import CADCore
import CADGeometry

enum GeneralBoundedFiniteSphereConeSSIAcceptance {
    typealias Counter = BoundedSphereConeSSIAcceptance.Counter
    struct Failure: Error { let line: Int }
    static func require(_ value: Bool, line: Int = #line) throws {
        guard value else { throw Failure(line: line) }
    }
    static func ledger(work: Int = 8_388_608, bytes: Int = 268_435_456) throws -> ExactScalarLedger {
        .init(limits: try .init(work: work, storageBytes: bytes,
            valueDepth: 32, coefficientDepth: 32))
    }
    static func limits() throws -> OriginalDomainIdentityLimits {
        try .init(source: .init(remainingSourceDepth: 1), maximumTransportDepth: 1,
            maximumCharts: 2, maximumFamilies: 2, maximumIdentityProofs: 0)
    }
    static func input(_ index: Int = 0) -> (sphere: Surface3D, cone: Surface3D) {
        let center = index == 2 ? Point3D(x: 5, y: -3, z: 7) : .origin
        let scale = index == 1 ? 2.0 : 1.0
        return (.analytic(.sphere(center: center, radius: 2 * scale)),
            .analytic(.cone(apex: .init(x: center.x + 3 * scale, y: center.y, z: center.z - 4 * scale),
                axis: .unitZ, halfAngle: Double(bitPattern: 0x3fddac670561bb50))))
    }
    static func boxes(_ index: Int = 0) throws -> (sphere: SurfaceParameterBox, cone: SurfaceParameterBox) {
        let scale = index == 1 ? 2.0 : 1.0
        return (SurfaceParameterBox(u: try .init(lower: -2, upper: -1), v: try .init(lower: -1, upper: 0)),
            SurfaceParameterBox(u: try .init(lower: 1, upper: 2), v: try .init(lower: 3 * scale, upper: 4 * scale)))
    }
    static func admitted(_ reversed: Bool = false, counter: Counter, sourceDepth: Int = 1, inputIndex: Int = 0)
        throws -> SurfaceSurfaceIntersectionResult {
        let pair = input(inputIndex), selection = try boxes(inputIndex)
        return try DefaultSurfaceSurfaceIntersector().intersectionResult(first: reversed ? pair.cone : pair.sphere,
            over: reversed ? selection.cone : selection.sphere, second: reversed ? pair.sphere : pair.cone,
            over: reversed ? selection.sphere : selection.cone, tolerance: .standard,
            maximumSpanCount: 262_144, maximumSubdivisionDepth: 8, remainingSourceDepth: sourceDepth,
            consumeWork: { try counter.consume() }, consumeStorage: { try counter.retain($0) }, maximumAlgebraicDepth: 32)
    }
    static func rejectsPublication(_ code: KernelErrorCode = .resourceLimitExceeded, _ body: () throws -> Void) throws {
        do { try body() }
        catch let error as KernelError {
            try require(error.code == code)
            return
        }
        throw Failure(line: #line)
    }
    static func rejectsCancellation(_ body: () throws -> Void) throws {
        do { try body() }
        catch is CancellationError { return }
        throw Failure(line: #line)
    }
    static func interiorOracle() throws {
        let pair = input()
        let whole = try DefaultSurfaceSurfaceIntersector().intersectionResult(first: pair.sphere,
            second: pair.cone, tolerance: .standard)
        guard let relation = whole.originalBoundedSphereConeRelation?.original else {
            throw Failure(line: #line)
        }
        var query = try ledger()
        let section = try relation.section(halfAngle: relation.source.original.field.integer(1, using: &query),
            limits: limits(), using: &query)
        let zero = try OriginalParameterCycle(exact: ExactRationalScalarDomain().integer(0, using: &query), using: &query)
        let member = try section.member(branch: 1, coneCycle: zero, sphereCycle: zero,
            limits: limits(), using: &query)
        var proof = try ledger()
        let f = member.field
        try require(f.compare(member.slant, f.integer(3, using: &proof), using: &proof) == .greater)
        try require(f.compare(member.slant, f.integer(4, using: &proof), using: &proof) == .less)
        try require(f.sign(of: member.x, using: &proof) == .positive)
        try require(f.sign(of: member.y, using: &proof) == .zero)
        try require(f.compare(section.sine, f.integer(1, using: &proof), using: &proof) == .equal)
        try require(f.sign(of: section.cosine, using: &proof) == .zero)
        let latitude = try member.sphereLatitudeSine(limits: limits(), using: &proof)
        let lower = try f.dividing(f.integer(-61, using: &proof), f.integer(100, using: &proof), using: &proof)
        try require(f.compare(latitude, lower, using: &proof) == .greater)
        try require(f.sign(of: latitude, using: &proof) == .negative)
        let period = try f.importing(relation.source.original.labelPeriod, using: &proof)
        try require(f.compare(period, f.integer(6, using: &proof), using: &proof) == .greater)
        try require(f.compare(period, f.dividing(f.integer(63, using: &proof), f.integer(10, using: &proof),
            using: &proof), using: &proof) == .less)
        let q = ExactRationalScalarDomain()
        var rational = try ledger()
        let twoThirds = try q.dividing(q.integer(2, using: &rational), q.integer(3, using: &rational), using: &rational)
        let cube = try q.multiplying(q.multiplying(twoThirds, twoThirds, using: &rational), twoThirds, using: &rational)
        let sineLower = try q.subtracting(twoThirds, q.dividing(cube, q.integer(6, using: &rational), using: &rational), using: &rational)
        try require(q.compare(sineLower, q.dividing(q.integer(61, using: &rational), q.integer(100, using: &rational),
            using: &rational), using: &rational) == .greater)
        // sin(2/3)>50/81>61/100 and pi>3 imply V>-B/9>-7/10.
        // X>0,Y=0 give sphere U=-B/4; t=1 gives cone U=B/4.
        print("PASS independent exact interior witness in both finite original UV boxes")
    }
    static func success(selected: Int? = nil) throws {
        for index in 0..<3 where selected == nil || selected == index {
            let pair = input(index)
            let selection = try boxes(index)
            for reversed in [false, true] {
                let result = try admitted(reversed, counter: Counter(), inputIndex: index)
                guard let relation = result.originalBoundedSphereConeRelation?.original,
                    let receipt = relation.finiteArc, result.intersections.count == 1,
                    case .originalBoundedSphereCone(let component) = result.intersections[0] else {
                    throw Failure(line: #line)
                }
                try require(result.representation == .exactRelation && !relation.isEmpty)
                try require(relation.branchCount == 1 && relation.imageDimension == 1 && relation.fiberDimension == 0)
                try require(relation.hasPositiveDimensionalSolutions && relation.hasPositiveDimensionalImage)
                try require(receipt.coneU == 1...2 && receipt.branch == 1 && receipt.imageDimension == 1)
                try require(receipt.firstBox == (reversed ? selection.cone : selection.sphere))
                try require(receipt.secondBox == (reversed ? selection.sphere : selection.cone))
                try require(component.relation === relation && !component.isClosed && component.imageDimension == 1)
                try require(component.firstSurface == (reversed ? pair.cone : pair.sphere))
                try require(component.secondSurface == (reversed ? pair.sphere : pair.cone))
                var prepare = try ledger()
                let zero = try OriginalParameterCycle(exact: ExactRationalScalarDomain().integer(0, using: &prepare), using: &prepare)
                for coneU in [1.0, 1.5, 2.0] {
                    var query = try ledger()
                    let raw = try relation.source.original.field.binary64(exactly: coneU, using: &query)
                    let member = try component.member(coneU: raw, branch: 1, coneCycle: zero, sphereCycle: zero,
                        limits: limits(), using: &query)
                    try require(member.relation === relation && member.branch == 1 && member.sphereIsFirst == !reversed)
                    try verify(member, coneU: coneU, inputIndex: index)
                }
                var legacy = try ledger()
                do {
                    _ = try relation.section(halfAngle: relation.source.original.field.integer(1, using: &legacy),
                        limits: limits(), using: &legacy)
                    throw Failure(line: #line)
                } catch let error as OriginalDomainIdentityFailure {
                    guard case .incompleteCoverage = error else { throw error }
                }
            }
        }
        print("PASS finite exact SSI both orders, original endpoints U=1 and U=2, interior U=3/2, translated/scaled source laws")
    }
    static func verify(_ member: OriginalBoundedSphereConeSurfaceArcMember, coneU: Double, inputIndex: Int) throws {
        let source = member.relation.source.original, position = member.position, f = source.field
        let scale = inputIndex == 1 ? 2.0 : 1.0
        let center = inputIndex == 2 ? Point3D(x: 5, y: -3, z: 7) : .origin
        var proof = try ledger()
        try require(position.source.original.original.first == source.original.first)
        try require(position.source.original.original.second == source.original.second)
        func same(_ lhs: OriginalBoundedSphereConeSurfaceSnapshot.Field.Value,
            _ rhs: OriginalBoundedSphereConeSurfaceSnapshot.Field.Value) throws {
            try require(f.compare(lhs, rhs, using: &proof) == .equal)
        }
        try same(member.coneU, f.binary64(exactly: coneU, using: &proof))
        try same(position.coneU, member.coneU)
        let slant = position.slant
        try require(position.branch == 1 && slant.branch == 1)
        try same(slant.coneU, member.coneU)
        try same(slant.labelPeriod, source.labelPeriod)
        try same(slant.middleOffset, f.multiplying(f.binary64(exactly: 4 * scale, using: &proof), source.cosine, using: &proof))
        try same(slant.sineCoefficient, f.multiplying(f.binary64(exactly: 3 * scale, using: &proof), source.sine, using: &proof))
        try same(slant.constant, f.binary64(exactly: 21 * scale * scale, using: &proof))
        for (axis, coordinate, apex) in [(0, position.x, center.x + 3 * scale),
            (1, position.y, center.y), (2, position.z, center.z - 4 * scale)] {
            try require(coordinate.axis == axis && coordinate.slant.branch == slant.branch)
            try same(coordinate.apex, f.binary64(exactly: apex, using: &proof))
            try same(coordinate.sourceSine, source.sine)
            try same(coordinate.sourceCosine, source.cosine)
            try same(coordinate.slant.coneU, member.coneU)
            try same(coordinate.slant.middleOffset, slant.middleOffset)
            try same(coordinate.slant.sineCoefficient, slant.sineCoefficient)
            try same(coordinate.slant.constant, slant.constant)
        }
        var firstQuery = try ledger(), secondQuery = try ledger()
        let first = try member.firstUV(limits: limits(), using: &firstQuery)
        let second = try member.secondUV(limits: limits(), using: &secondQuery)
        guard case .cone(let u, let v) = member.sphereIsFirst ? second : first,
            case .sphere(let sphere) = member.sphereIsFirst ? first : second else { throw Failure(line: #line) }
        try same(u, member.coneU)
        try require(v.branch == 1 && sphere.x.axis == 0 && sphere.y.axis == 1 && sphere.z.axis == 2)
        try same(v.coneU, member.coneU)
        try same(v.constant, slant.constant)
        try same(sphere.centerX, f.binary64(exactly: center.x, using: &proof))
        try same(sphere.centerY, f.binary64(exactly: center.y, using: &proof))
        try same(sphere.centerZ, f.binary64(exactly: center.z, using: &proof))
        try same(sphere.radius, f.binary64(exactly: 2 * scale, using: &proof))
        try same(sphere.labelPeriod, source.labelPeriod)
        for coordinate in [sphere.x, sphere.y, sphere.z] {
            try same(coordinate.slant.coneU, member.coneU)
            try same(coordinate.slant.constant, slant.constant)
        }
        var independent = try ledger()
        try member.admitProof(limits: limits(), using: &independent)
    }
    static func rejectsQuery(_ body: () throws -> Void) throws {
        do { try body() }
        catch let error as Failure { throw error }
        catch { return }
        throw Failure(line: #line)
    }
    static func controls() throws {
        let counter = Counter(), result = try admitted(counter: counter)
        guard let relation = result.originalBoundedSphereConeRelation?.original,
            let receipt = relation.finiteArc else { throw Failure(line: #line) }
        let n = counter.totals
        try require(n.work > 0 && n.bytes > 0)
        try require(try admitted(counter: Counter(work: n.work, bytes: n.bytes)).intersections.count == 1)
        try rejectsPublication { _ = try admitted(counter: Counter(work: n.work - 1, bytes: n.bytes)) }
        try rejectsPublication { _ = try admitted(counter: Counter(work: n.work, bytes: n.bytes - 1)) }
        for at in [1, n.work / 2, n.work] {
            try rejectsCancellation { _ = try admitted(counter: Counter(cancelAt: at)) }
        }
        try rejectsPublication { _ = try admitted(counter: Counter(), sourceDepth: 0) }
        var setup = try ledger()
        let f = relation.source.original.field
        let raw = try f.binary64(exactly: 1.5, using: &setup)
        let zero = try OriginalParameterCycle(exact: ExactRationalScalarDomain().integer(0, using: &setup), using: &setup)
        var measured = try ledger()
        let member = try relation.member(coneU: raw, branch: 1, coneCycle: zero, sphereCycle: zero,
            limits: limits(), using: &measured)
        try require(measured.work > 0 && measured.storageBytes > 0)
        var exact = try ledger(work: measured.work, bytes: measured.storageBytes)
        _ = try relation.member(coneU: raw, branch: 1, coneCycle: zero, sphereCycle: zero,
            limits: limits(), using: &exact)
        var lowWork = try ledger(work: measured.work - 1, bytes: measured.storageBytes)
        try rejectsQuery { _ = try relation.member(coneU: raw, branch: 1, coneCycle: zero, sphereCycle: zero,
            limits: limits(), using: &lowWork) }
        var lowStorage = try ledger(work: measured.work, bytes: measured.storageBytes - 1)
        try rejectsQuery { _ = try relation.member(coneU: raw, branch: 1, coneCycle: zero, sphereCycle: zero,
            limits: limits(), using: &lowStorage) }
        var cancelled = try ledger(); cancelled.cancel()
        try rejectsQuery { _ = try relation.member(coneU: raw, branch: 1, coneCycle: zero, sphereCycle: zero,
            limits: limits(), using: &cancelled) }
        var cancelledReceipt = try ledger(); cancelledReceipt.cancel()
        try rejectsQuery { try receipt.admitProof(using: &cancelledReceipt) }
        var cancelledMember = try ledger(); cancelledMember.cancel()
        try rejectsQuery { _ = try member.secondUV(limits: limits(), using: &cancelledMember) }
        var wrongBranch = try ledger()
        try rejectsQuery { _ = try relation.member(coneU: raw, branch: 0, coneCycle: zero, sphereCycle: zero,
            limits: limits(), using: &wrongBranch) }
        for value in [0.5, 2.5] {
            var outside = try ledger()
            let raw = try f.binary64(exactly: value, using: &outside)
            try require(try !receipt.contains(raw, using: &outside))
            try rejectsQuery { _ = try relation.member(coneU: raw, branch: 1, coneCycle: zero, sphereCycle: zero,
                limits: limits(), using: &outside) }
        }
        try detached()
        print("PASS finite public/query N/N-1 work/storage, entry/mid/final/query cancellation, branch/scope and source release")
    }
    static func detached() throws {
        var pair = input(2)
        let selection = try boxes(2)
        let counter = Counter()
        var result: SurfaceSurfaceIntersectionResult? = try DefaultSurfaceSurfaceIntersector().intersectionResult(
            first: pair.sphere, over: selection.sphere, second: pair.cone, over: selection.cone, tolerance: .standard,
            maximumSpanCount: 262_144, maximumSubdivisionDepth: 8, remainingSourceDepth: 1,
            consumeWork: { try counter.consume() }, consumeStorage: { try counter.retain($0) }, maximumAlgebraicDepth: 32)
        guard let relation = result?.originalBoundedSphereConeRelation?.original else { throw Failure(line: #line) }
        result = nil
        pair = (.analytic(.plane(origin: .origin, normal: .unitX)), .analytic(.plane(origin: .origin, normal: .unitZ)))
        try require(pair.sphere != relation.source.original.original.first && pair.cone != relation.source.original.original.second)
        var setup = try ledger()
        let zero = try OriginalParameterCycle(exact: ExactRationalScalarDomain().integer(0, using: &setup), using: &setup)
        for value in [1.0, 2.0] {
            var query = try ledger()
            let member = try relation.member(coneU: relation.source.original.field.binary64(exactly: value, using: &query),
                branch: 1, coneCycle: zero, sphereCycle: zero, limits: limits(), using: &query)
            try verify(member, coneU: value, inputIndex: 2)
        }
    }
    static func singleton() throws {
        let pair = input(), selection = try boxes()
        let coneBox = SurfaceParameterBox(u: try .init(lower: 1.5, upper: 1.5), v: selection.cone.v)
        for reversed in [false, true] {
            let counter = Counter()
            let result = try DefaultSurfaceSurfaceIntersector().intersectionResult(first: reversed ? pair.cone : pair.sphere,
                over: reversed ? coneBox : selection.sphere, second: reversed ? pair.sphere : pair.cone,
                over: reversed ? selection.sphere : coneBox, tolerance: .standard,
                maximumSpanCount: 262_144, maximumSubdivisionDepth: 8, remainingSourceDepth: 1,
                consumeWork: { try counter.consume() }, consumeStorage: { try counter.retain($0) }, maximumAlgebraicDepth: 32)
            guard let relation = result.originalBoundedSphereConeRelation?.original, let receipt = relation.finiteArc,
                result.intersections.count == 1, case .originalBoundedSphereCone(let component) = result.intersections[0] else {
                throw Failure(line: #line)
            }
            try require(result.representation == .exactRelation && !relation.isEmpty)
            try require(receipt.coneU == 1.5...1.5 && receipt.imageDimension == 0 && relation.imageDimension == 0)
            try require(!relation.hasPositiveDimensionalSolutions && !relation.hasPositiveDimensionalImage)
            try require(component.imageDimension == 0 && component.fiberDimension == 0 && !component.isClosed)
            var query = try ledger()
            let zero = try OriginalParameterCycle(exact: ExactRationalScalarDomain().integer(0, using: &query), using: &query)
            let raw = try relation.source.original.field.binary64(exactly: 1.5, using: &query)
            let member = try component.member(coneU: raw, branch: 1, coneCycle: zero, sphereCycle: zero,
                limits: limits(), using: &query)
            try verify(member, coneU: 1.5, inputIndex: 0)
        }
        print("PASS exact singleton original-U selection remains a point in both parent orders")
    }
}
