import Testing
import L0
import L1
import L2
import L3
import L4
import L5
import L6

private typealias B = ExactRationalScalarDomain
private typealias F = ExactAlgebraicScalarDomain<B>
private typealias C = ExactRealCellDomain<B>
private func limits() throws -> ExactRealTopologyLimits {
    try .init(maximumGeneratedCells: 30_000, maximumRootsPerStack: 100,
              maximumClosures: 1000, maximumAttachmentPieces: 30_000, maximumComponents: 1000)
}
private func ledger() throws -> ExactScalarLedger {
    .init(limits: try .init(work: 80_000_000, storageBytes: 1_073_741_824, valueDepth: 400, coefficientDepth: 400))
}
private func interval(_ field: F, _ a: inout ExactScalarLedger) throws -> ExactRealRootInterval<F.Value> {
    let r = try ExactRealRootDomain(field: field, using: &a)
    return try r.domain(lower: .finite(field.integer(-2, using: &a)), upper: .finite(field.integer(2, using: &a)), using: &a)
}
private func fixture(_ sector: Bool, _ a: inout ExactScalarLedger) throws -> (C, ExactRealCellSelection<B>, ExactRealCellPredicate<B>) {
    let f = try F.base(field: B(), maximumExtensionLevel: 10, using: &a)
    let c = try C(field: f, variableCount: 1, using: &a), p = c.polynomials
    let x = try p.variable(0, using: &a)
    let law = try p.subtracting(p.multiplying(x, x, using: &a), p.constant(f.integer(1, using: &a), using: &a), using: &a)
    let box = try interval(f, &a)
    let s = try c.bind(polynomials: [law], domains: [box], using: &a)
    let predicate = try c.predicate(instructions: [.sign(polynomial: 0, relation: sector ? .greater : .equal)], for: s, using: &a)
    let partition = try c.decompose(s, limits: .init(maximumStoredCells: 1000, maximumRootsPerStack: 100), using: &a)
    let selection = try c.select(partition, matching: predicate, using: &a)
    let t = try C(field: f, variableCount: 2, using: &a), q = t.polynomials
    let y = try q.variable(0, using: &a), tx = try q.variable(1, using: &a)
    let image = sector ? tx : try q.multiplying(tx, tx, using: &a)
    let graph = try q.subtracting(y, image, using: &a)
    let target = try t.bind(polynomials: [graph], domains: [box, box], using: &a)
    return (c, selection, try t.predicate(instructions: [.sign(polynomial: 0, relation: .equal)], for: target, using: &a))
}

@Test(.timeLimit(.minutes(2))) func transportsDifferentRootsAfterCoordinateReordering() throws {
    var a = try ledger()
    let (c, source, target) = try fixture(false, &a)
    let map = [1]
    let r = try ExactRealTopology<B>(cells: C.self).refinePullback(of: source, onto: target,
        coordinateMap: map, cellLimits: .init(maximumStoredCells: 30_000, maximumRootsPerStack: 100),
        topologyLimits: limits(), using: &a)
    #expect(r.region.coordinateCount == 2)
    #expect(r.region.included.filter { $0 }.count == 2)
    let tc = try C(retaining: r.region.partition.source, using: &a)
    for i in r.region.cells.indices where r.region.included[i] {
        let sourceCell = source.cells[r.sourceCellOrdinals[i]]
        let s = try c.sample(of: sourceCell, in: source.partition, using: &a)
        let t = try tc.sample(of: r.region.cells[i], in: r.region.partition, using: &a)
        #expect(t.coordinates.count == 2)
        #expect(r.region.cells[i].dimension == 0)
        #expect(try s.field.sign(of: s.coordinates[0], using: &a) == t.field.sign(of: t.coordinates[1], using: &a))
        #expect(try t.field.sign(of: t.coordinates[0], using: &a) == .positive)
    }
}

@Test(.timeLimit(.minutes(2))) func thomBoundaryOrderAvoidsWitnessDimensionInflation() throws {
    var a = try ledger()
    let (_, source, target) = try fixture(true, &a)
    let map = [1]
    let r = try ExactRealTopology<B>(cells: C.self).refinePullback(of: source, onto: target,
        coordinateMap: map, cellLimits: .init(maximumStoredCells: 30_000, maximumRootsPerStack: 100),
        topologyLimits: limits(), using: &a)
    #expect(r.region.coordinateCount == 2)
    #expect(r.region.partition.source.variableCount == r.region.coordinateCount)
    #expect(r.region.included.contains(true))
    for i in r.region.cells.indices where r.region.included[i] {
        #expect(r.region.cells[i].axis == 1)
        #expect(r.region.cells[i].dimension <= 1)
        #expect(r.sourceCellOrdinals[i] >= 0)
    }
}

