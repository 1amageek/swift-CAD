import CADCore
@testable import CADGeometry
@testable import RetainedHostAdapters
@testable import PublicLiftPlane
@testable import GuideSeamPort

/// Reuses the accepted four-chart planar Coons input with the current self consumer.
enum GuideSeamCoonsRegression {
    typealias Admission = ClosedGuideSeamAcceptance.Admission
    typealias Base = OriginalExactScalarDomain
    typealias Source = RetainedHostAdapters.OriginalCoonsAtlasSnapshot
    typealias Cover = OriginalIssuedDomainCover<Source, Int, Base>
    typealias Evidence = OriginalRationalChartReceipt<Source, Int, Base>
    typealias Raw = GuideSeamPort.OriginalIssuedGraphRelations<Source, Evidence, Cover, Source, Evidence, Cover>
    typealias Cells = PublicLiftPlane.ExactRealCellDomain<Base>

    private static func require(_ condition: Bool) throws {
        if !condition { throw ExactScalarFailure.invalidEvidence }
    }

    private static func limits() throws -> OriginalDomainIdentityLimits {
        try .init(source: .init(remainingSourceDepth: 8), maximumTransportDepth: 16,
            maximumCharts: 32, maximumFamilies: 2, maximumIdentityProofs: 16)
    }

    // The multi:true branch of the accepted PolylineAtlasLiftProof.shape recipe.
    private static func shape(using a: inout Admission) throws -> OriginalCoonsSurface3D {
        try ExactScalarNumericAccess.withAdmission(&a) { usage in
            let t = [0.0, 0.5, 1.0], knots = [0.0, 0, 0.5, 1, 1]
            let native = BSplineSurface3D(uDegree: 1, vDegree: 1, uKnots: knots, vKnots: knots,
                controlPoints: t.map { v in t.map { u in .init(x: u, y: v, z: 0) } })
            let issuer = OriginalSurfaceBoundarySourceIssuer()
            func boundary(_ side: SurfaceParameterBoundary) throws -> OriginalCurveRootSpan3D {
                try issuer.boundary(of: .bSpline(native), at: side, maximumDepth: 0,
                    maximumSpanCount: 4, tolerance: .standard, usage: &usage)
            }
            let lower = try boundary(.vLower)
            return try OriginalCoonsSurface3D(vMinimumBoundary: lower, vMaximumBoundary: boundary(.vUpper),
                uMinimumBoundary: boundary(.uLower), uMaximumBoundary: boundary(.uUpper),
                tolerance: .standard, usage: &usage)
        }.value
    }

    static func raw(using a: inout Admission) throws -> Raw {
        let host = try shape(using: &a)
        let field = try Base(maximumValueDepth: 32, maximumCoefficientDepth: 32, using: &a)
        let limits = try limits()
        let source = try DefaultOriginalSourceBindingIssuer(
            provider: OriginalCoonsAtlasSnapshotProvider(field: field, tolerance: .standard))
            .bind(host, limits: limits.source, using: &a)
        let charts = try DefaultOriginalFiniteRetainedSurfaceChartPreparer<Source>()
            .prepare(source: source, maximumCharts: 4, limits: limits.source, using: &a)
        try require(charts.laws.count == 4 && charts.support.count == 2)
        for bound in charts.support {
            try require(field.compare(bound.lower, field.integer(0, using: &a), using: &a) == .equal)
            try require(field.compare(bound.upper, field.integer(1, using: &a), using: &a) == .equal)
        }
        var intervals: [[ExactParameterInterval<OriginalExactScalar>]] = []
        for bound in charts.support {
            intervals.append([try .checked(field: field, lower: .finite(bound.lower), upper: .finite(bound.upper),
                depth: .zero, using: &a)])
        }
        let frame = try DefaultOriginalParameterTransporter<Source, Base>().frame(source: source, field: field,
            support: intervals, semantics: [.authoredScalar, .authoredScalar], limits: limits, using: &a)
        let cover = try DefaultOriginalIssuedDomainBinder().bind(laws: charts.laws,
            request: frame.fullSelection(limits: limits, using: &a), limits: limits, using: &a)
        let algebraic = try PublicLiftPlane.ExactAlgebraicScalarDomain.base(field: field, maximumExtensionLevel: 32, using: &a)
        let family = try GuideSeamPort.DefaultOriginalRationalGraphFamilyPreparer().prepare(cover: cover, field: algebraic,
            maximumGraphs: 4, limits: limits, using: &a)
        try require(family.graphs.count == 4)
        for graph in family.graphs {
            let original = graph.original.graph, ring = original.polynomials
            let zero = try ring.constant(field.integer(0, using: &a), using: &a)
            let one = try ring.constant(field.integer(1, using: &a), using: &a)
            let expected = [try ring.variable(0, using: &a), try ring.variable(1, using: &a), zero, one]
            try require(original.layout.variableCount == 2)
            for axis in expected.indices {
                try require(ring.equals(original.homogeneous[axis], expected[axis], using: &a))
            }
            for axis in 0..<2 {
                try require(ring.equals(original.parameterTransport.numerators[axis], expected[axis], using: &a))
                try require(ring.equals(original.parameterTransport.denominators[axis], one, using: &a))
            }
        }
        return try GuideSeamPort.DefaultOriginalIssuedGraphRelationResolver().resolve(kind: .surfaceSurface,
            first: family, second: family, maximumPairs: 16, limits: limits,
            cellLimits: .init(maximumStoredCells: 20_000, maximumRootsPerStack: 100),
            topologyLimits: .init(maximumGeneratedCells: 20_000, maximumRootsPerStack: 100,
                maximumClosures: 20_000, maximumAttachmentPieces: 100_000, maximumComponents: 1_000), using: &a)
    }

