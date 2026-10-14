import CADCore
import CADGeometry

@main struct PreparedLiftedProbe {
    typealias Lifted = GeneralLiftedFiniteSphereConeSSIAcceptance
    typealias Fixture = GeneralBoundedFiniteSphereConeSSIAcceptance
    static func main() throws {
        for index in 0..<2 {
            let coneCycle = index == 0 ? 1 : -2, sphereCycle = index == 0 ? 0 : 3
            let boxes = try Lifted.liftedBoxes(coneCycle: coneCycle, sphereCycle: sphereCycle)
            for order in 0..<2 {
                let reversed = order == 1
                var pair = Fixture.input()
                let counter = Fixture.Counter()
                var session: (any OriginalSurfacePairIntersecting)? = try DefaultSurfaceSurfaceIntersector().prepareOriginalPair(
                    first: reversed ? pair.cone : pair.sphere, second: reversed ? pair.sphere : pair.cone,
                    tolerance: .standard, maximumSpanCount: 262_144, maximumSubdivisionDepth: 8,
                    remainingSourceDepth: 1, consumeWork: { try counter.consume() },
                    consumeStorage: { try counter.retain($0) }, maximumAlgebraicDepth: 32)
                let prepared = counter.totals
                guard let result = try session?.intersectionResult(firstBox: reversed ? boxes.cone : boxes.sphere,
                    secondBox: reversed ? boxes.sphere : boxes.cone, options: .init()) else {
                    throw Fixture.Failure(line: #line)
                }
                let relation = try Lifted.owner(result, boxes: boxes, reversed: reversed, dimension: 1)
                guard let receipt = relation.finiteArc else { throw Fixture.Failure(line: #line) }
                let queried = counter.totals
                try Fixture.require(queried.work > prepared.work && queried.bytes > prepared.bytes)
                try Fixture.require(queried.work <= 8_388_608 && queried.bytes <= 268_435_456)
                session = nil
                pair = (.analytic(.plane(origin: .origin, normal: .unitX)),
                    .analytic(.plane(origin: .origin, normal: .unitZ)))
                try Fixture.require(pair.sphere != relation.source.original.original.first && pair.cone != relation.source.original.original.second)
                let q = ExactRationalScalarDomain(); var setup = try Fixture.ledger()
                let expectedCone = try q.integer(coneCycle, using: &setup)
                let expectedSphere = try q.integer(sphereCycle, using: &setup)
                try Fixture.require(q.compare(receipt.coneCycle, expectedCone, using: &setup) == .equal)
                try Fixture.require(q.compare(receipt.sphereCycle, expectedSphere, using: &setup) == .equal)
                let coneLabel = try OriginalParameterCycle(exact: expectedCone, using: &setup)
                let sphereLabel = try OriginalParameterCycle(exact: expectedSphere, using: &setup)
                for endpoint in 0..<2 {
                    let rawU = endpoint == 0 ? boxes.cone.u.lower : boxes.cone.u.upper
                    var query = try Fixture.ledger()
                    let raw = try relation.source.original.field.binary64(exactly: rawU, using: &query)
                    let member = try relation.member(coneU: raw, branch: 1, coneCycle: coneLabel,
                        sphereCycle: sphereLabel, limits: Fixture.limits(), using: &query)
                    var independent = try Fixture.ledger()
                    try member.admitProof(limits: Fixture.limits(), using: &independent)
                    try Lifted.verify(member, rawU: rawU, principal: q.integer(endpoint + 1, using: &setup),
                        coneCycle: expectedCone, sphereCycle: expectedSphere)
                }
                try Fixture.require(counter.totals.work == queried.work && counter.totals.bytes == queried.bytes)
                print("PASS lifted prepared coneCycle", coneCycle, "sphereCycle", sphereCycle, "reversed", reversed,
                    "prepareWork", prepared.work, "queryWork", queried.work - prepared.work,
                    "callerWork", queried.work, "callerBytes", queried.bytes)
            }
        }
        print("PASS prepared lifted nonempty SSI, independent cycles, both orders and raw endpoint members after session/input release")
    }
}
