import CADCore

/// Publishes the original Coons/plane product through the existing issued graph path.
struct OriginalRetainedCoonsPlanePublicProducer {
    private typealias Base = OriginalExactScalarDomain
    private typealias Source = OriginalCoonsAtlasSnapshot

    func resolve(first: Surface3D, second: Surface3D,
        firstBox: SurfaceParameterBox? = nil, secondBox: SurfaceParameterBox? = nil,
        options: SurfaceSurfaceIntersectionOptions, tolerance: ModelingTolerance,
        includeRelations: Bool = false, using a: inout OriginalQueryExecution)
        throws -> SurfaceSurfaceIntersectionResult? {
        a.context = a.context.at(stage: .request)
        try a.checkpoint()
        let coons: OriginalCoonsSurface3D, plane: Surface3D, planeFirst: Bool
        let coonsBox: SurfaceParameterBox?, planeBox: SurfaceParameterBox?
        if case .procedural(.originalCoons(let host)) = first {
            coons = host; plane = second; planeFirst = false
            coonsBox = firstBox; planeBox = secondBox
        } else if case .procedural(.originalCoons(let host)) = second {
            coons = host; plane = first; planeFirst = true
            coonsBox = secondBox; planeBox = firstBox
        } else { return nil }
        let normal: Vector3D
        switch plane {
        case .plane(let p) where p.uDirection == nil: normal = p.normal
        case .analytic(.plane(_,let n)): normal = n
        default: return nil
        }
        // FIXME(INCOMPLETE_IMPLEMENTATION): Ordinary Coons/plane SSI currently
        // issues axis-normal plane bases. Other original bases must retain their
        // exact algebraic lengths before this selector claims general coverage.
        let length: Double
        if normal.x != 0, normal.y == 0, normal.z == 0 { length = abs(normal.x) }
        else if normal.y != 0, normal.x == 0, normal.z == 0 { length = abs(normal.y) }
        else if normal.z != 0, normal.x == 0, normal.y == 0 { length = abs(normal.z) }
        else { return nil }
        do {
            try options.validate(tolerance: tolerance)
            let depth = a.effectiveLimits.maximumValueDepth
            try a.checkpoint()
            a.context = a.context.at(stage: .source)
            let sourceLimits = try OriginalSourceIssuanceLimits(remainingSourceDepth:
                a.effectiveLimits.remainingSourceDepth)
            let charts = min(min(a.effectiveLimits.maximumCharts, a.effectiveLimits.maximumSpans), options.maximumSubdivisionCells)
            let limits = try OriginalDomainIdentityLimits(source: sourceLimits,
                maximumTransportDepth: a.effectiveLimits.maximumTransportDepth, maximumCharts: charts,
                maximumFamilies: min(2, a.effectiveLimits.maximumFamilies), maximumIdentityProofs: 0)
            let f = try Base(maximumValueDepth: a.effectiveLimits.maximumValueDepth, maximumCoefficientDepth: a.effectiveLimits.maximumCoefficientDepth, using: &a)
            let source = try DefaultOriginalSourceBindingIssuer(provider:
                OriginalCoonsAtlasSnapshotProvider(field: f, tolerance: tolerance))
                .bind(coons, limits: sourceLimits, using: &a)
            try a.admitSourceDepth(source.sourceDepth)
            a.context = a.context.retaining(first: planeFirst ? nil : .init(source: source), second: planeFirst ? .init(source: source) : nil)
            let family = try DefaultOriginalFiniteRetainedSurfaceChartPreparer<Source>()
                .prepare(source: source, maximumCharts: charts, limits: sourceLimits, using: &a)
            a.context = a.context.at(stage: .domain)
            let domain = DefaultOriginalRetainedSurfaceDomainIssuer<Source>()
            let frame = try domain.frame(family: family, limits: limits, using: &a)
            let request = try selection(frame, box: coonsBox, field: f, limits: limits, using: &a)
            a.context = a.context.retaining(first: planeFirst ? nil : .init(selection: request), second: planeFirst ? .init(selection: request) : nil)
            let cover = try DefaultOriginalIssuedDomainBinder().bind(laws: family.laws,
                request: request, limits: limits, using: &a)
            let field = try ExactAlgebraicScalarDomain.base(field: f, maximumExtensionLevel: depth, using: &a)
            let graphs = try DefaultOriginalRationalGraphFamilyPreparer().prepare(cover: cover,
                field: field, maximumGraphs: charts, limits: limits, using: &a)
            a.context = a.context.at(stage: .source)
            let target = try DefaultOriginalSourceBindingIssuer(provider: OriginalPlaneSnapshotProvider(tolerance: tolerance))
                .bind(plane, limits: sourceLimits, using: &a)
            try a.admitSourceDepth(target.sourceDepth)
            a.context = a.context.retaining(first: planeFirst ? .init(source: target) : nil, second: planeFirst ? nil : .init(source: target))
            let exactLength = try f.binary64(exactly: length, using: &a)
            let basis = try DefaultOriginalPlaneBasisIssuer<OriginalPlaneSnapshot,Base>()
                .issue(source: target, field: f, firstLength: exactLength, normalLength: exactLength,
                    limits: sourceLimits, using: &a)
            a.context = a.context.at(stage: .domain)
            let planeDomain = DefaultOriginalPlaneDomainIssuer<OriginalPlaneSnapshot,Base>()
            let planeFrame = try planeDomain.frame(basis: basis, limits: limits, using: &a)
            let planeRequest = try selection(planeFrame, box: planeBox, field: f, limits: limits, using: &a)
            a.context = a.context.retaining(first: planeFirst ? .init(selection: planeRequest) : nil, second: planeFirst ? nil : .init(selection: planeRequest))
            let planeCover = try planeDomain.issue(request: planeRequest, basis: basis, limits: limits, using: &a)
            let planeGraph = try DefaultOriginalPlaneGraphCompiler<OriginalPlaneSnapshot>()
                .compile(cover: planeCover, field: field, limits: limits, using: &a)
            let geometryLimits = try NativeExactPublicLimits.unboundedStructure()
            a.context = a.context.at(stage: .relation)
            let original = try DefaultOriginalSurfacePlaneRelationResolver().resolve(surface: graphs,
                plane: planeGraph, planeFirst: planeFirst, maximumPairs: charts, limits: limits,
                cellLimits: geometryLimits.cells, topologyLimits: geometryLimits.topology, using: &a)
            var components = 0
            for pair in original.pairs {
                try a.consumeWork(1)
                let sum = components.addingReportingOverflow(pair.relation.components.count)
                guard !sum.overflow, sum.partialValue <= min(options.maximumSeedCount, a.effectiveLimits.maximumResults) else {
                    throw ExactScalarFailure.resourceLimit(.work)
                }
                components = sum.partialValue
            }
            a.context = a.context.at(stage: .publication)
            let publication = try OriginalIssuedGeometricPublication.resolve(original,
                geometryLimits: geometryLimits, maximumPoints: min(options.maximumSeedCount, a.effectiveLimits.maximumResults),
                transports: { pair in
                    let index = planeFirst ? pair.secondGraphIndex : pair.firstGraphIndex
                    let transport = graphs.graphs[index].original.graph.parameterTransport
                    return planeFirst ? (nil,transport) : (transport,nil)
                }, using: &a)
            try a.retainStorage(bytes: exactScalarPayloadBytes(count: 1,
                of: OriginalSurfacePlaneGeometricRelations<Source,
                    OriginalRationalChartReceipt<Source,Int,Base>,
                    OriginalIssuedDomainCover<Source,Int,Base>,OriginalPlaneSnapshot>.self))
            a.context = a.context.at(stage: .relation)
            let receipt = OriginalSurfacePlaneGeometricRelations(original: original,
                pairs: publication.pairs, exactPoints: publication.points)
            if !includeRelations, receipt.hasPositiveDimensionalSolutions {
                throw KernelError(phase: .geometry, code: .nonDiscreteIntersection, tolerance: tolerance,
                    message: "The original Coons/plane relation contains a positive-dimensional intersection.")
            }
            // FIXME(INCOMPLETE_IMPLEMENTATION): The bare ordinary SSI array has
            // no isolated-point publisher for this mixed-source owner yet. Rich
            // results retain exact points; bare nonempty singleton results must
            // fail until numerical original-UV representatives are published.
            if !includeRelations, !receipt.isEmpty {
                throw KernelError(phase: .geometry, code: .unsupportedCapability, tolerance: tolerance,
                    message: "Isolated Coons/plane contacts require numerical point publication.")
            }
            a.context = a.context.at(stage: .publication)
            try a.retainStorage(bytes: exactScalarPayloadBytes(count: 1, of: SurfaceSurfaceIntersectionResult.self))
            let result = SurfaceSurfaceIntersectionResult(intersections: [], originalIssuedGeometricRelation: receipt)
            try a.checkpoint()
            return result
        } catch { throw NativeExactGeometryPublicationFailure.published(error, tolerance: tolerance, context: a.context) }
    }