    static func oracle(_ raw: Raw, using a: inout Admission) throws {
        try require(raw.pairs.count == 16 && raw.first.source.owner === raw.second.source.owner)
        // Independently authored knot grid; validate the chart cover before using
        // its ordinals to test both inclusion and exclusion over every full cell.
        let base = raw.first.graphs[0].original.graph.field
        var rectangles: [[Double]] = []
        for graph in raw.first.graphs {
            let original = graph.original.graph
            var matched: [Double]?
            for v in [0.0, 0.5] {
                for u in [0.0, 0.5] {
                    let candidate = [u, u + 0.5, v, v + 0.5]
                    var equal = original.support.count == 2 && original.includesUpperBoundary == [true, true]
                    for axis in 0..<2 {
                        equal = try equal && base.compare(original.support[axis].lower,
                            base.binary64(exactly: candidate[2 * axis], using: &a), using: &a) == .equal
                        equal = try equal && base.compare(original.support[axis].upper,
                            base.binary64(exactly: candidate[2 * axis + 1], using: &a), using: &a) == .equal
                    }
                    if equal { matched = candidate }
                }
            }
            guard let matched, !rectangles.contains(matched) else { throw ExactScalarFailure.invalidEvidence }
            rectangles.append(matched)
        }
        var nonemptyPairs = 0
        for pair in raw.pairs {
            let selected = pair.relation.projection.original, partition = selected.partition
            try require(partition.source.variableCount == 4)
            try require(pair.relation.original.firstCoordinates == [0, 1])
            try require(pair.relation.original.secondCoordinates == [2, 3])
            let cells = try Cells(retaining: partition.source, using: &a), ring = cells.polynomials
            let u = try ring.subtracting(ring.variable(0, using: &a), ring.variable(2, using: &a), using: &a)
            let v = try ring.subtracting(ring.variable(1, using: &a), ring.variable(3, using: &a), using: &a)
            guard let us = try cells.signInvariant(for: u, in: partition, using: &a),
                let vs = try cells.signInvariant(for: v, in: partition, using: &a) else { throw ExactScalarFailure.invalidEvidence }
            let bounds = rectangles[pair.firstGraphIndex] + rectangles[pair.secondGraphIndex]
            var constraints: [ExactPolynomial<PublicLiftPlane.ExactAlgebraicScalarDomain<Base>>] = []
            for axis in 0..<4 {
                for endpoint in 0..<2 {
                    let value = try ring.field.importingBase(base.binary64(exactly: bounds[2 * axis + endpoint], using: &a), using: &a)
                    constraints.append(try ring.subtracting(ring.variable(axis, using: &a), ring.constant(value, using: &a), using: &a))
                }
            }
            let invariants = try constraints.map { polynomial in
                guard let invariant = try cells.signInvariant(for: polynomial, in: partition, using: &a) else {
                    throw ExactScalarFailure.invalidEvidence
                }
                return invariant
            }
            var count = 0
            for cell in partition.cells where cell.axis == 3 {
                let diagonal = try cells.sign(of: us, at: cell, using: &a) == .zero && cells.sign(of: vs, at: cell, using: &a) == .zero
                var inside = true
                for index in invariants.indices {
                    let sign = try cells.sign(of: invariants[index], at: cell, using: &a)
                    if index % 2 == 0 ? sign == .negative : sign == .positive { inside = false }
                }
                try require(selected.cells.contains(cell) == (diagonal && inside))
                if selected.cells.contains(cell) { count += 1 }
            }
            if count > 0 { nonemptyPairs += 1 }
        }
        try require(nonemptyPairs == 16)
        print("PASS S-COONS-PLANE-01 all 16 chart pairs equal the complete independent closed-domain diagonal oracle")
    }

