import CADCore
@testable import CADGeometry
@testable import PolylineLiftAdapters
@testable import PublicLiftPlane
import PublicCoonsSelf
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(WASILibc)
import WASILibc
#endif

/// Independent full-cell oracles for authored folds and scoped source-law collapse.
@main struct CoonsGraphSelfContactFoldScope {
    typealias Admission = PolylineLiftProof.Admission
    typealias Base = OriginalExactScalarDomain
    typealias Source = BSplineSurface3D
    typealias Evidence = OriginalRationalChartReceipt<Source, OriginalBSplineChartSelection, Base>
    typealias Cover = OriginalIssuedDomainCover<Source, OriginalBSplineChartSelection, Base>
    typealias Raw = PublicLiftPlane.OriginalIssuedGraphRelations<Source, Evidence, Cover, Source, Evidence, Cover>
    typealias Result = OriginalIssuedGraphSelfContacts<Source, Evidence, Cover, Evidence, Cover>
    typealias Identity = OriginalParameterIdentity<Source, Base>
    typealias Cells = PublicLiftPlane.ExactRealCellDomain<Base>
    typealias Field = Result.Field
    typealias Polynomial = ExactPolynomial<Field>

    static func marker(_ text: StaticString) { print(text); fflush(nil) }

    static func group() -> String {
#if hasFeature(Embedded)
        if let value = getenv("CAD_PROOF_GROUP") { return String(cString: value) }
        return "all"
#else
        return CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "all"
#endif
    }

