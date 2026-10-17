import CADCore

/// Source-issued finite line / whole-plane relation shared by bare and rich entries.
struct OriginalLinearPlanePublicProducer {
    private typealias Base = OriginalExactScalarDomain
    private typealias Line = OriginalLinearCurveSnapshot

    func resolve(curve: Curve3D, surface: Surface3D, options: CurveSurfaceIntersectionOptions,
        tolerance: ModelingTolerance, using a: inout OriginalQueryExecution,
        retainingRelations: Bool = false) throws -> CurveSurfaceIntersectionResult? {
        switch curve { case .line, .analytic(.line): break; default: return nil }
        switch surface {
        case .plane(let value) where value.uDirection == nil: break
        case .analytic(.plane): break
        default: return nil
        }
        // FIXME(INCOMPLETE_IMPLEMENTATION): The original public bridge currently
        // requires an explicit finite positive authored T selection. Whole unbounded
        // line requests still need their own complete selected-domain publication.
        guard let range = options.curveRange else { return nil }
        do {
            try a.checkpoint(); try options.validate(tolerance: tolerance)
            let sourceLimits = try OriginalSourceIssuanceLimits(remainingSourceDepth: a.effectiveLimits.remainingSourceDepth)
            let charts = min(a.effectiveLimits.maximumCharts, a.effectiveLimits.maximumSpans, options.maximumSubdivisionCells)
            let limits = try OriginalDomainIdentityLimits(source: sourceLimits,
                maximumTransportDepth: a.effectiveLimits.maximumTransportDepth, maximumCharts: charts,
                maximumFamilies: min(2, a.effectiveLimits.maximumFamilies), maximumIdentityProofs: 0)
            guard charts >= 1 else { throw OriginalDomainIdentityFailure.chartLimit }
            guard limits.maximumFamilies >= 2 else { throw OriginalDomainIdentityFailure.familyLimit }
            guard min(options.maximumPolynomialDegree, a.effectiveLimits.maximumPolynomialDegree) >= 1 else {
                throw KernelError(phase: .geometry, code: .resourceLimitExceeded, tolerance: tolerance,
                    message: "Original line/plane equations exceed the selected polynomial degree.")
            }
            a.context = a.context.at(stage: .source)
            let line = try DefaultOriginalSourceBindingIssuer(provider: OriginalLinearCurveSnapshotProvider(tolerance: tolerance))
                .bind(curve, limits: sourceLimits, using: &a)
            try a.admitSourceDepth(line.sourceDepth)
            a.context = a.context.retaining(first: .init(source: line))
            let plane = try DefaultOriginalSourceBindingIssuer(provider: OriginalPlaneSnapshotProvider(tolerance: tolerance))
                .bind(surface, limits: sourceLimits, using: &a)
            try a.admitSourceDepth(plane.sourceDepth)
            a.context = a.context.retaining(second: .init(source: plane))
            guard range.lower.isFinite, range.upper.isFinite, range.lower < range.upper else {
                throw KernelError(phase: .geometry, code: .invalidInput, tolerance: tolerance,
                    message: "Selected intersection ranges require finite ordered positive endpoints.")
            }
            var f = try Base(maximumValueDepth: a.effectiveLimits.maximumValueDepth,
                maximumCoefficientDepth: a.effectiveLimits.maximumCoefficientDepth, using: &a)
            let lengths = try coefficientLengths(of: plane, field: &f, limits: sourceLimits, using: &a)
            let basis = try DefaultOriginalPlaneBasisIssuer<OriginalPlaneSnapshot, Base>().issue(source: plane, field: f,
                firstLength: lengths.cross, normalLength: lengths.normal, limits: sourceLimits, using: &a)
            a.context = a.context.at(stage: .domain)
            let lineDomain = DefaultOriginalLinearDomainIssuer<Line, Base>()
            let lineFrame = try lineDomain.frame(source: line, field: f, limits: limits, using: &a)
            try a.retainStorage(bytes: exactScalarPayloadBytes(count: 1, of: [ExactParameterInterval<OriginalExactScalar>].self))
            try a.retainStorage(bytes: exactScalarPayloadBytes(count: 1, of: ExactParameterInterval<OriginalExactScalar>.self))
            let lineRequest = try lineFrame.selection(intervals: [[interval(range, field: f, using: &a)]], limits: limits, using: &a)
            a.context = a.context.retaining(first: .init(selection: lineRequest))
            let lineChart = try line.chart(OriginalLinearChartSelection(lower: range.lower, upper: range.upper), limits: sourceLimits, using: &a)
            let lineLaw = try DefaultOriginalLinearChartIssuer<Line, Base>().issue(source: line, chart: lineChart,
                field: f, limits: sourceLimits, using: &a)
            try a.retainStorage(bytes: exactScalarPayloadBytes(count: 1, of: OriginalLinearPlaneRelations.Law.self))
            let lineCover = try DefaultOriginalIssuedDomainBinder<Line, OriginalLinearChartSelection, Base>()
                .bind(laws: [lineLaw], request: lineRequest, limits: limits, using: &a)
            let field = try ExactAlgebraicScalarDomain.base(field: f, maximumExtensionLevel: Int.max, using: &a)
            let first = try DefaultOriginalRationalGraphFamilyPreparer<Line, OriginalLinearChartSelection>()
                .prepare(cover: lineCover, field: field, maximumGraphs: charts, limits: limits, using: &a)
            let planeDomain = DefaultOriginalPlaneDomainIssuer<OriginalPlaneSnapshot, Base>()
            let planeFrame = try planeDomain.frame(basis: basis, limits: limits, using: &a)
            let full = try planeFrame.fullSelection(limits: limits, using: &a)
            try a.retainStorage(bytes: exactScalarPayloadBytes(count: 2, of: [ExactParameterInterval<OriginalExactScalar>].self))
            var axes: [[ExactParameterInterval<OriginalExactScalar>]] = []; axes.reserveCapacity(2)
            for axis in 0..<2 {
                try a.consumeWork(1)
                if let selected = axis == 0 ? options.surfaceURange : options.surfaceVRange {
                    try a.retainStorage(bytes: exactScalarPayloadBytes(count: 1, of: ExactParameterInterval<OriginalExactScalar>.self))
                    axes.append([try interval(selected, field: f, using: &a)])
                } else {
                    let retained = full.axes[axis].intervals
                    try a.retainStorage(bytes: exactScalarPayloadBytes(count: retained.count, of: ExactParameterInterval<OriginalExactScalar>.self))
                    axes.append(Array(retained))
                }
            }
            let request = try planeFrame.selection(intervals: axes, limits: limits, using: &a)
            a.context = a.context.retaining(second: .init(selection: request))
            let cover = try planeDomain.issue(request: request, basis: basis, limits: limits, using: &a)
            let target = try DefaultOriginalPlaneGraphCompiler<OriginalPlaneSnapshot>().compile(cover: cover,
                field: field, limits: limits, using: &a)
            let unbounded = try NativeExactPublicLimits.unboundedStructure(), topology = unbounded.topology
            let geometryLimits = try ExactGeometricRelationLimits(cells: unbounded.cells,
                topology: .init(maximumGeneratedCells: topology.maximumGeneratedCells, maximumRootsPerStack: topology.maximumRootsPerStack,
                    maximumClosures: min(topology.maximumClosures, options.maximumCandidateCount, a.effectiveLimits.maximumResults),
                    maximumAttachmentPieces: topology.maximumAttachmentPieces, maximumComponents: topology.maximumComponents),
                maximumStrata: unbounded.maximumStrata, maximumProjectionSpans: unbounded.maximumProjectionSpans)
            a.context = a.context.at(stage: .relation)
            let original = try OriginalLinearPlaneRelations.prepare(first: first, second: target,
                limits: limits, geometryLimits: geometryLimits, tolerance: tolerance, using: &a)
            let observed = try a.withPreparationScope { a in
                try original.admitProof(limits: limits, using: &a)
                return try OriginalIssuedGeometricPublication.resolve(original, geometryLimits: geometryLimits,
                    maximumPoints: min(options.maximumCandidateCount, a.effectiveLimits.maximumResults),
                    transports: { pair in (original.firstGraphs[pair.firstGraphIndex].original.graph.parameterTransport, nil) }, using: &a)
            }
            let publication = observed.result
            let receipt = try OriginalLinearPlaneGeometricRelations.prepare(original: original, pairs: publication.pairs,
                exactPoints: publication.points, depth: observed.depth, tolerance: tolerance, using: &a)
            guard retainingRelations || !receipt.hasPositiveDimensionalSolutions else {
                throw KernelError(phase: .geometry, code: .nonDiscreteIntersection, tolerance: tolerance,
                    message: "The original line/plane selected product contains a positive-dimensional intersection.")
            }
            if receipt.hasPositiveDimensionalSolutions {
                a.context = a.context.at(stage: .publication)
                try a.retainStorage(bytes: exactScalarPayloadBytes(count: 1, of: CurveSurfaceIntersectionResult.self))
                let result = CurveSurfaceIntersectionResult(points: [], overlaps: [],
                    originalIssuedGeometricRelation: receipt)
                try a.checkpoint(); return result
            }
            a.context = a.context.at(stage: .refinement)
            let numeric = try OriginalLinearPlanePointPublisher().publish(receipt, options: options,
                tolerance: tolerance, limits: limits, using: &a)
            a.context = a.context.at(stage: .publication)
            try a.retainStorage(bytes: exactScalarPayloadBytes(count: 1, of: CurveSurfaceIntersectionResult.self))
            let result = CurveSurfaceIntersectionResult(points: numeric.points, overlaps: [],
                originalIssuedGeometricRelation: receipt, originalIssuedNumericalPoints: numeric.receipt)
            try a.checkpoint(); return result
        } catch { throw NativeExactGeometryPublicationFailure.published(error, tolerance: tolerance, context: a.context) }
    }

