import CADCore

/// One original lift/plane solve under the composing public execution.
struct OriginalRetainedLiftPlanePublicProducer {
    func resolve(curve: Curve3D, surface: Surface3D, options: CurveSurfaceIntersectionOptions,
        tolerance: ModelingTolerance, using a: inout OriginalQueryExecution,
        retainingRelations: Bool = false) throws -> CurveSurfaceIntersectionResult? {
        a.context = a.context.at(stage: .request)
        try a.checkpoint()
        guard case .surfaceLift(let input) = curve, input.exactBSplineImage == nil else { return nil }
        let normal: Vector3D
        switch surface {
        case .plane(let plane) where plane.uDirection == nil: normal = plane.normal
        case .analytic(.plane(_,let n)): normal = n
        default: return nil
        }
        // FIXME(INCOMPLETE_IMPLEMENTATION): The ordinary lift/plane dispatcher
        // presently issues an exact basis for axis normals only. General normals
        // require their original algebraic lengths before this family is complete.
        let length: Double
        if normal.x != 0 && normal.y == 0 && normal.z == 0 { length = abs(normal.x) }
        else if normal.y != 0 && normal.x == 0 && normal.z == 0 { length = abs(normal.y) }
        else if normal.z != 0 && normal.x == 0 && normal.y == 0 { length = abs(normal.z) }
        else { return nil }
        switch (input.parameterCurve,input.surface) {
        case (.polyline,.procedural(.originalCoons)):
            return try resolve(input:input,surface:surface,options:options,tolerance:tolerance,
                using: &a,retainingRelations:retainingRelations,length:length,
                host:{ OriginalCoonsAtlasSnapshotProvider(field:$0,tolerance:tolerance) })
        case (.polyline,.procedural(.originalBoundaryCorrected)):
            return try resolve(input:input,surface:surface,options:options,tolerance:tolerance,
                using: &a,retainingRelations:retainingRelations,length:length,
                host:{ OriginalBoundaryCorrectionSnapshotProvider(field:$0,tolerance:tolerance) })
        case (.bSpline,.procedural(.originalPlaneDerivative)):
            return try resolve(input:input,surface:surface,options:options,tolerance:tolerance,
                using: &a,retainingRelations:retainingRelations,length:length,
                prepare:{ depth,limits,charts,a in
                    try prepareDerivative(input:input,tolerance:tolerance,depth:depth,
                        limits:limits,charts:charts,using:&a)
                })
        // FIXME(INCOMPLETE_IMPLEMENTATION): Other retained host/pcurve combinations
        // require their complete original source and checked UV reduction before
        // this public entry may accept and publish their whole requested domain.
        default: return nil
        }
    }

    private func resolve<P: OriginalRetainedLiftHostSnapshotting>(input:SurfaceLiftCurve3D,
        surface:Surface3D,options:CurveSurfaceIntersectionOptions,tolerance:ModelingTolerance,
        using a: inout OriginalQueryExecution,retainingRelations:Bool,length:Double,
        host makeHost:(OriginalExactScalarDomain) -> P) throws -> CurveSurfaceIntersectionResult {
        a.context = a.context.at(stage: .request)
        try a.checkpoint()
        return try resolve(input:input,surface:surface,options:options,tolerance:tolerance,
            using: &a,retainingRelations:retainingRelations,length:length,
            prepare:{ depth,sourceLimits,charts,a in
                typealias Source = OriginalPolylineRetainedAtlasLiftSnapshot<P.Source>
                a.context = a.context.at(stage: .source)
                let pcurve = try DefaultOriginalSourceBindingIssuer(provider:OriginalPolylinePcurveSnapshotProvider(
                    maximumValueDepth: a.effectiveLimits.maximumValueDepth, maximumCoefficientDepth: a.effectiveLimits.maximumCoefficientDepth))
                    .bind(input.parameterCurve,limits:sourceLimits,using:&a)
                let f = pcurve.original.originalField
                let provider = OriginalPolylineRetainedAtlasLiftSnapshotProvider(
                    host:makeHost(f),pcurve:pcurve)
                let source = try DefaultOriginalSourceBindingIssuer(provider:provider).bind(input,limits:sourceLimits,using:&a)
                try a.admitSourceDepth(source.sourceDepth)
                a.context = a.context.retaining(first: .init(source: source))
                let host = try DefaultOriginalFiniteRetainedSurfaceChartPreparer<P.Source>()
                    .prepare(source:source.original.originalSurface,maximumCharts:charts,limits:sourceLimits,using:&a)
                let pc = try DefaultOriginalFiniteRetainedCurveChartPreparer<OriginalPolylinePcurveSnapshot>()
                    .prepare(source:pcurve,maximumCharts:charts,limits:sourceLimits,using:&a)
                return try DefaultOriginalFiniteRetainedSurfaceLiftGraphPreparer<Source>()
                    .prepare(source:source,surface:host,pcurve:pc,maximumCharts:charts,limits:sourceLimits,using:&a)
            })
    }

