import CADCore
import CADGeometry

@main struct PreparedFiniteProbe {
    typealias Fixture = GeneralBoundedFiniteSphereConeSSIAcceptance
    static func main() throws {
        for index in 0..<3 {
            for reversed in [false, true] {
                var pair = Fixture.input(index)
                let boxes = try Fixture.boxes(index), counter = Fixture.Counter()
                var session: (any OriginalSurfacePairIntersecting)? = try DefaultSurfaceSurfaceIntersector().prepareOriginalPair(
                    first: reversed ? pair.cone : pair.sphere, second: reversed ? pair.sphere : pair.cone,
                    tolerance: .standard, maximumSpanCount: 262_144, maximumSubdivisionDepth: 8,
                    remainingSourceDepth: 1, consumeWork: { try counter.consume() },
                    consumeStorage: { try counter.retain($0) }, maximumAlgebraicDepth: 32)
                let prepared = counter.totals
                var result = try session?.intersectionResult(firstBox: reversed ? boxes.cone : boxes.sphere,
                    secondBox: reversed ? boxes.sphere : boxes.cone, options: .init())
                guard let relation = result?.originalBoundedSphereConeRelation?.original,
                    let receipt = relation.finiteArc, let published = result,
                    published.intersections.count == 1,
                    case .originalBoundedSphereCone(let component) = published.intersections[0] else {
                    throw Fixture.Failure(line: #line)
                }
                try Fixture.require(published.representation == .exactRelation && !relation.isEmpty)
                try Fixture.require(receipt.coneU == 1...2 && receipt.branch == 1 && receipt.imageDimension == 1)
                try Fixture.require(receipt.firstBox == (reversed ? boxes.cone : boxes.sphere))
                try Fixture.require(receipt.secondBox == (reversed ? boxes.sphere : boxes.cone))
                try Fixture.require(!component.isClosed && component.imageDimension == 1 && component.relation === relation)
                try Fixture.require(relation.source.original.sphereIsFirst == !reversed)
                let queried = counter.totals
                try Fixture.require(queried.work > prepared.work && queried.bytes > prepared.bytes)
                try Fixture.require(queried.work <= 8_388_608 && queried.bytes <= 268_435_456)
                var setup = try Fixture.ledger()
                let zero = try OriginalParameterCycle(exact: ExactRationalScalarDomain().integer(0, using: &setup), using: &setup)
                var members: [OriginalBoundedSphereConeSurfaceArcMember] = []
                for u in [1.0, 2.0] {
                    var query = try Fixture.ledger()
                    let raw = try relation.source.original.field.binary64(exactly: u, using: &query)
                    members.append(try component.member(coneU: raw, branch: 1, coneCycle: zero, sphereCycle: zero,
                        limits: Fixture.limits(), using: &query))
                }
                session = nil
                result = nil
                pair = (.analytic(.plane(origin: .origin, normal: .unitX)),
                    .analytic(.plane(origin: .origin, normal: .unitZ)))
                try Fixture.require(pair.sphere != relation.source.original.original.first && pair.cone != relation.source.original.original.second)
                for (member, u) in zip(members, [1.0, 2.0]) {
                    var independent = try Fixture.ledger()
                    try member.admitProof(limits: Fixture.limits(), using: &independent)
                    try Fixture.verify(member, coneU: u, inputIndex: index)
                }
                try Fixture.require(counter.totals.work == queried.work && counter.totals.bytes == queried.bytes)
                print("PASS finite prepared input", index, "reversed", reversed,
                    "prepareWork", prepared.work, "queryWork", queried.work - prepared.work,
                    "callerWork", queried.work, "callerBytes", queried.bytes)
            }
        }
        print("PASS nonempty finite prepared SSI, 3 inputs x both orders, both raw-U endpoints and detached independent member admission")
    }
}