    private func interval(_ range: ScalarInterval, field: Base, using a: inout OriginalQueryExecution)
        throws -> ExactParameterInterval<OriginalExactScalar> {
        let lower = try field.binary64(exactly: range.lower, using: &a), upper = try field.binary64(exactly: range.upper, using: &a)
        return try .checked(field: field, lower: .finite(lower), upper: .finite(upper), includesLower: true, includesUpper: true,
            depth: .init(value: max(lower.depth.value, upper.depth.value), coefficient: max(lower.depth.coefficient, upper.depth.coefficient)), using: &a)
    }

    private func coefficientLengths(of source: OriginalSourceBinding<OriginalPlaneSnapshot>,
        field: inout Base, limits: OriginalSourceIssuanceLimits, using a: inout OriginalQueryExecution)
        throws -> (normal: OriginalExactScalar, cross: OriginalExactScalar) {
        try a.checkpoint(); try source.require(limits)
        let reference = try DefaultOriginalPlaneBasisIssuer<OriginalPlaneSnapshot, Base>()
            .referenceAxis(source: source, limits: limits, using: &a)
        var maximum = 0.0
        for axis in 0..<3 {
            try a.consumeWork(1)
            let component = source.original.normalCoordinate(in: axis)
            guard component.isFinite else { throw OriginalSourceIssuanceFailure.invalidSource }
            maximum = max(maximum, abs(component))
        }
        guard maximum > 0 else { throw OriginalSourceIssuanceFailure.invalidSource }
        // This exact power of two changes coefficient scale only. The original
        // basis issuer below still proves its laws against the untouched raw normal.
        let scale = Double(sign: .plus, exponent: maximum.exponent, significand: 1)
        guard scale.isFinite, scale > 0 else { throw OriginalSourceIssuanceFailure.invalidSource }
        let p = try ExactRationalCoefficient.originalDouble(scale, usage: &a)
        var s = ExactRationalCoefficient.zero, t = ExactRationalCoefficient.zero
        for axis in 0..<3 {
            try a.consumeWork(1)
            let raw = try ExactRationalCoefficient.originalDouble(source.original.normalCoordinate(in: axis), usage: &a)
            let component = try raw.divided(by: p, usage: &a)
            let square = try component.multiplied(by: component, usage: &a)
            s = try s.adding(square, usage: &a)
            if axis != reference { t = try t.adding(square, usage: &a) }
        }
        guard s.isPositive, t.isPositive else { throw OriginalSourceIssuanceFailure.invalidSource }
        let rationalNormal = try s.exactSquareRoot(usage: &a)
        let rationalCross = try t.exactSquareRoot(usage: &a)
        let normal: OriginalExactScalar, cross: OriginalExactScalar
        if let rationalNormal, let rationalCross {
            normal = try field.rational(exactly: rationalNormal, using: &a)
            cross = try field.rational(exactly: rationalCross, using: &a)
        } else if let rationalNormal {
            cross = try positiveSquareRoot(t, field: &field, using: &a)
            normal = try field.rational(exactly: rationalNormal, using: &a)
        } else if let rationalCross {
            normal = try positiveSquareRoot(s, field: &field, using: &a)
            cross = try field.rational(exactly: rationalCross, using: &a)
        } else if let ratio = try t.divided(by: s, usage: &a).exactSquareRoot(usage: &a) {
            normal = try positiveSquareRoot(s, field: &field, using: &a)
            cross = try field.multiplying(normal, field.rational(exactly: ratio, using: &a), using: &a)
        } else {
            // The larger positive root is sqrt(s)+sqrt(t). The original source
            // basis issuer verifies both recovered positive square laws below.
            let sum = try s.adding(t, usage: &a), delta = try s.subtracting(t, usage: &a)
            let root = try a.withProofScope(valueAxis: .coefficient) { a in
                let x = try ExactBivariatePolynomial.coordinate(alongU: true, usage: &a)
                let square = try x.multiplied(by: x, usage: &a)
                let twiceSum = try sum.adding(sum, usage: &a)
                let equation = try square.multiplied(by: square, usage: &a)
                    .subtracting(square.scaled(by: twiceSum, usage: &a), usage: &a)
                    .adding(.constant(delta.multiplied(by: delta, usage: &a), usage: &a), usage: &a)
                return try selectedPositiveRoot(equation, upper: sum.adding(.one, usage: &a),
                    expectedCount: 2, using: &a)
            }
            field = try .init(extending: field, root: root, axis: .coefficient, using: &a)
            let theta = try field.generator(using: &a)
            let difference = try field.dividing(field.rational(exactly: delta, using: &a), theta, using: &a)
            let two = try field.integer(2, using: &a)
            normal = try field.dividing(field.adding(theta, difference, using: &a), two, using: &a)
            cross = try field.dividing(field.subtracting(theta, difference, using: &a), two, using: &a)
        }
        let factor = try field.rational(exactly: p, using: &a)
        let originalNormal = try field.multiplying(normal, factor, using: &a)
        let originalCross = try field.multiplying(cross, factor, using: &a)
        try a.checkpoint()
        return (originalNormal, originalCross)
    }