    private func prepareDerivative(input:SurfaceLiftCurve3D,tolerance:ModelingTolerance,depth:Int,
        limits:OriginalSourceIssuanceLimits,charts:Int,using a:inout OriginalQueryExecution)
        throws -> OriginalFiniteRetainedSurfaceLiftGraphs<OriginalNativePcurveRetainedAtlasLiftSnapshot<OriginalPlaneDerivativeSurfaceSnapshot>> {
        typealias Source = OriginalNativePcurveRetainedAtlasLiftSnapshot<OriginalPlaneDerivativeSurfaceSnapshot>
        let f = try OriginalExactScalarDomain(maximumValueDepth: a.effectiveLimits.maximumValueDepth, maximumCoefficientDepth: a.effectiveLimits.maximumCoefficientDepth,using:&a)
        let provider = OriginalNativePcurveRetainedAtlasLiftSnapshotProvider(
            host:OriginalPlaneDerivativeSurfaceSnapshotProvider(field:f,tolerance:tolerance),tolerance:tolerance)
        a.context = a.context.at(stage: .source)
        let source = try DefaultOriginalSourceBindingIssuer(provider:provider).bind(input,limits:limits,using:&a)
        try a.admitSourceDepth(source.sourceDepth)
        a.context = a.context.retaining(first: .init(source: source))
        let host = try DefaultOriginalFiniteRetainedSurfaceChartPreparer<OriginalPlaneDerivativeSurfaceSnapshot>()
            .prepare(source:source.original.originalSurface,maximumCharts:charts,limits:limits,using:&a)
        let pcurve = try DefaultOriginalFiniteBSplineChartPreparer<BSplineCurve2D>()
            .prepare(source:source.original.originalPcurve,field:f,maximumCharts:charts,limits:limits,using:&a)
        return try DefaultOriginalFiniteRetainedSurfaceLiftGraphPreparer<Source>()
            .prepare(source:source,surface:host,pcurve:pcurve,maximumCharts:charts,limits:limits,using:&a)
    }

