#if ISSUED_GRAPH_PUBLIC_VERIFICATION
import CADCore
@testable import CADGeometry
#else
import L0
import L1
import L2
import L3
import L4
import L5
import DI0
import DI
import SourceIssuer
import IssuedGraphs
#endif

extension GraphFixtures {
    public static func parameterRefinement() throws {
        let retained = try makeParameterRefinement()
        var a = try ledger()
        let source = retained.pullback.region.partition.source
        let cells = try ExactRealCellDomain<Base>(retaining: source, using: &a)
        let field = try cells.coefficientField(of: source, using: &a)
        let half = try field.binary64(exactly: 0.5, using: &a)
        for numerator in [1,2] {
            let t = try field.dividing(field.integer(numerator, using: &a), field.integer(3, using: &a), using: &a)
            try require(!retained.contains(liftedCoordinates: [t,t,half], limits: limits(),
                rootLimits: .init(maximumRoots: 100), using: &a))
        }
        let roots = try ExactRealRootDomain(field: field, using: &a)
        let ring = roots.polynomials
        let law = try roots.bind(ring.polynomial(terms: [
            .init(powers: [2], coefficient: field.integer(3, using: &a)),
            .init(powers: [0], coefficient: field.integer(-1, using: &a))
        ], using: &a), using: &a)
        let interval = try roots.domain(lower: .finite(field.integer(0, using: &a)),
            upper: .finite(field.integer(1, using: &a)), using: &a)
        let root = try roots.isolate(law, in: interval, limits: .init(maximumRoots: 1), using: &a).roots[0]
        let extensionValue = try field.adjoin(root, using: &a)
        let t = extensionValue.generator
        let extensionHalf = try extensionValue.domain.binary64(exactly: 0.5, using: &a)
        let coordinates = [t,t,extensionHalf]
        let point = try cells.point(field: extensionValue.domain, coordinates: coordinates, using: &a)
        guard let cell = try cells.locate(point, in: retained.pullback.region.partition,
            limits: .init(maximumRoots: 100), using: &a),
            let index = retained.pullback.region.cells.firstIndex(of: cell) else { throw Failure.incorrect(#line) }
        try require(retained.pullback.region.included[index])
        try require(retained.contains(liftedCoordinates: coordinates, queryField: extensionValue.domain,
            limits: limits(), rootLimits: .init(maximumRoots: 100), using: &a))
        let outside = try extensionValue.domain.adding(t, extensionValue.domain.integer(1, using: &a), using: &a)
        try require(!retained.contains(liftedCoordinates: [outside,outside,extensionHalf],
            queryField: extensionValue.domain, limits: limits(), rootLimits: .init(maximumRoots: 100), using: &a))
        let foreignBase = try Base(maximumValueDepth: 32, maximumCoefficientDepth: 32, using: &a)
        let foreignField = try Field.base(field: foreignBase, maximumExtensionLevel: 32, using: &a)
        do {
            _ = try retained.contains(liftedCoordinates: coordinates, queryField: foreignField,
                limits: limits(), rootLimits: .init(maximumRoots: 100), using: &a)
            throw Failure.incorrect(#line)
        } catch NativeExactRelationFailure.cell(.scalar(.incompatibleDomain)) {}
        print("PASS graph refinement descendant-field membership and foreign-field refusal")
        var ordinals = retained.pullback.sourceCellOrdinals
        ordinals.removeAll()
        try require(!retained.pullback.sourceCellOrdinals.isEmpty)
        try require(retained.contains(liftedCoordinates: [half,half,half], limits: limits(),
            rootLimits: .init(maximumRoots: 100), using: &a))
        var checkpoints = try CheckpointAdmission()
        _ = try retained.contains(liftedCoordinates: [half,half,half], limits: limits(),
            rootLimits: .init(maximumRoots: 100), using: &checkpoints)
        var terminal = try CheckpointAdmission(stop: checkpoints.checkpoints)
        do {
            _ = try retained.contains(liftedCoordinates: [half,half,half], limits: limits(),
                rootLimits: .init(maximumRoots: 100), using: &terminal)
            throw Failure.incorrect(#line)
        } catch NativeExactRelationFailure.scalar(.cancelled) {}
        var baseline = try RefinementDepthAdmission()
        try retained.raw.admitProof(limits: limits(), using: &baseline)
        var shallow = try RefinementDepthAdmission(stop: baseline.calls + 1)
        do {
            _ = try retained.contains(liftedCoordinates: [half,half,half], limits: limits(),
                rootLimits: .init(maximumRoots: 100), using: &shallow)
            throw Failure.incorrect(#line)
        } catch NativeExactRelationFailure.scalar(.resourceLimit(.valueDepth)) {}
    }

    static func makeParameterRefinement() throws -> OriginalIssuedGraphParameterRefinement<NativeSnapshot,Law,Cover,NativeSnapshot,Law,Cover> {
        var a = try ledger()
        let base = try Base(maximumValueDepth: 32, maximumCoefficientDepth: 32, using: &a)
        let field = try Field.base(field: base, maximumExtensionLevel: 32, using: &a)
        let l = try limits()
        let input = NativeInput(degrees: [1], knots: [[0,0,1,1]], counts: [2],
            controls: [[0,0.5,0],[1,0.5,0]], weights: [1,1], periodic: [false])
        let nativeCurve = try native(input, base, &a)
        let curveCover = try cover(nativeCurve, &a)
        let first = try DefaultOriginalRationalGraphFamilyPreparer().prepare(
            cover: curveCover, field: field, maximumGraphs: 8, limits: l, using: &a)
        let child = try native(plane(), base, &a)
        let second = try DefaultOriginalRationalGraphFamilyPreparer().prepare(
            cover: cover(child, &a), field: field, maximumGraphs: 8, limits: l, using: &a)
        let raw = try DefaultOriginalIssuedGraphRelationResolver().resolve(kind: .curveSurface,
            first: first, second: second, maximumPairs: 8, limits: l,
            cellLimits: cellLimits(), topologyLimits: topologyLimits(), using: &a)
        let rawSource = raw.pairs[0].relation.projection.original.partition.source
        let cells = try ExactRealCellDomain<Base>(retaining: rawSource, using: &a)
        let ring = cells.polynomials
        let t = try ring.variable(0, using: &a)
        let threeT = try ring.multiplying(t, ring.constant(field.integer(3, using: &a), using: &a), using: &a)
        let source = try cells.bind(polynomials: [
            ring.subtracting(threeT, ring.constant(field.integer(1, using: &a), using: &a), using: &a),
            ring.subtracting(threeT, ring.constant(field.integer(2, using: &a), using: &a), using: &a)
        ], domains: rawSource.domains, using: &a)
        let predicate = try cells.predicate(instructions: [.sign(polynomial: 0, relation: .greater),
            .sign(polynomial: 1, relation: .less), .and], for: source, using: &a)
        let refiner = DefaultOriginalIssuedGraphParameterRefiner<NativeSnapshot,Law,Cover,NativeSnapshot,Law,Cover>()
        var measured = try ledger()
        let result = try refiner.refine(in: raw, pairOrdinal: 0, matching: predicate,
            limits: l, cellLimits: cellLimits(), topologyLimits: topologyLimits(), using: &measured)
        let retained = result
        try require(result.pullback.coordinateMap == [0,1,2])
        for i in result.pullback.region.cells.indices {
            let ordinal = result.pullback.sourceCellOrdinals[i]
            try require(result.pullback.region.included[i] == (ordinal >= 0))
            if ordinal >= 0 { try require(ordinal < raw.pairs[0].relation.projection.original.cells.count) }
        }
        for t in [0.0,0.25,0.5,0.75,1.0] {
            let values = try [field.binary64(exactly: t, using: &a),field.binary64(exactly: t, using: &a),field.binary64(exactly: 0.5, using: &a)]
            var query = try ledger()
            try require(retained.contains(liftedCoordinates: values, limits: l,
                rootLimits: .init(maximumRoots: 100), using: &query) == (t == 0.5))
        }
        var exact = ExactScalarLedger(limits: try .init(work: measured.work, storageBytes: measured.storageBytes,
            valueDepth: 32, coefficientDepth: 32))
        _ = try refiner.refine(in: raw, pairOrdinal: 0, matching: predicate,
            limits: l, cellLimits: cellLimits(), topologyLimits: topologyLimits(), using: &exact)
        for shortage in [true,false] {
            var low = ExactScalarLedger(limits: try .init(work: measured.work - (shortage ? 1:0),
                storageBytes: measured.storageBytes - (shortage ? 0:1), valueDepth: 32, coefficientDepth: 32))
            do {
                _ = try refiner.refine(in: raw, pairOrdinal: 0, matching: predicate,
                    limits: l, cellLimits: cellLimits(), topologyLimits: topologyLimits(), using: &low)
                throw Failure.incorrect(#line)
            } catch NativeExactRelationFailure.scalar(.resourceLimit(let resource)) {
                try require(resource == (shortage ? .work:.storage))
            }
        }
        print("PASS graph refinement exact work/storage boundaries")
        for ordinal in [-1,1] {
            do {
                _ = try refiner.refine(in: raw, pairOrdinal: ordinal, matching: predicate,
                    limits: l, cellLimits: cellLimits(), topologyLimits: topologyLimits(), using: &a)
                throw Failure.incorrect(#line)
            } catch NativeExactRelationFailure.invalidDomain {}
        }
        var checkpoints = try CheckpointAdmission()
        _ = try refiner.refine(in: raw, pairOrdinal: 0, matching: predicate,
            limits: l, cellLimits: cellLimits(), topologyLimits: topologyLimits(), using: &checkpoints)
        for stop in [1,checkpoints.checkpoints] {
            var cancelled = try CheckpointAdmission(stop: stop)
            do {
                _ = try refiner.refine(in: raw, pairOrdinal: 0, matching: predicate,
                    limits: l, cellLimits: cellLimits(), topologyLimits: topologyLimits(), using: &cancelled)
                throw Failure.incorrect(#line)
            } catch NativeExactRelationFailure.scalar(.cancelled) {}
        }
        let offsetSource = try DefaultOriginalSourceBindingIssuer(provider: OffsetProvider()).bind(
            Offset(originalChild: child.source, originalDistance: 0.25), limits: l.source, using: &a)
        let family = try DefaultOriginalFiniteNativeOffsetLawPreparer<Offset>().prepare(
            source: offsetSource, child: child, maximumCharts: 8, limits: l.source, using: &a)
        let issuer = DefaultOriginalNativeOffsetDomainIssuer<Offset>()
        let frame = try issuer.frame(family: family, limits: l, using: &a)
        let offsetCover = try issuer.issue(request: frame.fullSelection(limits: l, using: &a), family: family, limits: l, using: &a)
        let offsetGraph = try DefaultOriginalOffsetGraphFamilyPreparer().prepare(cover: offsetCover,
            field: field, maximumGraphs: 8, limits: l, using: &a)
        let crossing = try DefaultOriginalRationalGraphFamilyPreparer().prepare(
            cover: cover(native(curve(), base, &a), &a), field: field, maximumGraphs: 8, limits: l, using: &a)
        let offsetRaw = try DefaultOriginalIssuedGraphRelationResolver().resolve(kind: .curveSurface,
            first: crossing, second: offsetGraph, maximumPairs: 8, limits: l,
            cellLimits: cellLimits(), topologyLimits: topologyLimits(), using: &a)
        try checkAuxiliaryRefinement(offsetRaw, &a)
        print("MEASURE graph refinement work=\(measured.work) storage=\(measured.storageBytes)")
        return retained
    }

    static func checkAuxiliaryRefinement<S,E,C,T,F,D>(
        _ raw: OriginalIssuedGraphRelations<S,E,C,T,F,D>, _ a: inout ExactScalarLedger
    ) throws {
        let l = try limits()
        let source = raw.pairs[0].relation.projection.original.partition.source
        let cells = try ExactRealCellDomain<Base>(retaining: source, using: &a)
        let field = try cells.coefficientField(of: source, using: &a)
        try require(source.variableCount == 4 && raw.pairs[0].relation.selection.partition.source.variableCount == 3)
        let guarded = try cells.bind(polynomials: [cells.polynomials.variable(3, using: &a)], domains: source.domains, using: &a)
        for positive in [true,false] {
            let predicate = try cells.predicate(instructions: [.sign(polynomial: 0, relation: positive ? .greater:.less)], for: guarded, using: &a)
            let result = try DefaultOriginalIssuedGraphParameterRefiner().refine(in: raw, pairOrdinal: 0,
                matching: predicate, limits: l, cellLimits: cellLimits(), topologyLimits: topologyLimits(), using: &a)
            try require(result.pullback.coordinateMap == [0,1,2,3])
            try require(result.pullback.region.included.contains(true) == positive)
            for q in [-1,1] {
                let values = try [field.binary64(exactly: 0.5, using: &a),field.binary64(exactly: 0.5, using: &a),
                    field.binary64(exactly: 0.5, using: &a),field.integer(q, using: &a)]
                var query = try ledger()
                try require(result.contains(liftedCoordinates: values, limits: l,
                    rootLimits: .init(maximumRoots: 100), using: &query) == (positive && q == 1))
            }
            var shallow = try ledger()
            do {
                _ = try result.contains(liftedCoordinates: [], limits: limits(depth: 0),
                    rootLimits: .init(maximumRoots: 100), using: &shallow)
                throw Failure.incorrect(#line)
            } catch NativeExactRelationFailure.domain(.sourceDepthLimit) {}
        }
        let wrong = try ExactRealCellDomain<Base>(field: field, variableCount: 3, using: &a)
        let wrongSource = try wrong.bind(polynomials: [], domains: Array(source.domains.prefix(3)), using: &a)
        let wrongPredicate = try wrong.predicate(instructions: [.literal(true)], for: wrongSource, using: &a)
        do {
            _ = try DefaultOriginalIssuedGraphParameterRefiner().refine(in: raw, pairOrdinal: 0,
                matching: wrongPredicate, limits: l, cellLimits: cellLimits(), topologyLimits: topologyLimits(), using: &a)
            throw Failure.incorrect(#line)
        } catch NativeExactRelationFailure.invalidDomain {}
    }

    struct RefinementDepthAdmission: ~Copyable, ExactScalarAdmission {
        var ledger: ExactScalarLedger
        var calls = 0
        let stop: Int?
        init(stop: Int? = nil) throws { self.stop = stop; ledger = try GraphFixtures.ledger() }
        mutating func checkpoint() throws(ExactScalarFailure) { try ledger.checkpoint() }
        mutating func consumeWork(_ count: Int) throws(ExactScalarFailure) { try ledger.consumeWork(count) }
        mutating func retainStorage(bytes: Int) throws(ExactScalarFailure) { try ledger.retainStorage(bytes: bytes) }
        mutating func admitDepth(value: Int, coefficient: Int) throws(ExactScalarFailure) {
            calls += 1
            if calls == stop { throw .resourceLimit(.valueDepth) }
            try ledger.admitDepth(value: value, coefficient: coefficient)
        }
        mutating func visitCell(axis: ExactScalarRootAxis, depth: Int) throws(ExactScalarFailure) {
            try ledger.visitCell(axis: axis, depth: depth)
        }
    }
}