    private func positiveSquareRoot(_ square: ExactRationalCoefficient,
        field: inout Base, using a: inout OriginalQueryExecution) throws -> OriginalExactScalar {
        let root = try a.withProofScope(valueAxis: .coefficient) { a in
            let x = try ExactBivariatePolynomial.coordinate(alongU: true, usage: &a)
            let equation = try x.multiplied(by: x, usage: &a)
                .subtracting(.constant(square, usage: &a), usage: &a)
            return try selectedPositiveRoot(equation, upper: square.adding(.one, usage: &a),
                expectedCount: 1, using: &a)
        }
        field = try .init(extending: field, root: root, axis: .coefficient, using: &a)
        return try field.generator(using: &a)
    }

    private func selectedPositiveRoot(_ equation: ExactBivariatePolynomial,
        upper: ExactRationalCoefficient, expectedCount: Int, using a: inout OriginalQueryExecution)
        throws -> ExactAlgebraicRealRoot {
        let roots = try ExactUnivariateRootIsolator().isolate(equation, lower: .zero, upper: upper,
            maximumDepth: a.effectiveLimits.maximumCoefficientDepth, usage: &a)
        guard roots.count == expectedCount, var selected = roots.first else { throw ExactScalarFailure.invalidEvidence }
        for index in 1..<roots.count {
            try a.consumeWork(1)
            if try roots[index].lower.subtracting(selected.lower, usage: &a).isPositive { selected = roots[index] }
        }
        try a.checkpoint()
        return try ExactAlgebraicRealRoot(polynomial: equation, isolation: selected, usage: &a)
    }
}