    static func raw(collapsed: Bool, using a: inout Admission) throws -> Raw {
        let surface = BSplineSurface3D(uDegree: collapsed ? 2 : 1, vDegree: 1,
            uKnots: collapsed ? [0,0,0,1,1,1] : [0,0,0.5,1,1], vKnots: [0,0,1,1],
            controlPoints: [0.0,1.0].map { v in
                (collapsed ? [1.0,-1.0,1.0] : [0.0,1.0,0.0]).map { x in
                    collapsed ? .init(x: 2,y: 3,z: 4) : .init(x: x,y: v,z: 0)
                }
            })
        let limits = try PolylineLiftProof.limits()
        let base = try Base(maximumValueDepth: 32, maximumCoefficientDepth: 32, using: &a)
        let source = try DefaultOriginalSourceBindingIssuer(
            provider: PolylineLiftAdapters.OriginalBSplineSurfaceSnapshotProvider(tolerance: .standard))
            .bind(surface, limits: limits.source, using: &a)
        let charts = try PolylineLiftAdapters.DefaultOriginalFiniteBSplineChartPreparer<Source>()
            .prepare(source: source, field: base, maximumCharts: collapsed ? 1 : 2, limits: limits.source, using: &a)
        try PolylineLiftProof.require(charts.laws.count == (collapsed ? 1 : 2) && charts.support.count == 2)
        var support: [[ExactParameterInterval<OriginalExactScalar>]] = []
        for axis in 0..<2 {
            try PolylineLiftProof.require(base.compare(charts.support[axis].lower, base.integer(0, using: &a), using: &a) == .equal)
            try PolylineLiftProof.require(base.compare(charts.support[axis].upper, base.integer(1, using: &a), using: &a) == .equal)
            support.append([try .checked(field: base, lower: .finite(charts.support[axis].lower),
                upper: .finite(charts.support[axis].upper), depth: .zero, using: &a)])
        }
        let frame = try DefaultOriginalParameterTransporter<Source, Base>().frame(source: source, field: base,
            support: support, semantics: [.authoredScalar,.authoredScalar], limits: limits, using: &a)
        let cover = try DefaultOriginalIssuedDomainBinder().bind(laws: charts.laws,
            request: frame.fullSelection(limits: limits, using: &a), limits: limits, using: &a)
        let field = try Field.base(field: base, maximumExtensionLevel: 32, using: &a)
        let family = try DefaultOriginalRationalGraphFamilyPreparer().prepare(cover: cover, field: field,
            maximumGraphs: collapsed ? 1 : 2, limits: limits, using: &a)
        try PolylineLiftProof.require(family.graphs.count == (collapsed ? 1 : 2))
        for ordinal in family.graphs.indices {
        let graph = family.graphs[ordinal].original.graph, ring = graph.polynomials
        let u = try ring.variable(0, using: &a), v = try ring.variable(1, using: &a)
        let zero = try ring.constant(base.integer(0, using: &a), using: &a)
        let one = try ring.constant(base.integer(1, using: &a), using: &a)
        let twiceU = try ring.scaled(u, by: base.integer(2, using: &a), using: &a)
        let foldedX = try ordinal == 0 ? twiceU : ring.subtracting(
            ring.constant(base.integer(2, using: &a), using: &a), twiceU, using: &a)
        let expected = collapsed
            ? try [2,3,4,1].map { try ring.constant(base.integer($0, using: &a), using: &a) }
            : [foldedX, v, zero, one]
        let expectedBounds = collapsed ? [0.0,1.0,0.0,1.0]
            : [ordinal == 0 ? 0.0 : 0.5, ordinal == 0 ? 0.5 : 1.0, 0.0,1.0]
        for axis in 0..<2 {
            try PolylineLiftProof.require(base.compare(graph.support[axis].lower,
                base.binary64(exactly: expectedBounds[2 * axis], using: &a), using: &a) == .equal)
            try PolylineLiftProof.require(base.compare(graph.support[axis].upper,
                base.binary64(exactly: expectedBounds[2 * axis + 1], using: &a), using: &a) == .equal)
        }
        try PolylineLiftProof.require(graph.layout.parameters == [0,1] && graph.layout.variableCount == 2)
        try PolylineLiftProof.require(graph.includesUpperBoundary == [true,true])
        for axis in 0..<4 {
            try PolylineLiftProof.require(ring.equals(graph.homogeneous[axis], expected[axis], using: &a))
        }
        for axis in 0..<2 {
            try PolylineLiftProof.require(ring.equals(graph.parameterTransport.numerators[axis], axis == 0 ? u : v, using: &a))
            try PolylineLiftProof.require(ring.equals(graph.parameterTransport.denominators[axis], one, using: &a))
        }
        }
        marker("PASS S-COONS-PLANE-01 Native source law and authored UV verified before self solving")
        return try PublicLiftPlane.DefaultOriginalIssuedGraphRelationResolver().resolve(kind: .surfaceSurface,
            first: family, second: family, maximumPairs: collapsed ? 1 : 4, limits: limits,
            cellLimits: .init(maximumStoredCells: 20_000, maximumRootsPerStack: 100),
            topologyLimits: .init(maximumGeneratedCells: 20_000, maximumRootsPerStack: 100,
                maximumClosures: 20_000, maximumAttachmentPieces: 100_000, maximumComponents: 1_000), using: &a)
    }

    static func collapseIdentity(_ raw: Raw, using a: inout Admission) throws -> Identity {
        let limits = try PolylineLiftProof.limits(), graph = raw.first.graphs[0]
        let frame = graph.original.request.frame, base = frame.scalarField
        let u = try ExactParameterInterval.checked(field: base,
            lower: .finite(base.binary64(exactly: 0.25, using: &a)),
            upper: .finite(base.binary64(exactly: 0.75, using: &a)),
            includesLower: false, includesUpper: false, depth: .zero, using: &a)
        let v = try ExactParameterInterval.checked(field: base,
            lower: .finite(base.integer(0, using: &a)),
            upper: .finite(base.binary64(exactly: 0.5, using: &a)),
            includesLower: true, includesUpper: false, depth: .zero, using: &a)
        let scope = try frame.selection(intervals: [[u],[v]], limits: limits, using: &a)
        let issuer = DefaultOriginalParameterIdentityIssuer<Source, Base>()
        let identity = try issuer.collapsed(law: graph.original.graph.evidence, on: scope, limits: limits, using: &a)
        let view = try issuer.relation(of: identity, limits: limits, using: &a)
        guard case .completeProduct = view.constraints else { throw ExactScalarFailure.invalidEvidence }
        try PolylineLiftProof.require(view.kind == .collapsedSubset && !view.left.isEmpty && !view.right.isEmpty)
        return identity
    }

