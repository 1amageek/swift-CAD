import CADCore

/// Publishes the original Rolling-ball/plane product through the existing issued graph path.
struct OriginalRetainedRollingPlanePublicProducer {
    private typealias Base = OriginalExactScalarDomain
    private typealias Source = OriginalGraphRollingBallSnapshot

    func resolve(first: Surface3D, second: Surface3D,
        firstBox: SurfaceParameterBox? = nil, secondBox: SurfaceParameterBox? = nil,
        options: SurfaceSurfaceIntersectionOptions, tolerance: ModelingTolerance,
        includeRelations: Bool = false, using a: inout OriginalQueryExecution)
        throws -> SurfaceSurfaceIntersectionResult? {
        a.context = a.context.at(stage: .request)
        try a.checkpoint()
        let rolling: RollingBallBlendSurface3D, plane: Surface3D, planeFirst: Bool
        let rollingBox: SurfaceParameterBox?, planeBox: SurfaceParameterBox?
        if case .procedural(.rollingBall(let host)) = first {
            rolling = host; plane = second; planeFirst = false
            rollingBox = firstBox; planeBox = secondBox
        } else if case .procedural(.rollingBall(let host)) = second {
            rolling = host; plane = first; planeFirst = true
            rollingBox = secondBox; planeBox = firstBox
        } else { return nil }
        let normal: Vector3D
        switch plane {
        case .plane(let p) where p.uDirection == nil: normal = p.normal
        case .analytic(.plane(_,let n)): normal = n
        default: return nil
        }
        // FIXME(INCOMPLETE_IMPLEMENTATION): Ordinary Rolling-ball/plane SSI currently
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
                OriginalGraphRollingBallSnapshotProvider(field:f)).bind(rolling,limits:sourceLimits,using:&a)
            try a.admitSourceDepth(source.sourceDepth)
            a.context = a.context.retaining(first: planeFirst ? nil : .init(source: source), second: planeFirst ? .init(source: source) : nil)
            let children = try OriginalSourceIssuanceLimits(remainingSourceDepth:sourceLimits.remainingSourceDepth-1)
            let child = DefaultOriginalRollingBallCurveGraphPreparer()
            let center = try child.prepare(source:source.original.originalCenter,field:f,maximumCharts:charts,limits:children,using:&a)
            let first = try child.prepare(source:source.original.originalFirstContact,field:f,maximumCharts:charts,limits:children,using:&a)
            let second = try child.prepare(source:source.original.originalSecondContact,field:f,maximumCharts:charts,limits:children,using:&a)
            typealias ChildEvidence = OriginalRollingBallCurveGraphEvidence
            typealias ChildCover = OriginalRollingBallCurveGraphCoverage
            let family = try DefaultOriginalFiniteRollingBallGraphPreparer<Source,ChildEvidence,ChildCover>()
                .prepare(source:source,center:center,first:first,second:second,maximumCharts:charts,limits:sourceLimits,using:&a)
            a.context = a.context.at(stage: .domain)
            let domain = DefaultOriginalRollingBallGraphDomainIssuer<Source,ChildEvidence,ChildCover>()
            let frame = try domain.frame(family:family,limits:limits,using:&a)
            let request = try selection(frame,box:rollingBox,field:f,limits:limits,using:&a)
            a.context = a.context.retaining(first: planeFirst ? nil : .init(selection: request), second: planeFirst ? .init(selection: request) : nil)
            let cover = try domain.issue(request:request,family:family,limits:limits,using:&a)
            let field = try ExactAlgebraicScalarDomain.base(field:f,maximumExtensionLevel:depth,using:&a)
            // FIXME(INCOMPLETE_IMPLEMENTATION): Ordinary rolling/plane SSI currently
            // consumes uniquely reducible child witnesses and rational constant roots.
            // General algebraic/periodic rail families require complete retained lifts
            // before this production route can claim rolling-family coverage.
            let graphs = try DefaultOriginalRollingBallGraphFamilyPreparer<Source,ChildEvidence,ChildCover>()
                .prepare(cover:cover,field:field,maximumGraphs:charts,limits:limits,using:&a)
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
            let receipt = try DefaultOriginalRollingPlaneSectionResolver().resolve(surface:graphs,plane:planeGraph,
                planeFirst:planeFirst,maximumPieces:min(options.maximumSeedCount, a.effectiveLimits.maximumResults),limits:limits,cellLimits:geometryLimits.cells,using:&a)
            if !includeRelations, receipt.hasPositiveDimensionalSolutions {
                throw KernelError(phase: .geometry, code: .nonDiscreteIntersection, tolerance: tolerance,
                    message: "The original Rolling-ball/plane relation contains a positive-dimensional intersection.")
            }
            // FIXME(INCOMPLETE_IMPLEMENTATION): The bare ordinary SSI array has
            // no isolated-point publisher for this mixed-source owner yet. Rich
            // results retain exact points; bare nonempty singleton results must
            // fail until numerical original-UV representatives are published.
            if !includeRelations, !receipt.isEmpty {
                throw KernelError(phase: .geometry, code: .unsupportedCapability, tolerance: tolerance,
                    message: "Isolated Rolling-ball/plane contacts require numerical point publication.")
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