    private func selection<S: Sendable>(_ frame: OriginalParameterFrame<S,Base>,
        box: SurfaceParameterBox?, field: Base, limits: OriginalDomainIdentityLimits,
        using a: inout OriginalQueryExecution) throws -> OriginalParameterSelection<S,Base> {
        guard let box else { return try frame.fullSelection(limits: limits, using: &a) }
        try a.retainStorage(bytes: exactScalarPayloadBytes(count: 2, of: [ExactParameterInterval<OriginalExactScalar>].self))
        try a.retainStorage(bytes: exactScalarPayloadBytes(count: 2, of: ExactParameterInterval<OriginalExactScalar>.self))
        return try frame.selection(intervals: [[interval(box.u, field: field, using: &a)],
            [interval(box.v, field: field, using: &a)]], limits: limits, using: &a)
    }

    private func interval(_ range: ScalarInterval, field: Base,
        using a: inout OriginalQueryExecution) throws -> ExactParameterInterval<OriginalExactScalar> {
        let lo = try field.binary64(exactly: range.lower, using: &a)
        let hi = try field.binary64(exactly: range.upper, using: &a)
        return try .checked(field: field, lower: .finite(lo), upper: .finite(hi),
            includesLower: true, includesUpper: true,
            depth: .init(value: max(lo.depth.value,hi.depth.value),
                coefficient: max(lo.depth.coefficient,hi.depth.coefficient)), using: &a)
    }
}
