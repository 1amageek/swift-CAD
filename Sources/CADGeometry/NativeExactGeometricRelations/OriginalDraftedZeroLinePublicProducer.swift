import CADCore

/// Composes the original finite line and zero-draft wall under one public execution.
struct OriginalDraftedZeroLinePublicProducer {
    private typealias Field = OriginalExactScalarDomain
    private typealias Line = OriginalLinearCurveSnapshot
    private typealias Wall = OriginalDraftedRuledSurfaceSnapshot
    private typealias LineLaw = OriginalRationalChartReceipt<Line,OriginalLinearChartSelection,Field>
    private typealias WallLaw = OriginalRationalChartReceipt<Wall,Int,Field>
    private typealias LineCover = OriginalIssuedDomainCover<Line,OriginalLinearChartSelection,Field>
    private typealias WallCover = OriginalIssuedDomainCover<Wall,Int,Field>

    func resolve(curve:Curve3D,surface:Surface3D,options:CurveSurfaceIntersectionOptions,
        tolerance:ModelingTolerance,using a: inout OriginalQueryExecution,
        retainingRelations:Bool = false) throws -> CurveSurfaceIntersectionResult? {
        a.context = a.context.at(stage: .request)
        try a.checkpoint()
        switch curve {
        case .line,.analytic(.line): break
        default: return nil
        }
        guard case .procedural(.originalDrafted(let wall)) = surface else { return nil }
        // FIXME(INCOMPLETE_IMPLEMENTATION): The ordinary line/drafted-wall selector
        // currently consumes only the source-owned exact-zero translation atlas.
        // General draft angles require their complete original position authority.
        guard OriginalDraftedRuledSurfaceSnapshotProvider.supports(wall) else { return nil }
        // FIXME(INCOMPLETE_IMPLEMENTATION): This ordinary producer requires an
        // explicit finite line request. Whole-line source coverage and publication
        // must be composed before an absent line range can use this exact path.
        guard let range = options.curveRange else { return nil }
        do {
            try options.validate(tolerance:tolerance)
            let depth = a.effectiveLimits.maximumValueDepth
            try a.checkpoint()
            a.context = a.context.at(stage: .source)
            let sourceLimits = try OriginalSourceIssuanceLimits(
                remainingSourceDepth: a.effectiveLimits.remainingSourceDepth)
            let charts = min(min(a.effectiveLimits.maximumCharts, a.effectiveLimits.maximumSpans),
                options.maximumSubdivisionCells)
            let limits = try OriginalDomainIdentityLimits(source:sourceLimits,maximumTransportDepth: a.effectiveLimits.maximumTransportDepth,
                maximumCharts:charts,maximumFamilies: min(2, a.effectiveLimits.maximumFamilies),maximumIdentityProofs:0)
            let f = try Field(maximumValueDepth: a.effectiveLimits.maximumValueDepth, maximumCoefficientDepth: a.effectiveLimits.maximumCoefficientDepth,using:&a)
            let line = try DefaultOriginalSourceBindingIssuer(provider:OriginalLinearCurveSnapshotProvider(tolerance:tolerance))
                .bind(curve,limits:sourceLimits,using:&a)
            try a.admitSourceDepth(line.sourceDepth)
            a.context = a.context.retaining(first: .init(source: line))
            a.context = a.context.at(stage: .domain)
            let lineDomain = DefaultOriginalLinearDomainIssuer<Line,Field>()
            let lineFrame = try lineDomain.frame(source:line,field:f,limits:limits,using:&a)
            try a.retainStorage(bytes:exactScalarPayloadBytes(count:1,of:[ExactParameterInterval<OriginalExactScalar>].self))
            try a.retainStorage(bytes:exactScalarPayloadBytes(count:1,of:ExactParameterInterval<OriginalExactScalar>.self))
            let lineRequest = try lineFrame.selection(intervals:[[interval(range,field:f,using:&a)]],limits:limits,using:&a)
            a.context = a.context.retaining(first: .init(selection: lineRequest))
            a.context = a.context.at(stage: .source)
            let chart = try line.chart(OriginalLinearChartSelection(lower:range.lower,upper:range.upper),
                limits:sourceLimits,using:&a)
            let law = try DefaultOriginalLinearChartIssuer<Line,Field>().issue(source:line,chart:chart,
                field:f,limits:sourceLimits,using:&a)
            try a.retainStorage(bytes:exactScalarPayloadBytes(count:1,of:LineLaw.self))
            let lineCover = try DefaultOriginalIssuedDomainBinder<Line,OriginalLinearChartSelection,Field>()
                .bind(laws:[law],request:lineRequest,limits:limits,using:&a)

            a.context = a.context.at(stage: .source)
            let source = try DefaultOriginalSourceBindingIssuer(
                provider:OriginalDraftedRuledSurfaceSnapshotProvider(field:f,tolerance:tolerance))
                .bind(wall,limits:sourceLimits,using:&a)
            try a.admitSourceDepth(source.sourceDepth)
            a.context = a.context.retaining(second: .init(source: source))
            let family = try DefaultOriginalFiniteRetainedSurfaceChartPreparer<Wall>()
                .prepare(source:source,maximumCharts:charts,limits:sourceLimits,using:&a)
            a.context = a.context.at(stage: .domain)
            let wallDomain = DefaultOriginalRetainedSurfaceDomainIssuer<Wall>()
            let wallFrame = try wallDomain.frame(family:family,limits:limits,using:&a)
            let full = try wallFrame.fullSelection(limits:limits,using:&a)
            let wallRequest:OriginalParameterSelection<Wall,Field>
            if options.surfaceURange != nil || options.surfaceVRange != nil {
                try a.retainStorage(bytes:exactScalarPayloadBytes(count:2,of:[ExactParameterInterval<OriginalExactScalar>].self))
                var axes:[[ExactParameterInterval<OriginalExactScalar>]] = [];axes.reserveCapacity(2)
                for axis in 0..<2 {
                    let selected = axis == 0 ? options.surfaceURange:options.surfaceVRange
                    if let selected {
                        try a.retainStorage(bytes:exactScalarPayloadBytes(count:1,of:ExactParameterInterval<OriginalExactScalar>.self))
                        axes.append([try interval(selected,field:f,using:&a)])
                    } else {
                        let retained = full.axes[axis].intervals
                        try a.retainStorage(bytes:exactScalarPayloadBytes(count:retained.count,of:ExactParameterInterval<OriginalExactScalar>.self))
                        axes.append(Array(retained))
                    }
                }
                wallRequest = try wallFrame.selection(intervals:axes,limits:limits,using:&a)
            } else { wallRequest = full }
            a.context = a.context.retaining(second: .init(selection: wallRequest))
            let wallCover = try DefaultOriginalIssuedDomainBinder<Wall,Int,Field>()
                .bind(laws:family.laws,request:wallRequest,limits:limits,using:&a)
            let field = try ExactAlgebraicScalarDomain.base(field:f,maximumExtensionLevel:Int.max,using:&a)
            let first = try DefaultOriginalRationalGraphFamilyPreparer<Line,OriginalLinearChartSelection>()
                .prepare(cover:lineCover,field:field,maximumGraphs:charts,limits:limits,using:&a)
            let second = try DefaultOriginalRationalGraphFamilyPreparer<Wall,Int>()
                .prepare(cover:wallCover,field:field,maximumGraphs:charts,limits:limits,using:&a)
            for graph in first.graphs { try checkDegree(graph.original.graph.homogeneous,maximum:min(options.maximumPolynomialDegree, a.effectiveLimits.maximumPolynomialDegree),using:&a) }
            for graph in second.graphs { try checkDegree(graph.original.graph.homogeneous,maximum:min(options.maximumPolynomialDegree, a.effectiveLimits.maximumPolynomialDegree),using:&a) }
            let unbounded = try NativeExactPublicLimits.unboundedStructure(),topology = unbounded.topology
            let geometryLimits = try ExactGeometricRelationLimits(cells:unbounded.cells,
                topology:.init(maximumGeneratedCells:topology.maximumGeneratedCells,maximumRootsPerStack:topology.maximumRootsPerStack,
                    maximumClosures:min(topology.maximumClosures,min(options.maximumCandidateCount, a.effectiveLimits.maximumResults)),
                    maximumAttachmentPieces:topology.maximumAttachmentPieces,maximumComponents:topology.maximumComponents),
                maximumStrata:unbounded.maximumStrata,maximumProjectionSpans:unbounded.maximumProjectionSpans)
            a.context = a.context.at(stage: .relation)
            let relations = try DefaultOriginalIssuedGraphRelationResolver<Line,LineLaw,LineCover,Wall,WallLaw,WallCover>()
                .resolve(kind:.curveSurface,first:first,second:second,maximumPairs:charts,limits:limits,
                    cellLimits:geometryLimits.cells,topologyLimits:geometryLimits.topology,using:&a)
            var selected = 0,components = 0
            for pair in relations.pairs {
                try a.consumeWork(1)
                let cells = selected.addingReportingOverflow(pair.relation.selection.cells.count)
                let connected = components.addingReportingOverflow(pair.relation.components.count)
                guard !cells.overflow,!connected.overflow,cells.partialValue <= min(options.maximumCandidateCount, a.effectiveLimits.maximumResults),
                    connected.partialValue <= min(options.maximumCandidateCount, a.effectiveLimits.maximumResults) else { throw ExactScalarFailure.resourceLimit(.work) }
                selected = cells.partialValue;components = connected.partialValue
            }
            a.context = a.context.at(stage: .publication)
            let geometry = try DefaultOriginalIssuedGeometricRelationResolver().resolve(relations,limits:limits,
                geometryLimits:geometryLimits,maximumPoints:min(options.maximumCandidateCount, a.effectiveLimits.maximumResults),using:&a)
            guard retainingRelations || !geometry.hasPositiveDimensionalSolutions else {
                throw KernelError(phase:.geometry,code:.nonDiscreteIntersection,tolerance:tolerance,
                    message:"The original line/drafted-wall relation has positive-dimensional solutions.")
            }
            a.context = a.context.at(stage: .refinement)
            let numeric = try OriginalRationalGraphPointPublisher<Line,LineLaw,LineCover,Wall,WallLaw,WallCover>()
                .publish(geometry,field:f,options:options,tolerance:tolerance,limits:limits,maximumDepth:depth,using:&a)
            a.context = a.context.at(stage: .publication)
            try a.retainStorage(bytes:exactScalarPayloadBytes(count:1,of:CurveSurfaceIntersectionResult.self))
            let result = CurveSurfaceIntersectionResult(points:numeric.points,overlaps:[],
                originalIssuedGeometricRelation:numeric.receipt.geometry,originalIssuedNumericalPoints:numeric.receipt)
            try a.checkpoint();return result
        } catch { throw NativeExactGeometryPublicationFailure.published(error,tolerance:tolerance,context:a.context) }
    }

    private func checkDegree<A:ExactScalarAdmission & ~Copyable>(_ laws:[ExactPolynomial<Field>],
        maximum:Int,using a:inout A) throws {
        for law in laws { for term in law.terms {
            try a.consumeWork(1)
            guard term.powers.allSatisfy({ $0 <= maximum }) else { throw ExactScalarFailure.resourceLimit(.work) }
        } }
    }

    private func interval<A:ExactScalarAdmission & ~Copyable>(_ range:ScalarInterval,field:Field,
        using a:inout A) throws -> ExactParameterInterval<OriginalExactScalar> {
        let lower = try field.binary64(exactly:range.lower,using:&a),upper = try field.binary64(exactly:range.upper,using:&a)
        return try .checked(field:field,lower:.finite(lower),upper:.finite(upper),includesLower:true,includesUpper:true,
            depth:.init(value:max(lower.depth.value,upper.depth.value),coefficient:max(lower.depth.coefficient,upper.depth.coefficient)),using:&a)
    }
}