@Test func rejectsInvalidCoordinateProjectionBeforePublication() throws {
    var a = try ledger()
    let (_, source, target) = try fixture(false, &a)
    let map = [2]
    #expect(throws: ExactRealTopologyFailure.self) {
        try ExactRealTopology<B>(cells: C.self).refinePullback(of: source, onto: target,
            coordinateMap: map, cellLimits: .init(maximumStoredCells: 30_000, maximumRootsPerStack: 100),
            topologyLimits: limits(), using: &a)
    }
}

@Test(.timeLimit(.minutes(2))) func thomOrderHandlesRepeatedRootsAndNegativeLeadingSigns() throws {
    for negative in [false, true] {
        var a = try ledger()
        let f = try F.base(field: B(), maximumExtensionLevel: 10, using: &a)
        let c = try C(field: f, variableCount: 1, using: &a), p = c.polynomials
        let x = try p.variable(0, using: &a), one = try p.constant(f.integer(1, using: &a), using: &a)
        let factor = try p.subtracting(x, one, using: &a)
        var law = try p.multiplying(factor, factor, using: &a)
        if negative { law = try p.multiplying(law, p.constant(f.integer(-1, using: &a), using: &a), using: &a) }
        let box = try interval(f, &a)
        let s = try c.bind(polynomials: [law], domains: [box], using: &a)
        let pred = try c.predicate(instructions: [.sign(polynomial: 0, relation: .notEqual)], for: s, using: &a)
        let partition = try c.decompose(s, limits: .init(maximumStoredCells: 1000, maximumRootsPerStack: 100), using: &a)
        let source = try c.select(partition, matching: pred, using: &a)
        let t = try C(field: f, variableCount: 2, using: &a), q = t.polynomials
        let graph = try q.subtracting(q.variable(0, using: &a), q.variable(1, using: &a), using: &a)
        let ts = try t.bind(polynomials: [graph], domains: [box, box], using: &a)
        let target = try t.predicate(instructions: [.sign(polynomial: 0, relation: .equal)], for: ts, using: &a)
        let r = try ExactRealTopology<B>(cells: C.self).refinePullback(of: source, onto: target,
            coordinateMap: [1], cellLimits: .init(maximumStoredCells: 30_000, maximumRootsPerStack: 100),
            topologyLimits: limits(), using: &a)
        let rc = try C(retaining: r.region.partition.source, using: &a)
        for i in r.region.cells.indices where r.region.included[i] {
            let sample = try rc.sample(of: r.region.cells[i], in: r.region.partition, using: &a)
            #expect(try sample.field.compare(sample.coordinates[0], sample.field.integer(1, using: &a), using: &a) != .equal)
        }
        #expect(r.region.included.contains(true))
    }
}

@Test(.timeLimit(.minutes(2))) func transportedRootIdentityRetainsChangingMultiplicityAtEndpoint() throws {
    var a = try ledger()
    let f = try F.base(field: B(), maximumExtensionLevel: 10, using: &a)
    let c = try C(field: f, variableCount: 2, using: &a), p = c.polynomials
    let u = try p.variable(0, using: &a), v = try p.variable(1, using: &a)
    let law = try p.subtracting(p.multiplying(v, v, using: &a), u, using: &a)
    let roots = try ExactRealRootDomain(field: f, using: &a)
    let unit = try roots.domain(lower: .finite(f.integer(0, using: &a)), upper: .finite(f.integer(1, using: &a)), using: &a)
    let box = try interval(f, &a)
    let s = try c.bind(polynomials: [law, v], domains: [unit, box], using: &a)
    let predicate = try c.predicate(instructions: [.sign(polynomial: 0, relation: .equal), .sign(polynomial: 1, relation: .greaterOrEqual), .and], for: s, using: &a)
    let partition = try c.decompose(s, limits: .init(maximumStoredCells: 1000, maximumRootsPerStack: 100), using: &a)
    let source = try c.select(partition, matching: predicate, using: &a)
    let t = try C(field: f, variableCount: 2, using: &a)
    let ts = try t.bind(polynomials: [], domains: [box, unit], using: &a)
    let target = try t.predicate(instructions: [.literal(true)], for: ts, using: &a)
    let r = try ExactRealTopology<B>(cells: C.self).refinePullback(of: source, onto: target,
        coordinateMap: [1,0], cellLimits: .init(maximumStoredCells: 30_000, maximumRootsPerStack: 100),
        topologyLimits: limits(), using: &a)
    let rc = try C(retaining: r.region.partition.source, using: &a)
    #expect(r.region.included.contains(true))
    for i in r.region.cells.indices where r.region.included[i] {
        let sample = try rc.sample(of: r.region.cells[i], in: r.region.partition, using: &a)
        #expect(try sample.field.sign(of: sample.coordinates[0], using: &a) != .negative)
        let pnt = try c.point(field: sample.field, coordinates: [sample.coordinates[1], sample.coordinates[0]], using: &a)
        let original = try c.locate(pnt, in: source.partition, limits: .init(maximumRoots: 100), using: &a)
        #expect(original == source.cells[r.sourceCellOrdinals[i]])
    }
}
