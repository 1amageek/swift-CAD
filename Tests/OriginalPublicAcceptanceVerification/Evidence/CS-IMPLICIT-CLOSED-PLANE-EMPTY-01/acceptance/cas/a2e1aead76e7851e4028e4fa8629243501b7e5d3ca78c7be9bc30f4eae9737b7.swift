import CADCore

/// Complete original affine isolated publication before legacy dispatch.
struct OriginalAffineCurveSurfacePointProducer {
    func resolve(curve: Curve3D, surface: Surface3D, options: CurveSurfaceIntersectionOptions,
        tolerance: ModelingTolerance, invocation: CurveSurfaceQueryInvocation? = nil)
        throws -> CurveSurfaceIntersectionResult? {
        guard case .bSpline(let curveSource) = curve,
            case .procedural(.originalAffineWord(let image)) = surface else { return nil }
        try options.validate(tolerance: tolerance)
        var usage = try NativeCurveSurfacePointAllowance(options: options, invocation: invocation)
        try usage.consumeExactWork(1)
        try invocation?.consume(depth: 0)
        let sourceDepth = invocation?.remainingSourceDepth ?? 1
        guard sourceDepth > 0 else {
            throw failure(.resourceLimitExceeded, "Original curve/affine preparation exhausted affine descendant source depth.", tolerance)
        }
        // FIXME(INCOMPLETE_IMPLEMENTATION): The public affine isolated checkpoint
        // admits direct aperiodic single-span Native sources only. Other descendants,
        // periodic covers, multi-span composition and normalized algebraic words require
        // genuine original issuers
        // before this producer may publish complete coverage or enter legacy fallback.
        guard case .bSpline(let surfaceSource) = image.source, !curveSource.isPeriodic,
            !surfaceSource.isUPeriodic, !surfaceSource.isVPeriodic else {
            throw failure(.unsupportedCapability, "Original affine points require direct aperiodic Native sources.", tolerance)
        }
        try curveSource.validate(tolerance: tolerance, consumeWork: { try usage.consumeExactWork(1) })
        try surfaceSource.validate(tolerance: tolerance, consumeWork: { try usage.consumeExactWork(1) })
        let curveSpan = try singleSpan(knots: curveSource.knots, degree: curveSource.degree,
            controlCount: curveSource.controlPointCount, tolerance: tolerance, usage: &usage)
        _ = try singleSpan(knots: surfaceSource.uKnots, degree: surfaceSource.uDegree,
            controlCount: surfaceSource.uControlPointCount, tolerance: tolerance, usage: &usage)
        _ = try singleSpan(knots: surfaceSource.vKnots, degree: surfaceSource.vDegree,
            controlCount: surfaceSource.vControlPointCount, tolerance: tolerance, usage: &usage)
        guard max(curveSource.degree, surfaceSource.uDegree, surfaceSource.vDegree) <= options.maximumPolynomialDegree else {
            throw failure(.resourceLimitExceeded, "Original affine source degree exceeds the admitted ceiling.", tolerance)
        }
        let curveLaw = try OriginalRationalCurvePolynomial(source: curveSource, spanIndex: curveSpan,
            tolerance: tolerance, usage: &usage)
        let t = try ScalarInterval(lower: curveSource.knots[curveSpan], upper: curveSource.knots[curveSpan + 1])
        let u = try ScalarInterval(lower: surfaceSource.uKnots[surfaceSource.uDegree],
            upper: surfaceSource.uKnots[surfaceSource.uControlPointCount])
        let v = try ScalarInterval(lower: surfaceSource.vKnots[surfaceSource.vDegree],
            upper: surfaceSource.vKnots[surfaceSource.vControlPointCount])
        let domain = SurfaceParameterBox(u: u, v: v)
        let prepared = try PreparedBSplineSurfaceDifferentialEncloser(surface: surfaceSource, tolerance: tolerance,
            consumeWork: { try usage.consumeExactWork(1) }, consumeStorage: { try usage.retainBytes($0) })
        let spans = try prepared.originalIntersectionNativeSpans(over: domain, tolerance: tolerance,
            maximumSpanCount: 1, consumeWork: { try usage.consumeExactWork(1) },
            consumeStorage: { try usage.retainBytes($0) })
        guard spans.count == 1, let span = spans.first else {
            throw failure(.invalidInput, "Original affine preparation requires its complete Native span receipt.", tolerance)
        }
        let affine = try OriginalAffineSurfaceIntersectionSource(image: image, nativeSpan: span,
            domain: domain, tolerance: tolerance, remainingSourceDepth: sourceDepth,
            maximumAlgebraicDepth: usage.maximumAlgebraicDepth, usage: &usage)
        try RationalAlgebraStorage.retain(9, of: OriginalRationalParameterDomain.self, usage: &usage)
        let native = try [OriginalRationalParameterDomain(t, usage: &usage),
            OriginalRationalParameterDomain(u, usage: &usage), OriginalRationalParameterDomain(v, usage: &usage)]
        let requested = try [OriginalRationalParameterDomain(options.curveRange ?? t, usage: &usage),
            OriginalRationalParameterDomain(options.surfaceURange ?? u, usage: &usage),
            OriginalRationalParameterDomain(options.surfaceVRange ?? v, usage: &usage)]
        var effective: [OriginalRationalParameterDomain]? = []
        effective?.reserveCapacity(3)
        for axis in 0..<3 {
            if let selected = try native[axis].intersecting(requested[axis], usage: &usage) {
                effective?.append(selected)
            } else { effective = nil }
        }
        let binding = try OriginalAffineIntersectionEquations(curve: curveLaw, surface: affine, usage: &usage)
        var incidence: OriginalRationalIntersectionIncidence?
        var components: OriginalRationalParameterComponents?
        var points: [CurveSurfaceIntersection] = []
        var indexes: [Int] = []
        var parameters: [OriginalSingularFieldValueIsolation] = []
        var localizations: [NativeCurveSurfaceScalarLocalization?] = []
        if let effective {
            let partition = try OriginalRationalIntersectionCells.prepare(equations: binding.equations,
                variableCount: 3, exactDomains: effective, nonzeroPolynomials: binding.denominatorGuards,
                thomEncoding: true, pruneExcludedPrefixes: true,
                maximumDepth: usage.maximumAlgebraicDepth, usage: &usage)
            // Inspect the entire selected relation before publishing any tuple.
            for index in partition.solutionCells {
                try usage.consumeExactWork(1)
                guard partition.cells[index].dimension == 0 else {
                    throw failure(.nonDiscreteIntersection,
                        "The original curve/affine requested product contains a positive-dimensional intersection.", tolerance)
                }
            }
            guard partition.solutionCells.count <= options.maximumCandidateCount else {
                throw failure(.resourceLimitExceeded, "Original curve/affine tuple count exceeds the admitted candidate ceiling.", tolerance)
            }
            let proved = try OriginalRationalIntersectionIncidence.prepare(partition: partition,
                maximumDepth: usage.maximumAlgebraicDepth, usage: &usage)
            components = try proved.connectedComponents(usage: &usage)
            incidence = proved
            // The existing cylindrical partition emits original tuples in T/U/V order.
            indexes = partition.solutionCells
            let count = indexes.count
            let scalarCount = try rationalAlgebraCount(count, 3, multiply: true)
            try RationalAlgebraStorage.retain(count, of: CurveSurfaceIntersection.self, usage: &usage)
            try RationalAlgebraStorage.retain(scalarCount, of: OriginalSingularFieldValueIsolation.self, usage: &usage)
            try RationalAlgebraStorage.retain(scalarCount, of: NativeCurveSurfaceScalarLocalization?.self, usage: &usage)
            points.reserveCapacity(count); parameters.reserveCapacity(scalarCount); localizations.reserveCapacity(scalarCount)
            let normal = try OriginalPolynomialCurveSurfaceNormal.prepare(homogeneous: affine.homogeneous, usage: &usage)
            for index in indexes {
                try usage.consumeExactWork(1)
                points.append(try NativeCurveSurfacePointPublisher().publish(cell: partition.cells[index],
                    partition: partition, cellIndex: index, effectiveDomains: effective,
                    curve: curveLaw, surfaceHomogeneous: affine.homogeneous, surfaceNormalNumerators: normal,
                    options: options, tolerance: tolerance, nativeDomains: (t, u, v),
                    retainingParameters: &parameters, retainingLocalizations: &localizations, usage: &usage))
            }
        }
        try OriginalAffineCurveSurfacePoints.admitStorage(usage: &usage)
        let receipt = OriginalAffineCurveSurfacePoints(curve: curveSource, source: binding, tolerance: tolerance,
            nativeDomains: native, requestedDomains: requested, effectiveDomains: effective,
            incidence: incidence, components: components, cellIndexes: indexes,
            parameterIsolations: parameters, parameterLocalizations: localizations)
        try RationalAlgebraStorage.retain(1, of: CurveSurfaceIntersectionResult.self, usage: &usage)
        try usage.consumeExactWork(0)
        try CurrentTaskCancellationChecker().checkCancellation()
        return .init(points: points, overlaps: [], originalAffinePoints: receipt)
    }

    private func singleSpan(knots: [Double], degree: Int, controlCount: Int,
        tolerance: ModelingTolerance, usage: inout NativeCurveSurfacePointAllowance) throws -> Int {
        var selected: Int?
        for index in degree..<controlCount {
            try usage.consumeExactWork(1)
            if knots[index] < knots[index + 1] {
                guard selected == nil else {
                    throw failure(.unsupportedCapability, "Original affine points require one complete Native span per source axis.", tolerance)
                }
                selected = index
            }
        }
        guard let selected else { throw GeometryError.invalidDistance(0) }
        return selected
    }

    private func failure(_ code: KernelErrorCode, _ message: String, _ tolerance: ModelingTolerance) -> KernelError {
        .init(phase: .geometry, code: code, tolerance: tolerance, message: message)
    }
}
