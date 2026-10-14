import CADCore
import CADGeometry

enum GeneralLiftedFiniteSphereConeSSIAcceptance {
    typealias Fixture = GeneralBoundedFiniteSphereConeSSIAcceptance
    typealias Field = OriginalBoundedSphereConeSurfaceSnapshot.Field
    typealias Counter = Fixture.Counter
    static let period = Double(bitPattern: 0x401921fb54442d18)
    static func liftedBoxes(coneCycle: Int, sphereCycle: Int) throws -> (sphere: SurfaceParameterBox, cone: SurfaceParameterBox) {
        let original = try Fixture.boxes()
        return (SurfaceParameterBox(u: try .init(lower: Double(sphereCycle) * period - 2,
            upper: Double(sphereCycle) * period - 1), v: original.sphere.v),
            SurfaceParameterBox(u: try .init(lower: Double(coneCycle) * period + 1,
                upper: Double(coneCycle) * period + 2), v: original.cone.v))
    }
    static func admitted(_ boxes: (sphere: SurfaceParameterBox, cone: SurfaceParameterBox), reversed: Bool,
        counter: Counter) throws -> SurfaceSurfaceIntersectionResult {
        let pair = Fixture.input()
        return try DefaultSurfaceSurfaceIntersector().intersectionResult(first: reversed ? pair.cone : pair.sphere,
            over: reversed ? boxes.cone : boxes.sphere, second: reversed ? pair.sphere : pair.cone,
            over: reversed ? boxes.sphere : boxes.cone, tolerance: .standard,
            maximumSpanCount: 262_144, maximumSubdivisionDepth: 8, remainingSourceDepth: 1,
            consumeWork: { try counter.consume() }, consumeStorage: { try counter.retain($0) }, maximumAlgebraicDepth: 32)
    }
    static func owner(_ result: SurfaceSurfaceIntersectionResult, boxes: (sphere: SurfaceParameterBox, cone: SurfaceParameterBox),
        reversed: Bool, dimension: Int) throws -> OriginalBoundedSphereConeSurfaceRelation {
        guard let relation = result.originalBoundedSphereConeRelation?.original, let receipt = relation.finiteArc,
            result.intersections.count == 1, case .originalBoundedSphereCone(let component) = result.intersections[0] else {
            throw Fixture.Failure(line: #line)
        }
        try Fixture.require(result.representation == .exactRelation && !relation.isEmpty && relation.branchCount == 1)
        try Fixture.require(receipt.branch == 1 && receipt.imageDimension == dimension && relation.imageDimension == dimension)
        try Fixture.require(receipt.firstBox == (reversed ? boxes.cone : boxes.sphere))
        try Fixture.require(receipt.secondBox == (reversed ? boxes.sphere : boxes.cone))
        try Fixture.require(receipt.coneU == boxes.cone.u.lower...boxes.cone.u.upper)
        try Fixture.require(component.relation === relation && !component.isClosed && component.imageDimension == dimension)
        try Fixture.require(relation.source.original.sphereIsFirst == !reversed)
        try Fixture.require(relation.hasPositiveDimensionalSolutions == (dimension == 1))
        return relation
    }
    static func fieldValue(_ rational: ExactRationalCoefficient, field: Field, using a: inout ExactScalarLedger) throws -> Field.Value {
        let base = try field.integer(UInt64(1) << 32, using: &a)
        var numerator = try field.integer(0, using: &a), denominator = try field.integer(0, using: &a)
        for word in rational.canonicalNumeratorWords.reversed() {
            numerator = try field.adding(field.multiplying(numerator, base, using: &a), field.integer(word, using: &a), using: &a)
        }
        for word in rational.canonicalDenominatorWords.reversed() {
            denominator = try field.adding(field.multiplying(denominator, base, using: &a), field.integer(word, using: &a), using: &a)
        }
        if rational.canonicalSign < 0 { numerator = try field.negated(numerator, using: &a) }
        return try field.dividing(numerator, denominator, using: &a)
    }
    static func verify(_ member: OriginalBoundedSphereConeSurfaceArcMember, rawU: Double,
        principal: ExactRationalCoefficient, coneCycle: ExactRationalCoefficient, sphereCycle: ExactRationalCoefficient) throws {
        try Fixture.verify(member, coneU: rawU, inputIndex: 0)
        let p = member.position, f = member.relation.source.original.field, q = ExactRationalScalarDomain()
        var a = try Fixture.ledger()
        try Fixture.require(q.compare(p.coneCycle, coneCycle, using: &a) == .equal)
        try Fixture.require(q.compare(p.sphereCycle, sphereCycle, using: &a) == .equal)
        let expected = try fieldValue(principal, field: f, using: &a)
        try Fixture.require(f.compare(p.principalConeU, expected, using: &a) == .equal)
        try Fixture.require(f.compare(p.slant.principalConeU, expected, using: &a) == .equal)
        let offset = try f.multiplying(fieldValue(coneCycle, field: f, using: &a), p.slant.labelPeriod, using: &a)
        try Fixture.require(f.compare(f.adding(p.principalConeU, offset, using: &a), p.coneU, using: &a) == .equal)
        let sphereOffset = try f.multiplying(fieldValue(sphereCycle, field: f, using: &a), p.slant.labelPeriod, using: &a)
        try Fixture.require(f.compare(p.sphereInverse.azimuthOffset, sphereOffset, using: &a) == .equal)
        try Fixture.require(q.compare(p.sphereInverse.sphereCycle, sphereCycle, using: &a) == .equal)
        var first = try Fixture.ledger(), second = try Fixture.ledger()
        let firstUV = try member.firstUV(limits: Fixture.limits(), using: &first)
        let secondUV = try member.secondUV(limits: Fixture.limits(), using: &second)
        guard case .cone(let raw, let slant) = member.sphereIsFirst ? secondUV : firstUV,
            case .sphere(let inverse) = member.sphereIsFirst ? firstUV : secondUV else { throw Fixture.Failure(line: #line) }
        try Fixture.require(f.compare(raw, f.binary64(exactly: rawU, using: &a), using: &a) == .equal)
        try Fixture.require(f.compare(slant.principalConeU, expected, using: &a) == .equal)
        try Fixture.require(f.compare(inverse.azimuthOffset, sphereOffset, using: &a) == .equal)
        for coordinate in [p.x, p.y, p.z, inverse.x, inverse.y, inverse.z] {
            try Fixture.require(f.compare(coordinate.slant.principalConeU, expected, using: &a) == .equal)
            try Fixture.require(f.compare(coordinate.slant.coneU, raw, using: &a) == .equal)
        }
    }
    static func success(selected: Int? = nil) throws {
        for (index, cycles) in [(1, 0), (-2, 3)].enumerated() where selected == nil || selected == index {
            let boxes = try liftedBoxes(coneCycle: cycles.0, sphereCycle: cycles.1)
            for reversed in [false, true] {
                let relation = try owner(admitted(boxes, reversed: reversed, counter: Counter()), boxes: boxes,
                    reversed: reversed, dimension: 1)
                guard let receipt = relation.finiteArc else { throw Fixture.Failure(line: #line) }
                let q = ExactRationalScalarDomain(); var setup = try Fixture.ledger()
                let cone = try q.integer(cycles.0, using: &setup), sphere = try q.integer(cycles.1, using: &setup)
                try Fixture.require(q.compare(receipt.coneCycle, cone, using: &setup) == .equal)
                try Fixture.require(q.compare(receipt.sphereCycle, sphere, using: &setup) == .equal)
                try Fixture.require(q.compare(receipt.principalConeLower, q.integer(1, using: &setup), using: &setup) == .equal)
                try Fixture.require(q.compare(receipt.principalConeUpper, q.integer(2, using: &setup), using: &setup) == .equal)
                try Fixture.require(q.compare(receipt.principalSphereLower, q.integer(-2, using: &setup), using: &setup) == .equal)
                try Fixture.require(q.compare(receipt.principalSphereUpper, q.integer(-1, using: &setup), using: &setup) == .equal)
                let coneLabel = try OriginalParameterCycle(exact: cone, using: &setup)
                let sphereLabel = try OriginalParameterCycle(exact: sphere, using: &setup)
                for (rawU, principalU) in [(boxes.cone.u.lower, 1.0), ((boxes.cone.u.lower + boxes.cone.u.upper) / 2, 1.5),
                    (boxes.cone.u.upper, 2.0)] {
                    var query = try Fixture.ledger()
                    let member = try relation.member(coneU: relation.source.original.field.binary64(exactly: rawU, using: &query),
                        branch: 1, coneCycle: coneLabel, sphereCycle: sphereLabel, limits: Fixture.limits(), using: &query)
                    var expected = try Fixture.ledger()
                    try verify(member, rawU: rawU, principal: q.binary64(exactly: principalU, using: &expected),
                        coneCycle: cone, sphereCycle: sphere)
                }
            }
        }
        print("PASS independent finite cone/sphere lifts (1,0) and (-2,3), both orders and all endpoint/interior UV laws")
    }
    static func huge(selected: Int? = nil) throws {
        // Python Fraction divmod of exact binary64 U by B=884279719003555/140737488355328.
        let cases: [(UInt64, Int, [UInt32], [UInt32], [UInt32])] = [
            (0x4470000000000000, 1, [2433072369, 3194018707, 40], [2217180557, 47131], [0, 32768]),
            (0xc590000000000000, -1, [4089768554, 1850622998, 10680707], [2017274303, 29826], [0, 16384])]
        for (index, entry) in cases.enumerated() where selected == nil || selected == index {
            let (bits, sign, words, numerator, denominator) = entry, rawU = Double(bitPattern: bits)
            let original = try Fixture.boxes()
            let boxes = (sphere: original.sphere,
                cone: SurfaceParameterBox(u: try ScalarInterval(lower: rawU, upper: rawU), v: original.cone.v))
            let q = ExactRationalScalarDomain(); var oracle = try Fixture.ledger()
            let cycle = try q.canonical(sign: sign, numerator: words, denominator: [1], using: &oracle)
            let remainder = try q.canonical(sign: 1, numerator: numerator, denominator: denominator, using: &oracle)
            let zero = try q.integer(0, using: &oracle), b = try q.binary64(exactly: period, using: &oracle)
            try Fixture.require(q.compare(q.adding(q.multiplying(cycle, b, using: &oracle), remainder, using: &oracle),
                q.binary64(exactly: rawU, using: &oracle), using: &oracle) == .equal)
            try Fixture.require(q.compare(remainder, q.dividing(q.integer(11, using: &oracle), q.integer(10, using: &oracle),
                using: &oracle), using: &oracle) == .greater)
            try Fixture.require(q.compare(remainder, q.dividing(q.integer(19, using: &oracle), q.integer(10, using: &oracle),
                using: &oracle), using: &oracle) == .less)
            try Fixture.require(words.count == 3)
            for reversed in [false, true] {
                let relation = try owner(admitted(boxes, reversed: reversed, counter: Counter()), boxes: boxes,
                    reversed: reversed, dimension: 0)
                guard let receipt = relation.finiteArc else { throw Fixture.Failure(line: #line) }
                var setup = try Fixture.ledger()
                try Fixture.require(q.compare(receipt.coneCycle, cycle, using: &setup) == .equal)
                try Fixture.require(q.compare(receipt.sphereCycle, zero, using: &setup) == .equal)
                try Fixture.require(q.compare(receipt.principalConeLower, remainder, using: &setup) == .equal)
                try Fixture.require(q.compare(receipt.principalConeUpper, remainder, using: &setup) == .equal)
                let coneLabel = try OriginalParameterCycle(exact: cycle, using: &setup)
                let sphereLabel = try OriginalParameterCycle(exact: zero, using: &setup)
                var query = try Fixture.ledger()
                let member = try relation.member(coneU: relation.source.original.field.binary64(exactly: rawU, using: &query),
                    branch: 1, coneCycle: coneLabel, sphereCycle: sphereLabel, limits: Fixture.limits(), using: &query)
                try verify(member, rawU: rawU, principal: remainder, coneCycle: cycle, sphereCycle: zero)
            }
        }
        print("PASS exact nonempty positive/negative huge-U singletons with cycles beyond UInt64 and independent rational remainders")
    }
    static func controls() throws {
        let boxes = try liftedBoxes(coneCycle: -2, sphereCycle: 3)
        let relation = try owner(admitted(boxes, reversed: false, counter: Counter()), boxes: boxes, reversed: false, dimension: 1)
        guard let receipt = relation.finiteArc else { throw Fixture.Failure(line: #line) }
        let q = ExactRationalScalarDomain(); var setup = try Fixture.ledger()
        let cone = try q.integer(-2, using: &setup), sphere = try q.integer(3, using: &setup)
        let coneLabel = try OriginalParameterCycle(exact: cone, using: &setup)
        let sphereLabel = try OriginalParameterCycle(exact: sphere, using: &setup)
        let raw = try relation.source.original.field.binary64(exactly: boxes.cone.u.lower, using: &setup)
        for (wrongCone, wrongSphere) in [(-1, 3), (-2, 2)] {
            var query = try Fixture.ledger()
            let c = try OriginalParameterCycle(exact: q.integer(wrongCone, using: &query), using: &query)
            let s = try OriginalParameterCycle(exact: q.integer(wrongSphere, using: &query), using: &query)
            try Fixture.require(try !receipt.accepts(coneCycle: c.original, sphereCycle: s.original, using: &query))
            do {
                _ = try relation.member(coneU: raw, branch: 1, coneCycle: c, sphereCycle: s, limits: Fixture.limits(), using: &query)
                throw Fixture.Failure(line: #line)
            } catch let error as OriginalDomainIdentityFailure {
                guard case .outsideSupport = error else { throw error }
            }
        }
        var measured = try Fixture.ledger()
        let member = try relation.member(coneU: raw, branch: 1, coneCycle: coneLabel, sphereCycle: sphereLabel,
            limits: Fixture.limits(), using: &measured)
        var exact = try Fixture.ledger(work: measured.work, bytes: measured.storageBytes)
        _ = try relation.member(coneU: raw, branch: 1, coneCycle: coneLabel, sphereCycle: sphereLabel,
            limits: Fixture.limits(), using: &exact)
        var lowWork = try Fixture.ledger(work: measured.work - 1, bytes: measured.storageBytes)
        try Fixture.rejectsQuery { _ = try relation.member(coneU: raw, branch: 1, coneCycle: coneLabel,
            sphereCycle: sphereLabel, limits: Fixture.limits(), using: &lowWork) }
        var lowStorage = try Fixture.ledger(work: measured.work, bytes: measured.storageBytes - 1)
        try Fixture.rejectsQuery { _ = try relation.member(coneU: raw, branch: 1, coneCycle: coneLabel,
            sphereCycle: sphereLabel, limits: Fixture.limits(), using: &lowStorage) }
        var cancelled = try Fixture.ledger(); cancelled.cancel()
        try Fixture.rejectsQuery { _ = try relation.member(coneU: raw, branch: 1, coneCycle: coneLabel,
            sphereCycle: sphereLabel, limits: Fixture.limits(), using: &cancelled) }
        var detached = try Fixture.ledger()
        try member.admitProof(limits: Fixture.limits(), using: &detached)
        try verify(member, rawU: boxes.cone.u.lower, principal: q.integer(1, using: &setup), coneCycle: cone, sphereCycle: sphere)
        print("PASS independent wrong-cycle refusal, lifted query N/N-1 work/storage, cancellation and retained member admission")
    }
}