    static func query(_ raw: Raw, excluding identities: [Identity], using a: inout Admission) throws -> Result {
        try DefaultOriginalIssuedGraphSelfContactQuery().contacts(in: raw, excluding: identities,
            domainLimits: PolylineLiftProof.limits(),
            cellLimits: .init(maximumStoredCells: 20_000, maximumRootsPerStack: 100),
            topologyLimits: .init(maximumGeneratedCells: 20_000, maximumRootsPerStack: 100,
                maximumClosures: 20_000, maximumAttachmentPieces: 100_000, maximumComponents: 1_000), using: &a)
    }

    static func foldedCells(_ partition: PublicLiftPlane.ExactRealCellPartition<Base>, first: Int, second: Int,
        residual: Bool, actual: (PublicLiftPlane.ExactRealCellID<Base>) throws -> Bool,
        using a: inout Admission) throws -> [Int] {
        let cells = try Cells(retaining: partition.source, using: &a), ring = cells.polynomials
        try PolylineLiftProof.require(partition.source.variableCount == 4)
        let variables = try (0..<4).map { try ring.variable($0, using: &a) }
        let uDifference = try ring.subtracting(variables[0], variables[2], using: &a)
        let vDifference = try ring.subtracting(variables[1], variables[3], using: &a)
        let uSum = try ring.subtracting(ring.adding(variables[0], variables[2], using: &a),
            ring.constant(ring.field.integer(1, using: &a), using: &a), using: &a)
        var laws = [first == second ? uDifference : uSum, vDifference]
        if residual { laws.append(uDifference) }
        let bounds = [first == 0 ? 0.0 : 0.5, first == 0 ? 0.5 : 1.0, 0.0,1.0,
                      second == 0 ? 0.0 : 0.5, second == 0 ? 0.5 : 1.0, 0.0,1.0]
        for axis in 0..<4 {
            for endpoint in 0..<2 {
                laws.append(try ring.subtracting(variables[axis], ring.constant(
                    ring.field.binary64(exactly: bounds[2 * axis + endpoint], using: &a), using: &a), using: &a))
            }
        }
        var invariants: [PublicLiftPlane.ExactRealCellSignInvariant<Base>] = []
        for (index, law) in laws.enumerated() {
            guard let invariant = try cells.signInvariant(for: law, in: partition, using: &a) else {
#if !hasFeature(Embedded)
                print("FAIL folded independent full-cell sign invariant", first, second, residual, index)
#else
                marker("FAIL folded independent full-cell sign invariant")
#endif
                throw ExactScalarFailure.invalidEvidence
            }
            invariants.append(invariant)
        }
        var checked = 0, included = 0, negative = 0, positive = 0
        for cell in partition.cells where cell.axis == 3 {
            let signs = try invariants.map { try cells.sign(of: $0, at: cell, using: &a) }
            var inside = true
            let boundsStart = residual ? 3 : 2
            for axis in 0..<4 {
                if signs[boundsStart + 2 * axis] == .negative || signs[boundsStart + 2 * axis + 1] == .positive { inside = false }
            }
            let expected = inside && signs[0] == .zero && signs[1] == .zero && (!residual || signs[2] != .zero)
            try PolylineLiftProof.require(actual(cell) == expected)
            if expected {
                included += 1
                if residual && signs[2] == .negative { negative += 1 }
                if residual && signs[2] == .positive { positive += 1 }
            }
            checked += 1
        }
        try PolylineLiftProof.require(checked > 0)
        return [checked,included,negative,positive]
    }

