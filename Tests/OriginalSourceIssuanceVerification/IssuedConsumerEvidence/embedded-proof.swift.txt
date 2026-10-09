import L0
import L1
import SourceIssuer
import DI0
import DI
#if SOURCE_ISSUED_MAP_ISOLATED_VERIFICATION
import L2
import L3
import L4
import L5
import IssuedMaps
#if hasFeature(Embedded)
import OriginalCoordinateTransfer
#endif
#endif

enum DomainProofFailure: Error { case incorrect(Int) }
func require(_ condition: Bool, line: Int = #line) throws {
    guard condition else { throw DomainProofFailure.incorrect(line) }
}

@main struct DomainProof {
    static func main() throws { try run() }
    nonisolated static func run() throws {
        var a = ExactScalarLedger(limits: try .init(work: 20_000_000, storageBytes: 134_217_728,
            valueDepth: 32, coefficientDepth: 32))
        let f = try OriginalExactScalarDomain(maximumValueDepth: 32, maximumCoefficientDepth: 32, using: &a)
        let limits = try OriginalDomainIdentityLimits(source: .init(remainingSourceDepth: 1),
            maximumTransportDepth: 3, maximumCharts: 8, maximumFamilies: 0, maximumIdentityProofs: 0)
        let input = NativeInput(degrees: [1], knots: [[0,0,1,2,2]], counts: [3],
            controls: [[0,0,0],[1,0,0],[2,0,0]], weights: [1,2,1], periodic: [false])
        let source = try DefaultOriginalSourceBindingIssuer(provider: NativeProvider()).bind(input,
            limits: limits.source, using: &a)
        let zero = try f.integer(0, using: &a), one = try f.integer(1, using: &a), two = try f.integer(2, using: &a)
        let depth = try ExactScalarDepth(value: 0, coefficient: 0)
        let full = try ExactParameterInterval.checked(field: f, lower: .finite(zero), upper: .finite(two), depth: depth, using: &a)
        let frame = try DefaultOriginalParameterTransporter<NativeSnapshot, OriginalExactScalarDomain>().frame(
            source: source, field: f, support: [[full]], semantics: [.authoredScalar], limits: limits, using: &a)
        let issued = try DefaultOriginalFiniteBSplineChartPreparer<NativeSnapshot>().prepare(source: source,
            field: f, maximumCharts: 8, limits: limits.source, using: &a)
        let laws = issued.laws
        try require(laws.count == 2 && issued.support.count == 1)
        try require(try f.compare(issued.support[0].lower, zero, using: &a) == .equal &&
            f.compare(issued.support[0].upper, two, using: &a) == .equal)
        let binder = DefaultOriginalIssuedDomainBinder<NativeSnapshot, OriginalBSplineChartSelection, OriginalExactScalarDomain>()
        let request = try frame.fullSelection(limits: limits, using: &a)
        var measured = ExactScalarLedger(limits: try .init(work: 20_000_000, storageBytes: 134_217_728,
            valueDepth: 32, coefficientDepth: 32))
        let cover = try binder.bind(laws: laws, request: request, limits: limits, using: &measured)
#if SOURCE_ISSUED_MAP_ISOLATED_VERIFICATION
        let coefficientField = try ExactAlgebraicScalarDomain.base(field: f,
            maximumExtensionLevel: 32, using: &a)
        let compiler = DefaultOriginalIssuedMapCompiler<NativeSnapshot, OriginalBSplineChartSelection>()
        let prepared = try compiler.compile(cover: cover, field: coefficientField, maximumMaps: 8, using: &a)
        try require(prepared.maps.count == 2 && prepared.maps[0].chartIndex == 0 && prepared.maps[1].chartIndex == 1)
        for index in prepared.maps.indices {
            let map = prepared.maps[index].map, law = cover.laws[cover.charts[index].lawIndex]
            let mapRing = try ExactPolynomialDomain(retaining: map.original.polynomials[0], using: &a)
            let t = try f.binary64(exactly: index == 0 ? 0.5 : 1.5, using: &a)
            let coordinate = try coefficientField.importingBase(t, using: &a)
            for axis in 0..<4 {
                let original = try law.polynomials.evaluated(law.homogeneous[axis], at: [t], using: &a)
                let compiled = try mapRing.evaluated(map.original.polynomials[axis], at: [coordinate], using: &a)
                try require(try coefficientField.compare(compiled.value,
                    coefficientField.importingBase(original.value, using: &a), using: &a) == .equal)
            }
        }
        do {
            _ = try compiler.compile(cover: cover, field: coefficientField, maximumMaps: 1, using: &a)
            throw DomainProofFailure.incorrect(#line)
        } catch NativeExactRelationFailure.domain(.chartLimit) {}
#endif
        try require(cover.charts.count == 2 && cover.charts.map { $0.lawIndex } == [0,1])
        try require(source.owns(cover.laws[0].chart) && source.owns(cover.laws[1].chart))
        let singleton = try ExactParameterInterval.checked(field: f, lower: .finite(one), upper: .finite(one), depth: depth, using: &a)
        let selected = try frame.selection(intervals: [[singleton]], limits: limits, using: &a)
        let seam = try binder.bind(laws: laws, request: selected, limits: limits, using: &a)
        try require(seam.charts.count == 2)
        for chart in seam.charts {
            let axis = chart.selectedLocal.axes[0].intervals[0]
            guard case .finite(let lower) = axis.lower, case .finite(let upper) = axis.upper else {
                throw DomainProofFailure.incorrect(#line)
            }
            try require(try f.compare(lower, one, using: &a) == .equal && f.compare(upper, one, using: &a) == .equal)
        }
        do {
            _ = try binder.bind(laws: [laws[0]], request: request, limits: limits, using: &a)
            throw DomainProofFailure.incorrect(#line)
        } catch OriginalDomainIdentityFailure.incompleteCoverage {}
        let outside = try ExactParameterInterval.checked(field: f, lower: .finite(f.integer(3, using: &a)),
            upper: .finite(f.integer(4, using: &a)), depth: depth, using: &a)
        let excluded = try frame.selection(intervals: [[outside]], limits: limits, using: &a)
        let empty = try binder.bind(laws: [], request: excluded, limits: limits, using: &a)
        try require(empty.coverage.effective.isEmpty && empty.charts.isEmpty)
        var exact = ExactScalarLedger(limits: try .init(work: measured.work, storageBytes: measured.storageBytes,
            valueDepth: 32, coefficientDepth: 32))
        _ = try binder.bind(laws: laws, request: request, limits: limits, using: &exact)
        var cancelled = ExactScalarLedger(limits: try .init(work: 20_000_000, storageBytes: 134_217_728,
            valueDepth: 32, coefficientDepth: 32)); cancelled.cancel()
        do {
            _ = try binder.bind(laws: laws, request: request, limits: limits, using: &cancelled)
            throw DomainProofFailure.incorrect(#line)
        } catch OriginalDomainIdentityFailure.scalar(.cancelled) {}
        let surfaceInput = NativeInput(degrees: [1,1], knots: [[0,0,1,1],[0,0,1,1]], counts: [2,2],
            controls: [[0,0,0],[1,0,0],[0,1,0],[1,1,0]], weights: [1,2,3,4], periodic: [false,false])
        let surface = try DefaultOriginalSourceBindingIssuer(provider: NativeProvider()).bind(surfaceInput,
            limits: limits.source, using: &a)
        let unit = try ExactParameterInterval.checked(field: f, lower: .finite(zero), upper: .finite(one), depth: depth, using: &a)
        let surfaceFrame = try DefaultOriginalParameterTransporter<NativeSnapshot, OriginalExactScalarDomain>().frame(
            source: surface, field: f, support: [[unit],[unit]], semantics: [.authoredScalar,.authoredScalar], limits: limits, using: &a)
        let surfaceChart = try surface.chart(OriginalBSplineChartSelection(spans: [1,1]), limits: limits.source, using: &a)
        let surfaceLaw = try DefaultOriginalBSplineChartIssuer<NativeSnapshot, OriginalExactScalarDomain>().issue(
            source: surface, chart: surfaceChart, field: f, limits: limits.source, using: &a)
        let left = try ExactParameterInterval.checked(field: f, lower: .finite(zero),
            upper: .finite(f.binary64(exactly: 0.25, using: &a)), depth: depth, using: &a)
        let right = try ExactParameterInterval.checked(field: f, lower: .finite(f.binary64(exactly: 0.75, using: &a)),
            upper: .finite(one), depth: depth, using: &a)
        let half = try f.binary64(exactly: 0.5, using: &a)
        let fixed = try ExactParameterInterval.checked(field: f, lower: .finite(half), upper: .finite(half), depth: depth, using: &a)
        let surfaceRequest = try surfaceFrame.selection(intervals: [[left,right],[fixed]], limits: limits, using: &a)
        let surfaceCover = try binder.bind(laws: [surfaceLaw], request: surfaceRequest, limits: limits, using: &a)
        try require(surfaceCover.charts.count == 1 && surfaceCover.charts[0].selectedLocal.axes[0].intervalCount == 2)
#if SOURCE_ISSUED_MAP_ISOLATED_VERIFICATION
        let surfacePrepared = try compiler.compile(cover: surfaceCover, field: coefficientField, maximumMaps: 8, using: &a)
        try require(surfacePrepared.maps.count == 2 && surfacePrepared.maps.allSatisfy { $0.map.parameterCount == 2 })
        let relationDomain = ExactParametricRelationDomain<OriginalExactScalarDomain,
            ExactRealCellDomain<OriginalExactScalarDomain>, ExactRealTopology<OriginalExactScalarDomain>>(
                cells: ExactRealCellDomain<OriginalExactScalarDomain>.self,
                topology: .init(cells: ExactRealCellDomain<OriginalExactScalarDomain>.self))
        let compiledPair = try relationDomain.compile(kind: .curveSurface, first: prepared.maps[0].map,
            second: surfacePrepared.maps[0].map, using: &a)
        let pairRing = try ExactPolynomialDomain(retaining: compiledPair.rawEquations[0], using: &a)
        let h = try coefficientField.importingBase(half, using: &a)
        let z = try coefficientField.integer(0, using: &a)
        for equation in compiledPair.rawEquations {
            try require(try coefficientField.sign(of: pairRing.evaluated(equation, at: [h,h,z], using: &a).value,
                using: &a) == .zero)
        }
        for guardLaw in compiledPair.predicate.source.polynomials.suffix(2) {
            try require(try coefficientField.sign(of: pairRing.evaluated(guardLaw, at: [h,h,z], using: &a).value,
                using: &a) != .zero)
        }
        let compiledEmpty = try compiler.compile(cover: empty, field: coefficientField, maximumMaps: 0, using: &a)
        try require(compiledEmpty.maps.isEmpty && compiledEmpty.original.coverage.effective.isEmpty)
#endif
#if SOURCE_ISSUED_MAP_ISOLATED_VERIFICATION
        let planeInput = NativeInput(degrees: [1,1], knots: [[0,0,1,1],[0,0,1,1]], counts: [2,2],
            controls: [[0,0,0],[1,0,0],[0,1,0],[1,1,0]], weights: [1,1,1,1], periodic: [false,false])
        let planeSource = try DefaultOriginalSourceBindingIssuer(provider: NativeProvider()).bind(planeInput,
            limits: limits.source, using: &a)
        let planeFrame = try DefaultOriginalParameterTransporter<NativeSnapshot, OriginalExactScalarDomain>().frame(
            source: planeSource, field: f, support: [[unit],[unit]], semantics: [.authoredScalar,.authoredScalar], limits: limits, using: &a)
        let planeLaws = try DefaultOriginalFiniteBSplineChartPreparer<NativeSnapshot>().prepare(source: planeSource,
            field: f, maximumCharts: 8, limits: limits.source, using: &a)
        let planeCover = try binder.bind(laws: planeLaws.laws, request: planeFrame.fullSelection(limits: limits, using: &a),
            limits: limits, using: &a)
        let planeMap = try compiler.compile(cover: planeCover, field: coefficientField, maximumMaps: 8, using: &a)
        let verticalInput = NativeInput(degrees: [1], knots: [[0,0,1,1]], counts: [2],
            controls: [[0.5,0.5,-0.5],[0.5,0.5,0.5]], weights: [1,1], periodic: [false])
        let verticalSource = try DefaultOriginalSourceBindingIssuer(provider: NativeProvider()).bind(verticalInput,
            limits: limits.source, using: &a)
        // Rational output must retain both causal depth axes of the original request.
        let tupleDomainUnit = try unit.retainingDepth(.init(value: 2, coefficient: 3), using: &a)
        let verticalFrame = try DefaultOriginalParameterTransporter<NativeSnapshot, OriginalExactScalarDomain>().frame(
            source: verticalSource, field: f, support: [[tupleDomainUnit]], semantics: [.authoredScalar], limits: limits, using: &a)
        let verticalLaws = try DefaultOriginalFiniteBSplineChartPreparer<NativeSnapshot>().prepare(source: verticalSource,
            field: f, maximumCharts: 8, limits: limits.source, using: &a)
        let verticalCover = try binder.bind(laws: verticalLaws.laws, request: verticalFrame.fullSelection(limits: limits, using: &a),
            limits: limits, using: &a)
        let verticalMap = try compiler.compile(cover: verticalCover, field: coefficientField, maximumMaps: 8, using: &a)
        let resolver = DefaultOriginalIssuedRelationResolver<NativeSnapshot, OriginalBSplineChartSelection,
            NativeSnapshot, OriginalBSplineChartSelection>()
        let cellLimits = try ExactRealCellLimits(maximumStoredCells: 2048, maximumRootsPerStack: 32)
        let topologyLimits = try ExactRealTopologyLimits(maximumGeneratedCells: 2048, maximumRootsPerStack: 32,
            maximumClosures: 128, maximumAttachmentPieces: 256, maximumComponents: 32)
        var resolveBudget = ExactScalarLedger(limits: try .init(work: 20_000_000, storageBytes: 134_217_728,
            valueDepth: 32, coefficientDepth: 32))
        let isolated = try resolver.resolve(kind: .curveSurface, first: verticalMap, second: planeMap,
            maximumPairs: 8, maximumIsolatedCells: 8, requireDiscrete: true, cellLimits: cellLimits,
            topologyLimits: topologyLimits, using: &resolveBudget)
        try require(isolated.pairs.count == 1 && isolated.isolatedCellCount == 1 && !isolated.hasPositiveDimensionalSolutions)
        let relation = isolated.pairs[0].relation
        guard let selectedCell = relation.selection.cells.first else { throw DomainProofFailure.incorrect(#line) }
        let relationCells = try ExactRealCellDomain(retaining: relation.original.predicate.source, using: &a)
        let sample = try relationCells.sample(of: selectedCell, in: relation.selection.partition, using: &a)
        for value in sample.coordinates {
            try require(try sample.field.compare(value, sample.field.importingBase(half, using: &a), using: &a) == .equal)
        }
        let tupleResolver = DefaultOriginalIssuedCurveSurfacePointResolver<NativeSnapshot, OriginalBSplineChartSelection,
            NativeSnapshot, OriginalBSplineChartSelection>()
        var tupleBudget = ExactScalarLedger(limits: try .init(work: 20_000_000, storageBytes: 134_217_728,
            valueDepth: 32, coefficientDepth: 32))
        let originalPoints = try tupleResolver.resolve(relation: isolated, maximumPoints: 8, using: &tupleBudget)
        try require(originalPoints.points.count == 1 && originalPoints.incidences.count == 1)
        try require(originalPoints.proofDepth.value >= max(2, relation.components.depth.value) &&
            originalPoints.proofDepth.coefficient >= max(3, relation.components.depth.coefficient))
        var exactTupleBudget = ExactScalarLedger(limits: try .init(work: tupleBudget.work,
            storageBytes: tupleBudget.storageBytes, valueDepth: tupleBudget.valueDepth, coefficientDepth: tupleBudget.coefficientDepth))
        _ = try tupleResolver.resolve(relation: isolated, maximumPoints: 8, using: &exactTupleBudget)
        for resource in [ExactResource.work, .storage, .valueDepth, .coefficientDepth] {
            let used = resource == .work ? tupleBudget.work : resource == .storage ? tupleBudget.storageBytes :
                resource == .valueDepth ? tupleBudget.valueDepth : tupleBudget.coefficientDepth
            guard used > 0 else { throw DomainProofFailure.incorrect(#line) }
            var low = ExactScalarLedger(limits: try .init(work: tupleBudget.work - (resource == .work ? 1 : 0),
                storageBytes: tupleBudget.storageBytes - (resource == .storage ? 1 : 0),
                valueDepth: tupleBudget.valueDepth - (resource == .valueDepth ? 1 : 0),
                coefficientDepth: tupleBudget.coefficientDepth - (resource == .coefficientDepth ? 1 : 0)))
            do { _ = try tupleResolver.resolve(relation: isolated, maximumPoints: 8, using: &low)
                throw DomainProofFailure.incorrect(#line)
            } catch NativeExactRelationFailure.scalar(.resourceLimit(let exhausted)) { try require(exhausted == resource) }
            catch NativeExactRelationFailure.cell(.scalar(.resourceLimit(let exhausted))) { try require(exhausted == resource) }
            catch NativeExactRelationFailure.root(.scalar(.resourceLimit(let exhausted))) { try require(exhausted == resource) }
        }
        var cancelledTuple = ExactScalarLedger(limits: try .init(work: tupleBudget.work,
            storageBytes: tupleBudget.storageBytes, valueDepth: 32, coefficientDepth: 32))
        cancelledTuple.cancel()
        do { _ = try tupleResolver.resolve(relation: isolated, maximumPoints: 8, using: &cancelledTuple)
            throw DomainProofFailure.incorrect(#line)
        } catch NativeExactRelationFailure.scalar(.cancelled) {}
        let tuple = originalPoints.points[0], originalField = originalPoints.coordinates.field
        for value in [tuple.t, tuple.u, tuple.v] {
            try require(try originalField.compare(value, originalField.binary64(exactly: 0.5, using: &a), using: &a) == .equal)
        }
        do { _ = try tupleResolver.resolve(relation: isolated, maximumPoints: 0, using: &a)
            throw DomainProofFailure.incorrect(#line)
        } catch NativeExactRelationFailure.resultLimit {}
        func preparedCurve(_ input: NativeInput, _ ledger: inout ExactScalarLedger) throws -> OriginalIssuedMapPreparation<NativeSnapshot, OriginalBSplineChartSelection> {
            let bound = try DefaultOriginalSourceBindingIssuer(provider: NativeProvider()).bind(input, limits: limits.source, using: &ledger)
            let issued = try DefaultOriginalFiniteBSplineChartPreparer<NativeSnapshot>().prepare(source: bound, field: f,
                maximumCharts: 8, limits: limits.source, using: &ledger)
            let low = try f.binary64(exactly: input.knots[0][input.degrees[0]], using: &ledger)
            let high = try f.binary64(exactly: input.knots[0][input.counts[0]], using: &ledger)
            let range = try ExactParameterInterval.checked(field: f, lower: .finite(low), upper: .finite(high), depth: depth, using: &ledger)
            let original = try DefaultOriginalParameterTransporter<NativeSnapshot, OriginalExactScalarDomain>().frame(
                source: bound, field: f, support: [[range]], semantics: [.authoredScalar], limits: limits, using: &ledger)
            let cover = try binder.bind(laws: issued.laws, request: original.fullSelection(limits: limits, using: &ledger), limits: limits, using: &ledger)
            return try compiler.compile(cover: cover, field: coefficientField, maximumMaps: 8, using: &ledger)
        }
        let algebraicInput = NativeInput(degrees: [2], knots: [[0,0,0,1,1,1]], counts: [3],
            controls: [[0.5,0.5,-0.5],[0.5,0.5,-0.5],[0.5,0.5,0.5]], weights: [1,1,1], periodic: [false])
        var algebraicBudget = ExactScalarLedger(limits: try .init(work: 20_000_000, storageBytes: 134_217_728, valueDepth: 32, coefficientDepth: 32))
        let algebraicMap = try preparedCurve(algebraicInput, &algebraicBudget)
        let algebraicRelation = try resolver.resolve(kind: .curveSurface, first: algebraicMap, second: planeMap,
            maximumPairs: 8, maximumIsolatedCells: 8, requireDiscrete: true, cellLimits: cellLimits,
            topologyLimits: topologyLimits, using: &algebraicBudget)
        let algebraicPoints = try tupleResolver.resolve(relation: algebraicRelation, maximumPoints: 8, using: &algebraicBudget)
        try require(algebraicPoints.points.count == 1)
        let af = algebraicPoints.coordinates.field, at = algebraicPoints.points[0].t
        try require(try af.compare(af.multiplying(at, at, using: &algebraicBudget),
            af.binary64(exactly: 0.5, using: &algebraicBudget), using: &algebraicBudget) == .equal)
        let seamInput = NativeInput(degrees: [1], knots: [[0,0,1,2,2]], counts: [3],
            controls: [[0.5,0.5,-1],[0.5,0.5,0],[0.5,0.5,1]], weights: [1,1,1], periodic: [false])
        var seamBudget = ExactScalarLedger(limits: try .init(work: 20_000_000, storageBytes: 134_217_728, valueDepth: 32, coefficientDepth: 32))
        let seamMap = try preparedCurve(seamInput, &seamBudget)
        let seamRelation = try resolver.resolve(kind: .curveSurface, first: seamMap, second: planeMap,
            maximumPairs: 8, maximumIsolatedCells: 8, requireDiscrete: true, cellLimits: cellLimits,
            topologyLimits: topologyLimits, using: &seamBudget)
        let seamPoints = try tupleResolver.resolve(relation: seamRelation, maximumPoints: 1, using: &seamBudget)
        try require(seamPoints.points.count == 1 && seamPoints.incidences.count == 2 && seamPoints.points[0].incidenceRange.count == 2)
        try require(try seamPoints.coordinates.field.compare(seamPoints.points[0].t,
            seamPoints.coordinates.field.integer(1, using: &seamBudget), using: &seamBudget) == .equal)
        let foldedInput = NativeInput(degrees: [2,1], knots: [[0,0,0,1,1,1],[0,0,1,1]], counts: [3,2],
            controls: [[1,0,0],[-1,0,0],[1,0,0],[1,1,0],[-1,1,0],[1,1,0]], weights: [1,1,1,1,1,1], periodic: [false,false])
        var foldedBudget = ExactScalarLedger(limits: try .init(work: 20_000_000, storageBytes: 134_217_728, valueDepth: 32, coefficientDepth: 32))
        let foldedSource = try DefaultOriginalSourceBindingIssuer(provider: NativeProvider()).bind(foldedInput, limits: limits.source, using: &foldedBudget)
        let foldedLaws = try DefaultOriginalFiniteBSplineChartPreparer<NativeSnapshot>().prepare(source: foldedSource, field: f,
            maximumCharts: 8, limits: limits.source, using: &foldedBudget)
        let foldedFrame = try DefaultOriginalParameterTransporter<NativeSnapshot, OriginalExactScalarDomain>().frame(
            source: foldedSource, field: f, support: [[unit],[unit]], semantics: [.authoredScalar,.authoredScalar], limits: limits, using: &foldedBudget)
        let foldedCover = try binder.bind(laws: foldedLaws.laws, request: foldedFrame.fullSelection(limits: limits, using: &foldedBudget), limits: limits, using: &foldedBudget)
        let foldedMap = try compiler.compile(cover: foldedCover, field: coefficientField, maximumMaps: 8, using: &foldedBudget)
        let foldCurve = NativeInput(degrees: [1], knots: [[0,0,1,1]], counts: [2],
            controls: [[0.25,0.5,-0.5],[0.25,0.5,0.5]], weights: [1,1], periodic: [false])
        let foldCurveMap = try preparedCurve(foldCurve, &foldedBudget)
        let foldedRelation = try resolver.resolve(kind: .curveSurface, first: foldCurveMap, second: foldedMap,
            maximumPairs: 8, maximumIsolatedCells: 8, requireDiscrete: true, cellLimits: cellLimits,
            topologyLimits: topologyLimits, using: &foldedBudget)
        let foldedPoints = try tupleResolver.resolve(relation: foldedRelation, maximumPoints: 2, using: &foldedBudget)
        try require(foldedPoints.points.count == 2)
        let ff = foldedPoints.coordinates.field
        try require(try ff.compare(foldedPoints.points[0].u, ff.binary64(exactly: 0.25, using: &foldedBudget), using: &foldedBudget) == .equal)
        try require(try ff.compare(foldedPoints.points[1].u, ff.binary64(exactly: 0.75, using: &foldedBudget), using: &foldedBudget) == .equal)
        print("ORIGINAL_ISSUED_TUV_OK retained algebraic T, two native seam incidences, distinct UV at one XYZ, exact sorting, retained proof depths, atomic budget/cancel failures and complete point owners")
        let completeEmpty = try resolver.resolve(kind: .curveSurface, first: compiler.compile(cover: empty,
            field: coefficientField, maximumMaps: 0, using: &a), second: planeMap,
            maximumPairs: 0, maximumIsolatedCells: 0, requireDiscrete: true, cellLimits: cellLimits,
            topologyLimits: topologyLimits, using: &a)
        try require(completeEmpty.pairs.isEmpty && completeEmpty.first.original.coverage.effective.isEmpty)
        let emptyPoints = try tupleResolver.resolve(relation: completeEmpty, maximumPoints: 0, using: &a)
        try require(emptyPoints.points.isEmpty && emptyPoints.incidences.isEmpty && emptyPoints.relation.pairs.isEmpty)
        do { _ = try resolver.resolve(kind: .curveSurface, first: verticalMap, second: planeMap,
            maximumPairs: 0, maximumIsolatedCells: 8, requireDiscrete: true, cellLimits: cellLimits,
            topologyLimits: topologyLimits, using: &a); throw DomainProofFailure.incorrect(#line)
        } catch NativeExactRelationFailure.domain(.chartLimit) {}
        do { _ = try resolver.resolve(kind: .curveSurface, first: verticalMap, second: planeMap,
            maximumPairs: 8, maximumIsolatedCells: 0, requireDiscrete: true, cellLimits: cellLimits,
            topologyLimits: topologyLimits, using: &a); throw DomainProofFailure.incorrect(#line)
        } catch NativeExactRelationFailure.resultLimit {}
        var exactResolve = ExactScalarLedger(limits: try .init(work: resolveBudget.work, storageBytes: resolveBudget.storageBytes,
            valueDepth: 32, coefficientDepth: 32))
        _ = try resolver.resolve(kind: .curveSurface, first: verticalMap, second: planeMap,
            maximumPairs: 8, maximumIsolatedCells: 8, requireDiscrete: true, cellLimits: cellLimits,
            topologyLimits: topologyLimits, using: &exactResolve)
        for resource in [ExactResource.work, .storage] {
            var low = ExactScalarLedger(limits: try .init(work: resolveBudget.work - (resource == .work ? 1 : 0),
                storageBytes: resolveBudget.storageBytes - (resource == .storage ? 1 : 0), valueDepth: 32, coefficientDepth: 32))
            do { _ = try resolver.resolve(kind: .curveSurface, first: verticalMap, second: planeMap,
                maximumPairs: 8, maximumIsolatedCells: 8, requireDiscrete: true, cellLimits: cellLimits,
                topologyLimits: topologyLimits, using: &low); throw DomainProofFailure.incorrect(#line)
            } catch NativeExactRelationFailure.scalar(.resourceLimit(let exhausted)) { try require(exhausted == resource) }
            catch NativeExactRelationFailure.relation(.cell(.scalar(.resourceLimit(let exhausted)))) { try require(exhausted == resource) }
            catch NativeExactRelationFailure.relation(.topology(.scalar(.resourceLimit(let exhausted)))) { try require(exhausted == resource) }
            catch NativeExactRelationFailure.relation(.scalar(.resourceLimit(let exhausted))) { try require(exhausted == resource) }
        }
        let mixedInput = NativeInput(degrees: [1], knots: [[0,0,1,2,3,3]], counts: [4],
            controls: [[0,0.5,0],[0.5,0.5,0],[0.5,0.5,1],[0.5,0.5,-1]], weights: [1,1,1,1], periodic: [false])
        let mixedSource = try DefaultOriginalSourceBindingIssuer(provider: NativeProvider()).bind(mixedInput,
            limits: limits.source, using: &a)
        let mixedLaws = try DefaultOriginalFiniteBSplineChartPreparer<NativeSnapshot>().prepare(source: mixedSource,
            field: f, maximumCharts: 8, limits: limits.source, using: &a)
        let mixedRange = try ExactParameterInterval.checked(field: f, lower: .finite(zero),
            upper: .finite(f.integer(3, using: &a)), depth: depth, using: &a)
        let mixedFrame = try DefaultOriginalParameterTransporter<NativeSnapshot, OriginalExactScalarDomain>().frame(
            source: mixedSource, field: f, support: [[mixedRange]], semantics: [.authoredScalar], limits: limits, using: &a)
        let mixedCover = try binder.bind(laws: mixedLaws.laws, request: mixedFrame.fullSelection(limits: limits, using: &a),
            limits: limits, using: &a)
        let mixedMap = try compiler.compile(cover: mixedCover, field: coefficientField, maximumMaps: 8, using: &a)
        let mixed = try resolver.resolve(kind: .curveSurface, first: mixedMap, second: planeMap,
            maximumPairs: 8, maximumIsolatedCells: 8, requireDiscrete: false, cellLimits: cellLimits,
            topologyLimits: topologyLimits, using: &a)
        try require(mixed.pairs.count == 3 && mixed.hasPositiveDimensionalSolutions && mixed.isolatedCellCount > 0)
        do { _ = try tupleResolver.resolve(relation: mixed, maximumPoints: 8, using: &a)
            throw DomainProofFailure.incorrect(#line)
        } catch NativeExactRelationFailure.nonDiscreteIntersection {}
        do { _ = try resolver.resolve(kind: .curveSurface, first: mixedMap, second: planeMap,
            maximumPairs: 8, maximumIsolatedCells: 8, requireDiscrete: true, cellLimits: cellLimits,
            topologyLimits: topologyLimits, using: &a); throw DomainProofFailure.incorrect(#line)
        } catch NativeExactRelationFailure.nonDiscreteIntersection {}
        print("ISSUED_RELATION_PROOF_OK complete isolated Native CS through L5, exact TUV, complete exclusion, mixed positive/isolated atomic rejection and exact work/storage/pair/result limits")
#endif
        print("ISSUED_DOMAIN_PROOF_OK full two-span cover, both closed seam owners, exact inverse selection, missing template rejection, complete exclusion and budgets/cancel")
    }
}
