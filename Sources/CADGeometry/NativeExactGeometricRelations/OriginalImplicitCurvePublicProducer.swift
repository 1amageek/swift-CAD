import CADCore

/// Publishes the supported source-owned implicit family through existing issued graph CS.
struct OriginalImplicitCurvePublicProducer {
    private typealias Base = OriginalExactScalarDomain
    private typealias Curve = OriginalImplicitCurveSnapshot
    private typealias Evidence = OriginalImplicitCurveGraphEvidence
    private typealias CurveCover = OriginalCompleteCurveGraphDomainCover<Curve,Evidence,OriginalFiniteImplicitCurveGraphCoverage>
    private typealias Surface = BSplineSurface3D
    private typealias SurfaceChart = OriginalBSplineChartSelection
    private typealias SurfaceLaw = OriginalRationalChartReceipt<Surface,SurfaceChart,Base>
    private typealias SurfaceCover = OriginalIssuedDomainCover<Surface,SurfaceChart,Base>

    func resolve(curve: Curve3D, surface: Surface3D, options: CurveSurfaceIntersectionOptions,
        tolerance: ModelingTolerance, using a: inout OriginalQueryExecution,
        retainingRelations: Bool = false) throws -> CurveSurfaceIntersectionResult? {
        a.context = a.context.at(stage: .request)
        try a.checkpoint()
        if let excluded = try OriginalImplicitHostPlanePublicProducer().resolve(
            curve: curve, surface: surface, options: options, tolerance: tolerance, using: &a) {
            return excluded
        }
        // FIXME(INCOMPLETE_IMPLEMENTATION): The ordinary implicit selector consumes
        // only the source-owned finite forward axis-separated Native cell capability.
        // Other implicit branches require complete original graph/coverage authority.
        guard OriginalImplicitCurveSnapshotProvider.supports(curve) else { return nil }
        // FIXME(INCOMPLETE_IMPLEMENTATION): This producer currently admits finite
        // nonperiodic Native targets. Other target families require their own complete
        // graph-family and checked numerical correspondence before this dispatch.
        guard case .bSpline(let native) = surface, !native.isUPeriodic, !native.isVPeriodic else { return nil }
        do {
            try options.validate(tolerance: tolerance)
            let depth = a.effectiveLimits.maximumValueDepth
            try a.checkpoint()
            a.context = a.context.at(stage: .source)
            let sourceLimits = try OriginalSourceIssuanceLimits(
                remainingSourceDepth: a.effectiveLimits.remainingSourceDepth)
            let charts = min(min(a.effectiveLimits.maximumCharts, a.effectiveLimits.maximumSpans), options.maximumSubdivisionCells)
            let limits = try OriginalDomainIdentityLimits(source: sourceLimits, maximumTransportDepth: a.effectiveLimits.maximumTransportDepth,
                maximumCharts: charts, maximumFamilies: min(2, a.effectiveLimits.maximumFamilies), maximumIdentityProofs: 0)
            let field = try Base(maximumValueDepth: a.effectiveLimits.maximumValueDepth, maximumCoefficientDepth: a.effectiveLimits.maximumCoefficientDepth, using: &a)
            let source = try DefaultOriginalSourceBindingIssuer(provider: OriginalImplicitCurveSnapshotProvider(tolerance: tolerance))
                .bind(curve, limits: sourceLimits, using: &a)
            try a.admitSourceDepth(source.sourceDepth)
            a.context = a.context.retaining(first: .init(source: source))
            let family = try DefaultOriginalFiniteImplicitCurveGraphPreparer()
                .prepare(source: source, field: field, maximumCharts: charts, limits: sourceLimits, using: &a)
            try a.retainStorage(bytes: exactScalarPayloadBytes(count: 1, of: OriginalSourceParameterInterval<OriginalExactScalar>.self))
            a.context = a.context.at(stage: .domain)
            let curveFrame = try frame(source: source, support: [family.support], inherited: family.proofDepth,
                field: field, limits: limits, using: &a)
            let curveRequest: OriginalParameterSelection<Curve,Base>
            if let range = options.curveRange {
                try a.retainStorage(bytes: exactScalarPayloadBytes(count: 1, of: [ExactParameterInterval<OriginalExactScalar>].self))
                try a.retainStorage(bytes: exactScalarPayloadBytes(count: 1, of: ExactParameterInterval<OriginalExactScalar>.self))
                curveRequest = try curveFrame.selection(intervals: [[interval(range, field: field, using: &a)]],
                    limits: limits, using: &a)
            } else { curveRequest = try curveFrame.fullSelection(limits: limits, using: &a) }

            a.context = a.context.retaining(first: .init(selection: curveRequest))
            a.context = a.context.at(stage: .source)
            let target = try DefaultOriginalSourceBindingIssuer(provider: OriginalBSplineSurfaceSnapshotProvider(tolerance: tolerance))
                .bind(native, limits: sourceLimits, using: &a)
            try a.admitSourceDepth(target.sourceDepth)
            a.context = a.context.retaining(second: .init(source: target))
            let targetFamily = try DefaultOriginalFiniteBSplineChartPreparer<Surface>()
                .prepare(source: target, field: field, maximumCharts: charts, limits: sourceLimits, using: &a)
            a.context = a.context.at(stage: .domain)
            let targetFrame = try frame(source: target, support: targetFamily.support,
                inherited: ExactScalarDepth(value: 0, coefficient: 0), field: field, limits: limits, using: &a)
            let full = try targetFrame.fullSelection(limits: limits, using: &a)
            let targetRequest: OriginalParameterSelection<Surface,Base>
            if options.surfaceURange != nil || options.surfaceVRange != nil {
                try a.retainStorage(bytes: exactScalarPayloadBytes(count: 2, of: [ExactParameterInterval<OriginalExactScalar>].self))
                var axes: [[ExactParameterInterval<OriginalExactScalar>]] = []; axes.reserveCapacity(2)
                for axis in 0..<2 {
                    try a.consumeWork(1)
                    let selected = axis == 0 ? options.surfaceURange : options.surfaceVRange
                    if let selected {
                        try a.retainStorage(bytes: exactScalarPayloadBytes(count: 1, of: ExactParameterInterval<OriginalExactScalar>.self))
                        axes.append([try interval(selected, field: field, using: &a)])
                    } else {
                        let retained = full.axes[axis].intervals
                        try a.retainStorage(bytes: exactScalarPayloadBytes(count: retained.count, of: ExactParameterInterval<OriginalExactScalar>.self))
                        axes.append(Array(retained))
                    }
                }
                targetRequest = try targetFrame.selection(intervals: axes, limits: limits, using: &a)
            } else { targetRequest = full }
            a.context = a.context.retaining(second: .init(selection: targetRequest))
            let targetCover = try DefaultOriginalIssuedDomainBinder<Surface,SurfaceChart,Base>()
                .bind(laws: targetFamily.laws, request: targetRequest, limits: limits, using: &a)
            let algebraic = try ExactAlgebraicScalarDomain.base(field: field, maximumExtensionLevel: Int.max, using: &a)
            let first = try DefaultOriginalCompleteCurveGraphFamilyPreparer<Curve,Evidence,OriginalFiniteImplicitCurveGraphCoverage>()
                .prepare(family: family, request: curveRequest, field: algebraic, maximumGraphs: charts, limits: limits, using: &a)
            let second = try DefaultOriginalRationalGraphFamilyPreparer<Surface,SurfaceChart>()
                .prepare(cover: targetCover, field: algebraic, maximumGraphs: charts, limits: limits, using: &a)
            guard first.graphs.count == family.coverage.reductions.count else {
                throw ExactGeometricRelationFailure.invalidCoverage
            }
            for index in first.graphs.indices {
                try a.consumeWork(1)
                let graph = first.graphs[index].original.graph
                guard graph.evidence.cellOrdinal == index,
                    family.coverage.reductions[index].cellOrdinal == index else {
                    throw ExactGeometricRelationFailure.invalidCoverage
                }
                try checkDegree(graph, maximum: min(options.maximumPolynomialDegree, a.effectiveLimits.maximumPolynomialDegree), using: &a)
            }
            for graph in second.graphs { try checkDegree(graph.original.graph, maximum: min(options.maximumPolynomialDegree, a.effectiveLimits.maximumPolynomialDegree), using: &a) }
            let structural = try NativeExactPublicLimits.unboundedStructure(), topology = structural.topology
            let geometryLimits = try ExactGeometricRelationLimits(cells: structural.cells,
                topology: .init(maximumGeneratedCells: topology.maximumGeneratedCells,
                    maximumRootsPerStack: topology.maximumRootsPerStack,
                    maximumClosures: min(topology.maximumClosures, min(options.maximumCandidateCount, a.effectiveLimits.maximumResults)),
                    maximumAttachmentPieces: topology.maximumAttachmentPieces, maximumComponents: topology.maximumComponents),
                maximumStrata: structural.maximumStrata, maximumProjectionSpans: structural.maximumProjectionSpans)
            a.context = a.context.at(stage: .relation)
            let raw = try DefaultOriginalIssuedGraphRelationResolver<Curve,Evidence,CurveCover,Surface,SurfaceLaw,SurfaceCover>()
                .resolve(kind: .curveSurface, first: first, second: second, maximumPairs: charts, limits: limits,
                    cellLimits: geometryLimits.cells, topologyLimits: geometryLimits.topology, using: &a)
            var selected = 0, components = 0
            for pair in raw.pairs {
                try a.consumeWork(1)
                let cells = selected.addingReportingOverflow(pair.relation.selection.cells.count)
                let connected = components.addingReportingOverflow(pair.relation.components.count)
                guard !cells.overflow, !connected.overflow, cells.partialValue <= min(options.maximumCandidateCount, a.effectiveLimits.maximumResults),
                    connected.partialValue <= min(options.maximumCandidateCount, a.effectiveLimits.maximumResults) else { throw ExactScalarFailure.resourceLimit(.work) }
                selected = cells.partialValue; components = connected.partialValue
            }
            try raw.admitProof(limits: limits, using: &a)
            try family.coverage.admitProof(limits: sourceLimits, using: &a)
            let retainedRaw = copy raw
            a.context = a.context.at(stage: .publication)
            let publication = try OriginalIssuedGeometricPublication.resolve(retainedRaw,
                geometryLimits: geometryLimits, maximumPoints: min(options.maximumCandidateCount, a.effectiveLimits.maximumResults),
                transports: { pair in
                    (retainedRaw.first.graphs[pair.firstGraphIndex].original.graph.parameterTransport,
                     retainedRaw.second.graphs[pair.secondGraphIndex].original.graph.parameterTransport)
                }, firstCoordinates: { pair in family.coverage.reductions[pair.firstGraphIndex].originalCoordinates }, using: &a)
            typealias Geometry = OriginalIssuedGeometricRelations<Curve,Evidence,CurveCover,Surface,SurfaceLaw,SurfaceCover>
            try a.retainStorage(bytes: exactScalarPayloadBytes(count: 1, of: Geometry.self))
            let geometry = Geometry(original: copy raw, pairs: publication.pairs, exactPoints: publication.points)
            try a.checkpoint()
            guard retainingRelations || !geometry.hasPositiveDimensionalSolutions else {
                throw KernelError(phase: .geometry, code: .nonDiscreteIntersection, tolerance: tolerance,
                    message: "The original implicit curve relation has positive-dimensional solutions.")
            }
            a.context = a.context.at(stage: .refinement)
            let numeric = try OriginalImplicitCurvePointPublisher<Surface,SurfaceLaw,SurfaceCover>()
                .publish(geometry, field: field, options: options, tolerance: tolerance, limits: limits,
                    maximumDepth: depth, using: &a)
            typealias Receipt = OriginalImplicitCurveRelations<Surface,SurfaceLaw,SurfaceCover>
            try a.retainStorage(bytes: exactScalarPayloadBytes(count: 1, of: Receipt.self))
            let retained = Receipt(issuedGeometry: geometry, geometry: numeric.receipt.geometry)
            a.context = a.context.at(stage: .publication)
            try a.retainStorage(bytes: exactScalarPayloadBytes(count: 1, of: CurveSurfaceIntersectionResult.self))
            let result = CurveSurfaceIntersectionResult(points: numeric.points, overlaps: [],
                originalIssuedGeometricRelation: numeric.receipt.geometry, originalIssuedNumericalPoints: numeric.receipt,
                originalImplicitCurveRelation: retained)
            try a.checkpoint(); return result
        } catch { throw NativeExactGeometryPublicationFailure.published(error, tolerance: tolerance, context: a.context) }
    }