    static func foldedOracle(_ result: Result, using a: inout Admission) throws {
        let raw = result.raw
        try PolylineLiftProof.require(raw.first.graphs.count == 2 && raw.second.graphs.count == 2)
        try PolylineLiftProof.require(raw.pairs.count == 4 && result.refinements.count == 4 && result.authoredDiagonals.count == 4)
        try PolylineLiftProof.require(result.identities.isEmpty && raw.first.source.owner === raw.second.source.owner)
        var seen: [Int] = [], rawCells = 0, refinedCells = 0, retainedCells = 0, emptyPairs = 0
        for ordinal in raw.pairs.indices {
            let pair = raw.pairs[ordinal], refined = result.refinements[ordinal], pullback = refined.pullback
            let first = pair.firstGraphIndex, second = pair.secondGraphIndex
            try PolylineLiftProof.require((0..<2).contains(first) && (0..<2).contains(second))
            let key = 2 * first + second
            try PolylineLiftProof.require(!seen.contains(key)); seen.append(key)
            try PolylineLiftProof.require(refined.pairOrdinal == ordinal && pullback.coordinateMap == [0,1,2,3])
            try PolylineLiftProof.require(pair.relation.original.firstCoordinates == [0,1] && pair.relation.original.secondCoordinates == [2,3])
            let selected = pair.relation.projection.original, original = selected.cells
            try PolylineLiftProof.require(pullback.source.cells.count == original.count)
            for index in original.indices { try PolylineLiftProof.require(pullback.source.cells[index] == original[index]) }
            let before = try foldedCells(selected.partition, first: first, second: second, residual: false,
                actual: { selected.cells.contains($0) }, using: &a)
            try PolylineLiftProof.require(before[1] > 0)
            rawCells += before[0]
            let region = pullback.region
            try PolylineLiftProof.require(region.coordinateCount == 4 && region.cells.count == region.included.count)
            try PolylineLiftProof.require(region.cells.count == pullback.sourceCellOrdinals.count)
            let after = try foldedCells(region.partition, first: first, second: second, residual: true,
                actual: { cell in
                    let matches = region.cells.indices.filter { region.cells[$0] == cell }
                    try PolylineLiftProof.require(matches.count == 1)
                    let index = matches[0], included = region.included[index]
                    try PolylineLiftProof.require(included ? original.indices.contains(pullback.sourceCellOrdinals[index])
                        : pullback.sourceCellOrdinals[index] == -1)
                    return included
                }, using: &a)
            try PolylineLiftProof.require(after[0] == region.cells.count)
            refinedCells += after[0]; retainedCells += after[1]
            if first == second {
                try PolylineLiftProof.require(after[1] == 0); emptyPairs += 1
            } else {
                try PolylineLiftProof.require(after[1] > 0)
                try PolylineLiftProof.require(first == 0 ? after[2] > 0 && after[3] == 0 : after[3] > 0 && after[2] == 0)
            }
        }
        try PolylineLiftProof.require(seen.count == 4 && emptyPairs == 2 && retainedCells > 0)
#if !hasFeature(Embedded)
        print("PASS S-COONS-PLANE-01 independent whole-cell folded oracle all4 pairs; raw", rawCells,
            "refined", refinedCells, "retained", retainedCells, "emptySameChartPairs", emptyPairs)
        fflush(nil)
#else
        marker("PASS S-COONS-PLANE-01 independent whole-cell folded oracle all4 pairs")
#endif
    }

