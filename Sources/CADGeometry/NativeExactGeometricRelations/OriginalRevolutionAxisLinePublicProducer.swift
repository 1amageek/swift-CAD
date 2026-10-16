import CADCore

/// Completes one finite original axis-line query without approximating the revolution.
struct OriginalRevolutionAxisLinePublicProducer {
    private typealias Base = OriginalExactScalarDomain
    private typealias Surface = OriginalRevolutionAxisGeometricRelations.Surface
    private typealias Selection = OriginalRevolutionAxisGeometricRelations.Selection
    private typealias Line = OriginalLinearCurveSnapshot


    func resolve(curve:Curve3D,surface:Surface3D,options:CurveSurfaceIntersectionOptions,
        tolerance:ModelingTolerance,using a: inout OriginalQueryExecution,
        retainingRelations:Bool = false) throws -> CurveSurfaceIntersectionResult? {
        a.context = a.context.at(stage: .request)
        try a.checkpoint()
        let point:Point3D,direction:Vector3D
        switch curve {
        case .line(let line): point=line.origin;direction=line.direction
        case .analytic(.line(let origin,let vector)): point=origin;direction=vector
        default: return nil
        }
        guard case .procedural(.originalRevolution(let shape)) = surface else { return nil }
        // FIXME(INCOMPLETE_IMPLEMENTATION): Ordinary revolution axis publication
        // initially consumes finite Native generators and signed coordinate axes.
        // General axes, child laws and unbounded requests need complete source intake
        // before this selector may claim the whole revolution family is supported.
        guard case .bSpline = shape.generator.source,case .closed = shape.uDomain,
            let range=options.curveRange,
            let length=coordinateAxisLength(shape:shape,point:point,direction:direction) else { return nil }
        do {
            try options.validate(tolerance:tolerance)
            let depth=a.effectiveLimits.maximumValueDepth
            try a.checkpoint()
            a.context = a.context.at(stage: .source)
            let sourceLimits=try OriginalSourceIssuanceLimits(
                remainingSourceDepth: a.effectiveLimits.remainingSourceDepth)
            guard sourceLimits.remainingSourceDepth >= 2 else { throw OriginalSourceIssuanceFailure.sourceDepthLimit }
            let charts=min(min(a.effectiveLimits.maximumCharts, a.effectiveLimits.maximumSpans),options.maximumSubdivisionCells)
            let limits=try OriginalDomainIdentityLimits(source:sourceLimits,maximumTransportDepth: a.effectiveLimits.maximumTransportDepth,
                maximumCharts:charts,maximumFamilies: min(2, a.effectiveLimits.maximumFamilies),maximumIdentityProofs:0)
            let f=try Base(maximumValueDepth: a.effectiveLimits.maximumValueDepth, maximumCoefficientDepth: a.effectiveLimits.maximumCoefficientDepth,using:&a)
            let line=try DefaultOriginalSourceBindingIssuer(provider:OriginalLinearCurveSnapshotProvider(tolerance:tolerance))
                .bind(curve,limits:sourceLimits,using:&a)
            try a.admitSourceDepth(line.sourceDepth)
            a.context = a.context.retaining(first: .init(source: line))
            a.context = a.context.at(stage: .domain)
            let lineDomain=DefaultOriginalLinearDomainIssuer<Line,Base>()
            let lineFrame=try lineDomain.frame(source:line,field:f,limits:limits,using:&a)
            try a.retainStorage(bytes:exactScalarPayloadBytes(count:1,of:[ExactParameterInterval<OriginalExactScalar>].self))
            try a.retainStorage(bytes:exactScalarPayloadBytes(count:1,of:ExactParameterInterval<OriginalExactScalar>.self))
            let lineRequest=try lineFrame.selection(intervals:[[interval(range,field:f,using:&a)]],limits:limits,using:&a)
            a.context = a.context.retaining(first: .init(selection: lineRequest))
            a.context = a.context.at(stage: .source)
            let lineChart=try line.chart(OriginalLinearChartSelection(lower:range.lower,upper:range.upper),limits:sourceLimits,using:&a)
            let lineLaw=try DefaultOriginalLinearChartIssuer<Line,Base>()
                .issue(source:line,chart:lineChart,field:f,limits:sourceLimits,using:&a)
            try a.retainStorage(bytes:exactScalarPayloadBytes(count:1,of:OriginalRationalChartReceipt<Line,OriginalLinearChartSelection,Base>.self))
            let lineCover=try DefaultOriginalIssuedDomainBinder<Line,OriginalLinearChartSelection,Base>()
                .bind(laws:[lineLaw],request:lineRequest,limits:limits,using:&a)
            let field=try ExactAlgebraicScalarDomain.base(field:f,maximumExtensionLevel:Int.max,using:&a)
            let first=try DefaultOriginalRationalGraphFamilyPreparer<Line,OriginalLinearChartSelection>()
                .prepare(cover:lineCover,field:field,maximumGraphs:charts,limits:limits,using:&a)

            a.context = a.context.at(stage: .source)
            let source=try DefaultOriginalSourceBindingIssuer(provider:OriginalRevolutionSnapshotProvider(
                child:OriginalNativeCurveFamilySnapshotProvider(tolerance:tolerance),field:f,tolerance:tolerance))
                .bind(shape,limits:sourceLimits,using:&a)
            try a.admitSourceDepth(source.sourceDepth)
            a.context = a.context.retaining(second: .init(source: source))
            let generator=source.original.originalGenerator
            let child=try DefaultOriginalFiniteBSplineChartPreparer<BSplineCurve3D>()
                .prepare(source:generator.original.originalChild,field:f,maximumCharts:charts,
                    limits:.init(remainingSourceDepth:sourceLimits.remainingSourceDepth-2),using:&a)
            let directed=try DefaultOriginalFiniteTraversalChartPreparer<OriginalTraversalSpanSnapshot<BSplineCurve3D>,OriginalBSplineChartSelection,Base>()
                .prepare(source:generator,children:child.laws,field:f,coefficients:DefaultOriginalSourceCoefficientImporter<Base>(),
                    maximumCharts:charts,limits:.init(remainingSourceDepth:sourceLimits.remainingSourceDepth-1),using:&a)
            let family=try DefaultOriginalFiniteRevolutionLawPreparer<Surface,Selection,Base>()
                .prepare(source:source,generators:directed,field:f,axisLength:f.binary64(exactly:length,using:&a),
                    maximumCharts:charts,limits:sourceLimits,using:&a)
            a.context = a.context.at(stage: .domain)
            let issuer=DefaultOriginalRevolutionDomainIssuer<Surface,Selection,Base>()
            let frame=try issuer.frame(family:family,limits:limits,using:&a)
            let full=try frame.fullSelection(limits:limits,using:&a)
            let request:OriginalParameterSelection<Surface,Base>
            if options.surfaceURange != nil || options.surfaceVRange != nil {
                try a.retainStorage(bytes:exactScalarPayloadBytes(count:2,of:[ExactParameterInterval<OriginalExactScalar>].self))
                var axes:[[ExactParameterInterval<OriginalExactScalar>]]=[];axes.reserveCapacity(2)
                for axis in 0..<2 {
                    if let selected=axis == 0 ? options.surfaceURange:options.surfaceVRange {
                        try a.retainStorage(bytes:exactScalarPayloadBytes(count:1,of:ExactParameterInterval<OriginalExactScalar>.self))
                        axes.append([try interval(selected,field:f,using:&a)])
                    } else {
                        let retained=full.axes[axis].intervals
                        try a.retainStorage(bytes:exactScalarPayloadBytes(count:retained.count,of:ExactParameterInterval<OriginalExactScalar>.self))
                        axes.append(Array(retained))
                    }
                }
                request=try frame.selection(intervals:axes,limits:limits,using:&a)
            } else { request=full }
            a.context = a.context.retaining(second: .init(selection: request))
            let cover=try issuer.issue(request:request,family:family,limits:limits,using:&a)
            for graph in first.graphs { try checkDegree(graph.original.graph,maximum:min(options.maximumPolynomialDegree, a.effectiveLimits.maximumPolynomialDegree),using:&a) }
            let unbounded=try NativeExactPublicLimits.unboundedStructure(),topology=unbounded.topology
            let geometryLimits=try ExactGeometricRelationLimits(cells:unbounded.cells,
                topology:.init(maximumGeneratedCells:topology.maximumGeneratedCells,maximumRootsPerStack:topology.maximumRootsPerStack,
                    maximumClosures:min(topology.maximumClosures,min(options.maximumCandidateCount, a.effectiveLimits.maximumResults)),
                    maximumAttachmentPieces:topology.maximumAttachmentPieces,maximumComponents:topology.maximumComponents),
                maximumStrata:unbounded.maximumStrata,maximumProjectionSpans:unbounded.maximumProjectionSpans)
            a.context = a.context.at(stage: .relation)
            let relation=try OriginalRevolutionAxisGeometricRelations.Original.resolve(first:first,cover:cover,
                maximumPairs:charts,maximumPolynomialDegree:min(options.maximumPolynomialDegree, a.effectiveLimits.maximumPolynomialDegree),limits:limits,cellLimits:geometryLimits.cells,
                topologyLimits:geometryLimits.topology,using:&a)
            var selected=0,components=0
            for pair in relation.pairs {
                try a.consumeWork(1)
                let cells=selected.addingReportingOverflow(pair.relation.selection.cells.count)
                let connected=components.addingReportingOverflow(pair.relation.components.count)
                guard !cells.overflow,!connected.overflow,cells.partialValue <= min(options.maximumCandidateCount, a.effectiveLimits.maximumResults),
                    connected.partialValue <= min(options.maximumCandidateCount, a.effectiveLimits.maximumResults) else { throw ExactScalarFailure.resourceLimit(.work) }
                selected=cells.partialValue;components=connected.partialValue
            }
            a.context = a.context.at(stage: .publication)
            let geometry=try OriginalRevolutionAxisGeometricRelations.resolve(relation,limits:limits,
                geometryLimits:geometryLimits,maximumPoints:min(options.maximumCandidateCount, a.effectiveLimits.maximumResults),using:&a)
            if !retainingRelations && geometry.hasPositiveDimensionalSolutions {
                throw KernelError(phase:.geometry,code:.nonDiscreteIntersection,tolerance:tolerance,
                    message:"The original axis query retains a positive-dimensional parameter relation.")
            }
            // FIXME(INCOMPLETE_IMPLEMENTATION): The bare axis-line entry has no
            // certified isolated numerical publisher yet. Nonempty isolated-only
            // relations must fail until every original tuple can be published.
            if !retainingRelations && !geometry.isEmpty {
                throw KernelError(phase:.geometry,code:.unsupportedCapability,tolerance:tolerance,
                    message:"Isolated original axis contacts require certified numerical publication.")
            }
            a.context = a.context.at(stage: .publication)
            try a.retainStorage(bytes:exactScalarPayloadBytes(count:1,of:CurveSurfaceIntersectionResult.self))
            let result=CurveSurfaceIntersectionResult(points:[],overlaps:[],originalIssuedGeometricRelation:geometry,
                originalRevolutionAxisRelation:geometry)
            try a.checkpoint();return result
        } catch { throw NativeExactGeometryPublicationFailure.published(error,tolerance:tolerance,context:a.context) }
    }