    private func resolve<Source:OriginalLiftGraphSourceReading>(input:SurfaceLiftCurve3D,
        surface:Surface3D,options:CurveSurfaceIntersectionOptions,tolerance:ModelingTolerance,
        using a: inout OriginalQueryExecution,retainingRelations:Bool,length:Double,
        prepare:(Int,OriginalSourceIssuanceLimits,Int,inout OriginalQueryExecution) throws -> OriginalFiniteRetainedSurfaceLiftGraphs<Source>)
        throws -> CurveSurfaceIntersectionResult {
        a.context = a.context.at(stage: .request)
        try a.checkpoint()
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
            let family = try prepare(depth,sourceLimits,charts,&a)
            let f = family.field
            for graph in family.graphs {
                for law in graph.homogeneous {
                    for term in law.terms {
                        try a.consumeWork(1)
                        guard term.powers.allSatisfy({ $0 <= min(options.maximumPolynomialDegree, a.effectiveLimits.maximumPolynomialDegree) }) else {
                            throw ExactScalarFailure.resourceLimit(.work)
                        }
                    }
                }
            }
            a.context = a.context.at(stage: .domain)
            let issuer = DefaultOriginalRetainedSurfaceLiftDomainIssuer<Source>()
            let frame = try issuer.frame(family:family,limits:limits,using:&a)
            let selection = try options.curveRange.map { range in
                try frame.selection(intervals:[[interval(range,field:f,using:&a)]],limits:limits,using:&a)
            } ?? frame.fullSelection(limits:limits,using:&a)
            a.context = a.context.retaining(first: .init(selection: selection))
            let lift = try issuer.issue(request:selection,family:family,limits:limits,using:&a)
            a.context = a.context.at(stage: .source)
            let plane = try DefaultOriginalSourceBindingIssuer(provider:OriginalPlaneSnapshotProvider(tolerance:tolerance))
                .bind(surface,limits:sourceLimits,using:&a)
            try a.admitSourceDepth(plane.sourceDepth)
            a.context = a.context.retaining(second: .init(source: plane))
            let exactLength = try f.binary64(exactly:length,using:&a)
            let basis = try DefaultOriginalPlaneBasisIssuer<OriginalPlaneSnapshot,OriginalExactScalarDomain>()
                .issue(source:plane,field:f,firstLength:exactLength,normalLength:exactLength,limits:sourceLimits,using:&a)
            a.context = a.context.at(stage: .domain)
            let domain = DefaultOriginalPlaneDomainIssuer<OriginalPlaneSnapshot,OriginalExactScalarDomain>()
            let planeFrame = try domain.frame(basis:basis,limits:limits,using:&a)
            let full = try planeFrame.fullSelection(limits:limits,using:&a)
            let planeRequest: OriginalParameterSelection<OriginalPlaneSnapshot,OriginalExactScalarDomain>
            if options.surfaceURange != nil || options.surfaceVRange != nil {
                try a.retainStorage(bytes:exactScalarPayloadBytes(count:2,of:[ExactParameterInterval<OriginalExactScalar>].self))
                var intervals:[[ExactParameterInterval<OriginalExactScalar>]] = [];intervals.reserveCapacity(2)
                for axis in 0..<2 {
                    let selected = axis == 0 ? options.surfaceURange:options.surfaceVRange
                    if let selected {
                        try a.retainStorage(bytes:exactScalarPayloadBytes(count:1,of:ExactParameterInterval<OriginalExactScalar>.self))
                        intervals.append([try interval(selected,field:f,using:&a)])
                    } else {
                        let retained = full.axes[axis].intervals
                        try a.retainStorage(bytes:exactScalarPayloadBytes(count:retained.count,of:ExactParameterInterval<OriginalExactScalar>.self))
                        intervals.append(Array(retained))
                    }
                }
                planeRequest = try planeFrame.selection(intervals:intervals,limits:limits,using:&a)
            } else { planeRequest = full }
            a.context = a.context.retaining(second: .init(selection: planeRequest))
            let cover = try domain.issue(request:planeRequest,basis:basis,limits:limits,using:&a)
            let field = try ExactAlgebraicScalarDomain.base(field:f,maximumExtensionLevel:Int.max,using:&a)
            let target = try DefaultOriginalPlaneGraphCompiler<OriginalPlaneSnapshot>().compile(cover:cover,field:field,limits:limits,using:&a)
            // FIXME(INCOMPLETE_IMPLEMENTATION): Contained-family publication currently
            // accepts the full authored curve and whole plane. Clipped/singular request
            // publication must retain every exact preimage before this branch is general.
            a.context = a.context.at(stage: .relation)
            if options.curveRange == nil, options.surfaceURange == nil, options.surfaceVRange == nil,
                let contained = try DefaultOriginalContainedLiftPlaneResolver().resolve(lift:lift,plane:target,
                    maximumPieces:min(options.maximumCandidateCount, a.effectiveLimits.maximumResults),limits:limits,using:&a) {
                if !retainingRelations && contained.hasPositiveDimensionalSolutions {
                    throw KernelError(phase:.geometry,code:.nonDiscreteIntersection,tolerance:tolerance,
                        message:"The original lift lies in the plane over a positive-dimensional domain.")
                }
                // FIXME(INCOMPLETE_IMPLEMENTATION): The bare ordinary CS API needs a
                // numerical point publisher for isolated-only contained families. Until
                // every singleton is published it must fail, never return an empty array.
                if !retainingRelations && !contained.isEmpty {
                    throw KernelError(phase:.geometry,code:.unsupportedCapability,tolerance:tolerance,
                        message:"Isolated contained-family contacts require exact point publication.")
                }
                a.context = a.context.at(stage: .publication)
                try a.retainStorage(bytes:exactScalarPayloadBytes(count:1,of:CurveSurfaceIntersectionResult.self))
                let result = CurveSurfaceIntersectionResult(points:[],overlaps:[],originalContainedLiftPlaneFamily:contained)
                try a.checkpoint();return result
            }
            let unbounded = try NativeExactPublicLimits.unboundedStructure()
            let topology = unbounded.topology
            let geometry = try ExactGeometricRelationLimits(cells:unbounded.cells,
                topology:.init(maximumGeneratedCells:topology.maximumGeneratedCells,maximumRootsPerStack:topology.maximumRootsPerStack,
                    maximumClosures:min(topology.maximumClosures,min(options.maximumCandidateCount, a.effectiveLimits.maximumResults)),
                    maximumAttachmentPieces:topology.maximumAttachmentPieces,maximumComponents:topology.maximumComponents),
                maximumStrata:unbounded.maximumStrata,maximumProjectionSpans:unbounded.maximumProjectionSpans)
            a.context = a.context.at(stage: .relation)
            let original = try DefaultOriginalLiftPlaneRelationResolver().resolve(lift:lift,plane:target,
                maximumPairs:charts,limits:limits,cellLimits:geometry.cells,topologyLimits:geometry.topology,using:&a)
            var selected = 0,components = 0
            for pair in original.pairs {
                try a.consumeWork(1)
                let nextSelected = selected.addingReportingOverflow(pair.relation.selection.cells.count)
                let nextComponents = components.addingReportingOverflow(pair.relation.components.count)
                guard !nextSelected.overflow,!nextComponents.overflow,
                    nextSelected.partialValue <= min(options.maximumCandidateCount, a.effectiveLimits.maximumResults),nextComponents.partialValue <= min(options.maximumCandidateCount, a.effectiveLimits.maximumResults) else {
                    throw ExactScalarFailure.resourceLimit(.work)
                }
                selected = nextSelected.partialValue;components = nextComponents.partialValue
            }
            a.context = a.context.at(stage: .publication)
            let publication = try OriginalIssuedGeometricPublication.resolve(original,geometryLimits:geometry,
                maximumPoints:min(options.maximumCandidateCount, a.effectiveLimits.maximumResults),
                transports:{ pair in (original.firstGraphs[pair.firstGraphIndex].original.graph.parameterTransport,nil) },
                firstCoordinates:{ pair in original.firstReductions[pair.firstGraphIndex].originalCoordinates },using:&a)
            try a.retainStorage(bytes:exactScalarPayloadBytes(count:1,of:OriginalLiftPlaneGeometricRelations<Source,OriginalPlaneSnapshot>.self))
            a.context = a.context.at(stage: .relation)
            let receipt = OriginalLiftPlaneGeometricRelations(original:original,pairs:publication.pairs,exactPoints:publication.points)
            guard retainingRelations || !receipt.hasPositiveDimensionalSolutions else {
                throw KernelError(phase:.geometry,code:.nonDiscreteIntersection,tolerance:tolerance,
                    message:"The original lift/plane relation contains a positive-dimensional intersection.")
            }
            a.context = a.context.at(stage: .refinement)
            let numeric = try OriginalLiftPlanePointPublisher<Source>().publish(receipt,options:options,tolerance:tolerance,
                limits:limits,maximumDepth:depth,using:&a)
            a.context = a.context.at(stage: .publication)
            try a.retainStorage(bytes:exactScalarPayloadBytes(count:1,of:CurveSurfaceIntersectionResult.self))
            let result = CurveSurfaceIntersectionResult(points:numeric.points,overlaps:[],
                originalIssuedGeometricRelation:numeric.receipt.geometry,originalIssuedNumericalPoints:numeric.receipt)
            try a.checkpoint();return result
        } catch { throw NativeExactGeometryPublicationFailure.published(error,tolerance:tolerance,context:a.context) }
    }

    private func interval<A: ExactScalarAdmission & ~Copyable>(_ range: ScalarInterval,
        field:OriginalExactScalarDomain,using a:inout A) throws -> ExactParameterInterval<OriginalExactScalar> {
        let lower = try field.binary64(exactly:range.lower,using:&a),upper = try field.binary64(exactly:range.upper,using:&a)
        return try .checked(field:field,lower:.finite(lower),upper:.finite(upper),includesLower:true,includesUpper:true,
            depth:.init(value:max(lower.depth.value,upper.depth.value),coefficient:max(lower.depth.coefficient,upper.depth.coefficient)),using:&a)
    }
}