    private func frame<S: Sendable, A: ExactScalarAdmission & ~Copyable>(source: OriginalSourceBinding<S>,
        support: [OriginalSourceParameterInterval<OriginalExactScalar>], inherited: ExactScalarDepth,
        field: Base, limits: OriginalDomainIdentityLimits, using a: inout A) throws -> OriginalParameterFrame<S,Base> {
        try a.retainStorage(bytes: exactScalarPayloadBytes(count: support.count, of: [ExactParameterInterval<OriginalExactScalar>].self))
        try a.retainStorage(bytes: exactScalarPayloadBytes(count: support.count, of: ExactParameterInterval<OriginalExactScalar>.self))
        try a.retainStorage(bytes: exactScalarPayloadBytes(count: support.count, of: OriginalCoordinateSemantics.self))
        var axes: [[ExactParameterInterval<OriginalExactScalar>]] = []; axes.reserveCapacity(support.count)
        for range in support {
            try a.consumeWork(1)
            let depth = try ExactScalarDepth(value: max(inherited.value, range.lower.depth.value, range.upper.depth.value),
                coefficient: max(inherited.coefficient, range.lower.depth.coefficient, range.upper.depth.coefficient))
            axes.append([try .checked(field: field, lower: .finite(range.lower), upper: .finite(range.upper), depth: depth, using: &a)])
        }
        return try DefaultOriginalParameterTransporter<S,Base>().frame(source: source, field: field,
            support: axes, semantics: [OriginalCoordinateSemantics](repeating: .authoredScalar, count: support.count),
            limits: limits, using: &a)
    }

    private func interval<A: ExactScalarAdmission & ~Copyable>(_ value: ScalarInterval,
        field: Base, using a: inout A) throws -> ExactParameterInterval<OriginalExactScalar> {
        try .checked(field: field, lower: .finite(field.binary64(exactly: value.lower, using: &a)),
            upper: .finite(field.binary64(exactly: value.upper, using: &a)),
            depth: .init(value: 0, coefficient: 0), using: &a)
    }

    private func checkDegree<S: Sendable,E: Sendable,A: ExactScalarAdmission & ~Copyable>(
        _ graph: OriginalParametricGraphReceipt<S,Base,E>, maximum: Int, using a: inout A) throws {
        for law in graph.homogeneous { try checkDegree(law, maximum: maximum, using: &a) }
        for condition in graph.conditions { try checkDegree(condition.polynomial, maximum: maximum, using: &a) }
    }

    private func checkDegree<A: ExactScalarAdmission & ~Copyable>(_ law: ExactPolynomial<Base>,
        maximum: Int, using a: inout A) throws {
        for term in law.terms {
            try a.consumeWork(1)
            for power in term.powers {
                try a.consumeWork(1)
                guard power <= maximum else { throw ExactScalarFailure.resourceLimit(.work) }
            }
        }
    }
}