    private func coordinateAxisLength(shape:OriginalRevolutionSurface3D,point:Point3D,direction:Vector3D) -> Double? {
        let axis=shape.axisDirection,origin=shape.axisOrigin
        if axis.x != 0,axis.y == 0,axis.z == 0,direction.x != 0,direction.y == 0,direction.z == 0,
            point.y == origin.y,point.z == origin.z { return abs(axis.x) }
        if axis.y != 0,axis.x == 0,axis.z == 0,direction.y != 0,direction.x == 0,direction.z == 0,
            point.x == origin.x,point.z == origin.z { return abs(axis.y) }
        if axis.z != 0,axis.x == 0,axis.y == 0,direction.z != 0,direction.x == 0,direction.y == 0,
            point.x == origin.x,point.y == origin.y { return abs(axis.z) }
        return nil
    }

    private func checkDegree<S:Sendable,E:Sendable,A:ExactScalarAdmission & ~Copyable>(
        _ graph:OriginalParametricGraphReceipt<S,Base,E>,maximum:Int,using a:inout A) throws {
        for law in graph.homogeneous { try check(law,maximum:maximum,using:&a) }
        for condition in graph.conditions { try check(condition.polynomial,maximum:maximum,using:&a) }
        for law in graph.parameterTransport.numerators { try check(law,maximum:maximum,using:&a) }
        for law in graph.parameterTransport.denominators { try check(law,maximum:maximum,using:&a) }
    }
    private func check<A:ExactScalarAdmission & ~Copyable>(_ law:ExactPolynomial<Base>,maximum:Int,using a:inout A) throws {
        for term in law.terms {
            try a.consumeWork(1)
            guard term.powers.allSatisfy({ $0 <= maximum }) else { throw ExactScalarFailure.resourceLimit(.work) }
        }
    }
    private func interval<A:ExactScalarAdmission & ~Copyable>(_ range:ScalarInterval,field:Base,
        using a:inout A) throws -> ExactParameterInterval<OriginalExactScalar> {
        let lower=try field.binary64(exactly:range.lower,using:&a),upper=try field.binary64(exactly:range.upper,using:&a)
        return try .checked(field:field,lower:.finite(lower),upper:.finite(upper),includesLower:true,includesUpper:true,
            depth:.init(value:max(lower.depth.value,upper.depth.value),coefficient:max(lower.depth.coefficient,upper.depth.coefficient)),using:&a)
    }
}