    static func oracle(_ result: Result, collapsed: Bool, using a: inout Admission) throws {
        if !collapsed { try foldedOracle(result, using: &a); return }
        let raw = result.raw
        try PolylineLiftProof.require(raw.pairs.count == 1 && result.refinements.count == 1 && result.authoredDiagonals.count == 1)
        try PolylineLiftProof.require(result.identities.count == (collapsed ? 1 : 0))
        try PolylineLiftProof.require(raw.first.source.owner === raw.second.source.owner)
        let pair = raw.pairs[0], refined = result.refinements[0], pullback = refined.pullback
        try PolylineLiftProof.require(pair.firstGraphIndex == 0 && pair.secondGraphIndex == 0 && refined.pairOrdinal == 0)
        try PolylineLiftProof.require(pair.relation.original.firstCoordinates == [0,1] && pair.relation.original.secondCoordinates == [2,3])
        try PolylineLiftProof.require(pullback.coordinateMap == [0,1,2,3])
        let original = pair.relation.projection.original.cells
        try PolylineLiftProof.require(pullback.source.cells.count == original.count)
        for index in original.indices { try PolylineLiftProof.require(pullback.source.cells[index] == original[index]) }
        let region = pullback.region, partition = region.partition
        try PolylineLiftProof.require(partition.source.variableCount == 4 && region.coordinateCount == 4)
        try PolylineLiftProof.require(region.cells.count == region.included.count && region.cells.count == pullback.sourceCellOrdinals.count)
        let cells = try Cells(retaining: partition.source, using: &a), ring = cells.polynomials
        let variables = try (0..<4).map { try ring.variable($0, using: &a) }
        let one = try ring.constant(ring.field.integer(1, using: &a), using: &a)
        let differenceU = try ring.subtracting(variables[0], variables[2], using: &a)
        let differenceV = try ring.subtracting(variables[1], variables[3], using: &a)
        let sumU = try ring.subtracting(ring.adding(variables[0], variables[2], using: &a), one, using: &a)
        var laws = [differenceU,differenceV]
        if !collapsed { laws.append(sumU) }
        for variable in variables { laws.append(variable); laws.append(try ring.subtracting(variable, one, using: &a)) }
        if collapsed {
            for axis in 0..<4 {
                let low = axis % 2 == 0 ? 0.25 : 0.0, high = axis % 2 == 0 ? 0.75 : 0.5
                for value in [low,high] {
                    laws.append(try ring.subtracting(variables[axis], ring.constant(ring.field.binary64(exactly: value, using: &a), using: &a), using: &a))
                }
            }
        }
        var invariants: [PublicLiftPlane.ExactRealCellSignInvariant<Base>] = []
        for (index, law) in laws.enumerated() {
            guard let invariant = try cells.signInvariant(for: law, in: partition, using: &a) else {
#if !hasFeature(Embedded)
                print("FAIL independent full-cell oracle has no sign invariant", index)
#else
                marker("FAIL independent full-cell oracle has no sign invariant")
#endif
                throw ExactScalarFailure.invalidEvidence
            }
            invariants.append(invariant)
        }
        var checked = 0, included = 0, excluded = 0, negativeFold = 0, positiveFold = 0, scopedOffDiagonal = 0, openBoundaryResidual = 0
        for cell in partition.cells where cell.axis == 3 {
            let matches = region.cells.indices.filter { region.cells[$0] == cell }
            try PolylineLiftProof.require(matches.count == 1)
            let index = matches[0]
            let signs = try invariants.map { try cells.sign(of: $0, at: cell, using: &a) }
            let diagonal = signs[0] == .zero && signs[1] == .zero
            let boundsStart = collapsed ? 2 : 3
            var inside = true
            for axis in 0..<4 {
                if signs[boundsStart + 2 * axis] == .negative || signs[boundsStart + 2 * axis + 1] == .positive { inside = false }
            }
            let expected: Bool
            if collapsed {
                let scopeStart = boundsStart + 8
                var inProduct = true, onOpenBoundary = false
                for axis in 0..<4 {
                    let lower = signs[scopeStart + 2 * axis], upper = signs[scopeStart + 2 * axis + 1]
                    if (axis % 2 == 0 ? lower != .positive : lower == .negative) || upper != .negative { inProduct = false }
                    if axis % 2 == 0 && lower == .zero || upper == .zero { onOpenBoundary = true }
                }
                expected = inside && !diagonal && !inProduct
                if inside && !diagonal && inProduct { scopedOffDiagonal += 1 }
                if expected && onOpenBoundary { openBoundaryResidual += 1 }
            } else {
                expected = inside && signs[2] == .zero && signs[0] != .zero && signs[1] == .zero
                if expected && signs[0] == .negative { negativeFold += 1 }
                if expected && signs[0] == .positive { positiveFold += 1 }
            }
            try PolylineLiftProof.require(region.included[index] == expected)
            let sourceOrdinal = pullback.sourceCellOrdinals[index]
            if expected {
                try PolylineLiftProof.require(original.indices.contains(sourceOrdinal))
                included += 1
            } else {
                try PolylineLiftProof.require(sourceOrdinal == -1)
                excluded += 1
            }
            checked += 1
        }
        try PolylineLiftProof.require(checked == region.cells.count && included > 0 && excluded > 0)
        if collapsed { try PolylineLiftProof.require(scopedOffDiagonal > 0 && openBoundaryResidual > 0) }
        else { try PolylineLiftProof.require(negativeFold > 0 && positiveFold > 0) }
#if !hasFeature(Embedded)
        print("PASS S-COONS-PLANE-01 independent whole-cell oracle", collapsed ? "collapse" : "folded",
            "checked", checked, "included", included, "excluded", excluded)
        fflush(nil)
#else
        marker("PASS S-COONS-PLANE-01 independent whole-cell scoped-collapse oracle")
#endif
    }