    static func run() throws {
        // Preserve the accepted Coons caller ceilings, separately for preparation and query.
        var preparation = try Admission(work: 80_000_000, storageBytes: 1_073_741_824)
        let original = try raw(using: &preparation)
        try oracle(original, using: &preparation)
        var query = try Admission(work: 80_000_000, storageBytes: 1_073_741_824)
        let domainLimits = try limits()
        let result = try GuideSeamPort.DefaultOriginalIssuedGraphSelfContactQuery().contacts(in: original,
            domainLimits: domainLimits,
            cellLimits: .init(maximumStoredCells: 20_000, maximumRootsPerStack: 100),
            topologyLimits: .init(maximumGeneratedCells: 20_000, maximumRootsPerStack: 100,
                maximumClosures: 20_000, maximumAttachmentPieces: 100_000, maximumComponents: 1_000), using: &query)
        try require(result.raw.pairs.count == 16 && result.refinements.count == 16
            && result.authoredDiagonals.count == 16 && result.identities.isEmpty)
        let issuer = DefaultOriginalParameterIdentityIssuer<Source, Base>()
        for ordinal in result.refinements.indices {
            let refined = result.refinements[ordinal], pullback = refined.pullback
            let pair = original.pairs[ordinal]
            try require(pair.firstGraphIndex == ordinal / 4 && pair.secondGraphIndex == ordinal % 4)
            try require(refined.pairOrdinal == ordinal && pullback.coordinateMap == [0, 1, 2, 3])
            let selected = pair.relation.projection.original.cells
            try require(pullback.source.cells.count == selected.count)
            for index in selected.indices { try require(pullback.source.cells[index] == selected[index]) }
            let region = pullback.region
            try require(region.coordinateCount == 4 && region.cells.count == region.included.count
                && region.cells.count == pullback.sourceCellOrdinals.count)
            var terminalCount = 0
            for cell in region.partition.cells where cell.axis == 3 {
                terminalCount += 1
                var occurrences = 0
                for retained in region.cells { if retained == cell { occurrences += 1 } }
                try require(occurrences == 1)
            }
            try require(terminalCount > 0 && terminalCount == region.cells.count)
            try require(region.included.allSatisfy { !$0 })
            for sourceOrdinal in pullback.sourceCellOrdinals { try require(sourceOrdinal == -1) }
            // The consumed authored diagonal retains each actual pair's complete request scopes.
            let diagonal = try issuer.relation(of: result.authoredDiagonals[ordinal],
                limits: domainLimits, using: &preparation)
            try require(diagonal.left.equals(original.first.graphs[pair.firstGraphIndex].original.request,
                limits: domainLimits, using: &preparation))
            try require(diagonal.right.equals(original.second.graphs[pair.secondGraphIndex].original.request,
                limits: domainLimits, using: &preparation))
            guard case .affine(let permutation, let gains, let offsets) = diagonal.constraints else {
                throw ExactScalarFailure.invalidEvidence
            }
            try require(permutation == [0, 1] && gains.count == 2 && offsets.count == 2)
            let field = diagonal.left.frame.scalarField
            for axis in 0..<2 {
                try require(field.compare(gains[axis], field.integer(1, using: &preparation), using: &preparation) == .equal)
                try require(field.compare(offsets[axis], field.integer(0, using: &preparation), using: &preparation) == .equal)
            }
        }
        print("PASS current Coons self regression: original four charts, whole ordered16 diagonal and complete empty residual")
    }
}
