import L0
import L1
import L2
import L3
import L4
import L5
import NativeRefinement

@main
struct NativeConsumerProof {
    typealias Base = ExactRationalScalarDomain
    typealias Field = ExactAlgebraicScalarDomain<Base>
    enum Failure: Error { case incorrect(Int) }
    static func require(_ value: Bool, line: Int = #line) throws {
        guard value else { throw Failure.incorrect(line) }
    }
    static func ledger() throws -> ExactScalarLedger {
        .init(limits: try .init(work: 80_000_000, storageBytes: 700_000_000, valueDepth: 32, coefficientDepth: 32))
    }
    static func main() throws {
        let retained = try run()
        var a = try ledger()
        let source = retained.pullback.region.partition.source
        let cells = try ExactRealCellDomain<Base>(retaining: source, using: &a)
        let field = try cells.coefficientField(of: source, using: &a)
        let half = try field.binary64(exactly: 0.5, using: &a)
        try require(retained.contains(localCoordinates: [half, half, half], rootLimits: .init(maximumRoots: 100), using: &a))
        print("PASS Native refinement membership after source and construction scope release")
    }
    nonisolated static func run() throws -> NativeExactParameterRefinement {
        var a = try ledger()
        let field = try Field.base(field: Base(), maximumExtensionLevel: 32, using: &a)
        let curve = try ExactRealCellDomain<Base>(field: field, variableCount: 1, using: &a)
        let surface = try ExactRealCellDomain<Base>(field: field, variableCount: 2, using: &a)
        let c = curve.polynomials, s = surface.polynomials
        let half = try field.binary64(exactly: 0.5, using: &a)
        let roots = try ExactRealRootDomain(field: field, using: &a)
        let interval = try roots.domain(lower: .finite(field.integer(0, using: &a)),
            upper: .finite(field.integer(1, using: &a)), using: &a)
        let firstSource = try curve.bind(polynomials: [c.variable(0, using: &a), c.constant(half, using: &a),
            c.zero(using: &a), c.constant(field.integer(1, using: &a), using: &a)], domains: [interval], using: &a)
        let secondSource = try surface.bind(polynomials: [s.variable(0, using: &a), s.variable(1, using: &a),
            s.zero(using: &a), s.constant(field.integer(1, using: &a), using: &a)], domains: [interval, interval], using: &a)
        let relations = ExactParametricRelationDomain<Base, ExactRealCellDomain<Base>,
            ExactRealTopologyDomain<Base, ExactRealCellDomain<Base>>>(cells: ExactRealCellDomain<Base>.self,
                topology: .init(cells: ExactRealCellDomain<Base>.self))
        let source = try relations.compile(kind: .curveSurface, first: relations.map(from: firstSource, using: &a),
            second: relations.map(from: secondSource, using: &a), using: &a)
        let cellLimits = try ExactRealCellLimits(maximumStoredCells: 20_000, maximumRootsPerStack: 100)
        let topologyLimits = try ExactRealTopologyLimits(maximumGeneratedCells: 20_000, maximumRootsPerStack: 100,
            maximumClosures: 1_000, maximumAttachmentPieces: 20_000, maximumComponents: 1_000)
        let raw = try relations.resolve(source, cellLimits: cellLimits, topologyLimits: topologyLimits, using: &a)
        let cells = try ExactRealCellDomain<Base>(retaining: source.predicate.source, using: &a)
        let p = cells.polynomials, t = try p.variable(0, using: &a)
        let triple = try p.scaled(t, by: field.integer(3, using: &a), using: &a)
        let conditionSource = try cells.bind(polynomials: [
            p.subtracting(triple, p.constant(field.integer(1, using: &a), using: &a), using: &a),
            p.subtracting(triple, p.constant(field.integer(2, using: &a), using: &a), using: &a)
        ], domains: source.predicate.source.domains, using: &a)
        let predicate = try cells.predicate(instructions: [.sign(polynomial: 0, relation: .greater),
            .sign(polynomial: 1, relation: .less), .and], for: conditionSource, using: &a)
        let refiner = DefaultNativeExactParameterRefiner()
        var measured = try ledger()
        let retained = try refiner.refine(raw, matching: predicate, cellLimits: cellLimits,
            topologyLimits: topologyLimits, using: &measured)
        try require(retained.pullback.coordinateMap == [0, 1, 2])
        for i in retained.pullback.region.cells.indices {
            let ordinal = retained.pullback.sourceCellOrdinals[i]
            try require(retained.pullback.region.included[i] == (ordinal >= 0))
            if ordinal >= 0 { try require(ordinal < raw.selection.cells.count) }
        }
        for numerator in 0...3 {
            let value = try field.dividing(field.integer(numerator, using: &a), field.integer(3, using: &a), using: &a)
            try require(!retained.contains(localCoordinates: [value, value, half], rootLimits: .init(maximumRoots: 100), using: &a))
        }
        var query = try ledger()
        try require(retained.contains(localCoordinates: [half, half, half], rootLimits: .init(maximumRoots: 100), using: &query))
        let law = try roots.bind(roots.polynomials.polynomial(terms: [
            .init(powers: [2], coefficient: field.integer(3, using: &a)),
            .init(powers: [0], coefficient: field.integer(-1, using: &a))], using: &a), using: &a)
        let root = try roots.isolate(law, in: interval, limits: .init(maximumRoots: 1), using: &a).roots[0]
        let extensionValue = try field.adjoin(root, using: &a)
        let x = extensionValue.generator, extensionHalf = try extensionValue.domain.binary64(exactly: 0.5, using: &a)
        try require(retained.contains(localCoordinates: [x, x, extensionHalf], queryField: extensionValue.domain,
            rootLimits: .init(maximumRoots: 100), using: &a))
        let outside = try extensionValue.domain.adding(x, extensionValue.domain.integer(1, using: &a), using: &a)
        try require(!retained.contains(localCoordinates: [outside, outside, extensionHalf], queryField: extensionValue.domain,
            rootLimits: .init(maximumRoots: 100), using: &a))
        let foreign = try Field.base(field: Base(), maximumExtensionLevel: 32, using: &a)
        do {
            _ = try retained.contains(localCoordinates: [x, x, extensionHalf], queryField: foreign,
                rootLimits: .init(maximumRoots: 100), using: &a)
            throw Failure.incorrect(#line)
        } catch NativeExactRelationFailure.cell(.scalar(.incompatibleDomain)) {}
        var exact = ExactScalarLedger(limits: try .init(work: measured.work, storageBytes: measured.storageBytes,
            valueDepth: 32, coefficientDepth: 32))
        _ = try refiner.refine(raw, matching: predicate, cellLimits: cellLimits, topologyLimits: topologyLimits, using: &exact)
        for workShortage in [true, false] {
            var short = ExactScalarLedger(limits: try .init(work: measured.work - (workShortage ? 1 : 0),
                storageBytes: measured.storageBytes - (workShortage ? 0 : 1), valueDepth: 32, coefficientDepth: 32))
            do {
                _ = try refiner.refine(raw, matching: predicate, cellLimits: cellLimits, topologyLimits: topologyLimits, using: &short)
                throw Failure.incorrect(#line)
            } catch NativeExactRelationFailure.scalar(.resourceLimit(let resource)) {
                try require(resource == (workShortage ? .work : .storage))
            }
        }
        var count = try CheckpointAdmission()
        _ = try retained.contains(localCoordinates: [half, half, half], rootLimits: .init(maximumRoots: 100), using: &count)
        for stop in [1, count.checkpoints] {
            var cancelled = try CheckpointAdmission(stop: stop)
            do {
                _ = try retained.contains(localCoordinates: [half, half, half], rootLimits: .init(maximumRoots: 100), using: &cancelled)
                throw Failure.incorrect(#line)
            } catch NativeExactRelationFailure.scalar(.cancelled) {}
        }
        for stop in [1, 2] {
            var shallow = try RefinementDepthAdmission(stop: stop)
            do {
                _ = try retained.contains(localCoordinates: [half, half, half], rootLimits: .init(maximumRoots: 100), using: &shallow)
                throw Failure.incorrect(#line)
            } catch NativeExactRelationFailure.scalar(.resourceLimit(.valueDepth)) {}
        }
        var refinementCheckpoints = try CheckpointAdmission()
        _ = try refiner.refine(raw, matching: predicate, cellLimits: cellLimits, topologyLimits: topologyLimits, using: &refinementCheckpoints)
        for stop in [1, refinementCheckpoints.checkpoints] {
            var cancelled = try CheckpointAdmission(stop: stop)
            do {
                _ = try refiner.refine(raw, matching: predicate, cellLimits: cellLimits, topologyLimits: topologyLimits, using: &cancelled)
                throw Failure.incorrect(#line)
            } catch NativeExactRelationFailure.scalar(.cancelled) {}
        }
        let wrongArity = try curve.predicate(instructions: [.literal(true)], for: firstSource, using: &a)
        do {
            _ = try refiner.refine(raw, matching: wrongArity, cellLimits: cellLimits, topologyLimits: topologyLimits, using: &a)
            throw Failure.incorrect(#line)
        } catch NativeExactRelationFailure.invalidDomain {}
        let falseSource = try cells.bind(polynomials: [], domains: source.predicate.source.domains, using: &a)
        let none = try cells.predicate(instructions: [.literal(false)], for: falseSource, using: &a)
        let empty = try refiner.refine(raw, matching: none, cellLimits: cellLimits, topologyLimits: topologyLimits, using: &a)
        try require(empty.pullback.region.included.allSatisfy { !$0 })
        try require(empty.pullback.sourceCellOrdinals.allSatisfy { $0 == -1 })
        try require(!empty.contains(localCoordinates: [half, half, half], rootLimits: .init(maximumRoots: 100), using: &a))
        var ordinals = retained.pullback.sourceCellOrdinals
        ordinals.removeAll()
        try require(!retained.pullback.sourceCellOrdinals.isEmpty)
        print("PASS current Native retained L5 refinement, algebraic membership, exclusion, field/resource/depth/cancel and COW")
        return retained
    }
}


private struct CheckpointAdmission: ~Copyable, ExactScalarAdmission {
    var ledger: ExactScalarLedger
    var checkpoints = 0
    let stop: Int?
    init(stop: Int? = nil) throws { self.stop = stop; ledger = try NativeConsumerProof.ledger() }
    mutating func checkpoint() throws(ExactScalarFailure) {
        checkpoints += 1
        if checkpoints == stop { throw .cancelled }
        try ledger.checkpoint()
    }
    mutating func consumeWork(_ n: Int) throws(ExactScalarFailure) { try ledger.consumeWork(n) }
    mutating func retainStorage(bytes: Int) throws(ExactScalarFailure) { try ledger.retainStorage(bytes: bytes) }
    mutating func admitDepth(value: Int, coefficient: Int) throws(ExactScalarFailure) { try ledger.admitDepth(value: value, coefficient: coefficient) }
    mutating func visitCell(axis: ExactScalarRootAxis, depth: Int) throws(ExactScalarFailure) { try ledger.visitCell(axis: axis, depth: depth) }
}

private struct RefinementDepthAdmission: ~Copyable, ExactScalarAdmission {
    var ledger: ExactScalarLedger
    var calls = 0
    let stop: Int
    init(stop: Int) throws { self.stop = stop; ledger = try NativeConsumerProof.ledger() }
    mutating func checkpoint() throws(ExactScalarFailure) { try ledger.checkpoint() }
    mutating func consumeWork(_ n: Int) throws(ExactScalarFailure) { try ledger.consumeWork(n) }
    mutating func retainStorage(bytes: Int) throws(ExactScalarFailure) { try ledger.retainStorage(bytes: bytes) }
    mutating func admitDepth(value: Int, coefficient: Int) throws(ExactScalarFailure) {
        calls += 1
        if calls == stop { throw .resourceLimit(.valueDepth) }
        try ledger.admitDepth(value: value, coefficient: coefficient)
    }
    mutating func visitCell(axis: ExactScalarRootAxis, depth: Int) throws(ExactScalarFailure) { try ledger.visitCell(axis: axis, depth: depth) }
}