    static func membership(_ result: Result, collapsed: Bool, using a: inout Admission) throws {
        let fixtures: [([Double],Bool)] = collapsed
            ? [([0,0,1,1],true), ([0.25,0.25,0.75,0.25],true), ([0.5,0,0.5,0.25],false),
               ([0.5,0.5,0.625,0.5],true), ([0.5,0.25,0.5,0.25],false)]
            : [([0,0.5,1,0.5],true), ([0.25,0,0.75,0],true), ([0,1,1,1],true),
               ([0.5,0.5,0.5,0.5],false), ([0.25,0,0.75,0.5],false), ([0.25,0,0.5,0],false)]
        for (values, expected) in fixtures {
            let tuple = try values.map { try result.raw.first.field.binary64(exactly: $0, using: &a) }
            var actual = false
            for pairOrdinal in result.raw.pairs.indices {
                let member = try result.contains(pairOrdinal: pairOrdinal, liftedCoordinates: tuple,
                    domainLimits: PolylineLiftProof.limits(), rootLimits: .init(maximumRoots: 100), using: &a)
                actual = actual || member
                if !collapsed && result.raw.pairs[pairOrdinal].firstGraphIndex == result.raw.pairs[pairOrdinal].secondGraphIndex {
                    try PolylineLiftProof.require(!member)
                }
            }
            try PolylineLiftProof.require(actual == expected)
        }
        marker("PASS S-COONS-PLANE-01 public membership agrees at fold/domain/open-scope boundaries")
    }

    static func main() throws {
        let selected = group()
        try PolylineLiftProof.require(["all","folded","collapse"].contains(selected))
        for collapsed in [false,true] where selected == "all" || selected == (collapsed ? "collapse" : "folded") {
            marker("RUN S-COONS-PLANE-01 bounded Native fold/scoped-collapse producer")
            var preparation = try Admission(work: 80_000_000)
            let raw = try raw(collapsed: collapsed, using: &preparation)
            let identities = try collapsed ? [collapseIdentity(raw, using: &preparation)] : []
            marker("RUN S-COONS-PLANE-01 public residual query")
            var admission = try Admission(work: 80_000_000)
            let result = try query(raw, excluding: identities, using: &admission)
            var verification = try Admission(work: 80_000_000)
            try oracle(result, collapsed: collapsed, using: &verification)
            try membership(result, collapsed: collapsed, using: &verification)
            marker("PASS S-COONS-PLANE-01 bounded Native group complete")
        }
    }
}
