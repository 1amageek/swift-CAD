import CADCore

/// Complete isolated Native curve/original ruled publication before legacy dispatch.
struct OriginalPolynomialCurveSurfacePointProducer {
    func resolve(curve: Curve3D, surface: Surface3D, options: CurveSurfaceIntersectionOptions,
        tolerance: ModelingTolerance, invocation: CurveSurfaceQueryInvocation? = nil)
        throws -> CurveSurfaceIntersectionResult? {
        guard case .bSpline(let curveSource) = curve,
            case .procedural(.ruled(let surfaceSource)) = surface else { return nil }
        try options.validate(tolerance: tolerance)
        var usage = try NativeCurveSurfacePointAllowance(options: options, invocation: invocation)
        try usage.consumeExactWork(1)
        try invocation?.consume(depth: 0)
        let sourceDepth = invocation?.remainingSourceDepth ?? 1
        guard sourceDepth > 0 else {
            throw failure(.resourceLimitExceeded, "Original curve/ruled preparation exhausted surface-to-boundary source depth.", tolerance)
        }
        // FIXME(INCOMPLETE_IMPLEMENTATION): This public producer covers direct
        // aperiodic single-span Native curves against the bounded ruled issuer.
        // Periodic and multi-span curves require complete original chart
        // composition before this checkpoint can authorize their publication.
        guard !curveSource.isPeriodic else {
            throw failure(.unsupportedCapability, "Original curve/ruled points require an aperiodic single-span Native curve.", tolerance)
        }
        try curveSource.validate(tolerance: tolerance, consumeWork: { try usage.consumeExactWork(1) })
        var span: Int?
        for index in curveSource.degree..<curveSource.controlPointCount {
            try usage.consumeExactWork(1)
            if curveSource.knots[index] < curveSource.knots[index + 1] {
                guard span == nil else {
                    throw failure(.unsupportedCapability, "Original curve/ruled points require one complete Native curve span.", tolerance)
                }
                span = index
            }
        }
        guard let span else { throw GeometryError.invalidDistance(0) }
        guard curveSource.degree <= options.maximumPolynomialDegree else {
            throw failure(.resourceLimitExceeded, "Original curve source degree exceeds the admitted ceiling.", tolerance)
        }
        let curveLaw = try OriginalRationalCurvePolynomial(source: curveSource, spanIndex: span,
            tolerance: tolerance, usage: &usage)
        let t = try ScalarInterval(lower: curveSource.knots[span], upper: curveSource.knots[span + 1])
        guard case .closed(let lowerU, let upperU) = surfaceSource.uDomain else {
            throw failure(.invalidInput, "An original ruled point query requires its finite closed native U domain.", tolerance)
        }
        let u = try ScalarInterval(lower: lowerU, upper: upperU)
        let v = try ScalarInterval(lower: 0, upper: 1)
        let ruled = try OriginalRuledSurfacePolynomial(source: surfaceSource, over: .init(u: u, v: v),
            remainingSourceDepth: sourceDepth, tolerance: tolerance, usage: &usage)
        guard max(ruled.start.source.degree, ruled.end.source.degree) <= options.maximumPolynomialDegree else {
            throw failure(.resourceLimitExceeded, "Original ruled boundary degree exceeds the admitted ceiling.", tolerance)
        }
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
        let binding = try ruled.curveRelation(curve: curveLaw, curveDomain: native[0], usage: &usage)
        var incidence: OriginalRationalIntersectionIncidence?
        var components: OriginalRationalParameterComponents?
        var points: [CurveSurfaceIntersection] = []
        var indexes: [Int] = []
        var parameters: [OriginalSingularFieldValueIsolation] = []
        var localizations: [NativeCurveSurfaceScalarLocalization?] = []
        if let effective {
            guard case .rational(let original) = binding.relation.polynomials, original.count == 5 else {
                throw rationalAlgebraFailure("Original curve/ruled equality lost its five raw guarded laws.")
            }
            try RationalAlgebraStorage.retain(5, of: ExactIntersectionPolynomial.self, usage: &usage)
            var equations: [ExactIntersectionPolynomial] = []; equations.reserveCapacity(3)
            var guards: [ExactIntersectionPolynomial] = []; guards.reserveCapacity(2)
            for ordinal in original.indices {
                try usage.consumeExactWork(1)
                if ordinal < 3 { equations.append(original[ordinal].original) }
                else { guards.append(original[ordinal].original) }
            }
            let partition = try OriginalRationalIntersectionCells.prepare(equations: equations,
                variableCount: 3, exactDomains: effective, nonzeroPolynomials: guards,
                thomEncoding: true, pruneExcludedPrefixes: true,
                maximumDepth: usage.maximumAlgebraicDepth, usage: &usage)
            // Inspect the entire selected relation before publishing any tuple.
            for index in partition.solutionCells {
                try usage.consumeExactWork(1)
                guard partition.cells[index].dimension == 0 else {
                    throw failure(.nonDiscreteIntersection,
                        "The original curve/ruled requested product contains a positive-dimensional intersection.", tolerance)
                }
            }
            guard partition.solutionCells.count <= options.maximumCandidateCount else {
                throw failure(.resourceLimitExceeded, "Original curve/ruled tuple count exceeds the admitted candidate ceiling.", tolerance)
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
            let normal = try OriginalPolynomialCurveSurfaceNormal.prepare(homogeneous: ruled.homogeneous, usage: &usage)
            for index in indexes {
                try usage.consumeExactWork(1)
                points.append(try NativeCurveSurfacePointPublisher().publish(cell: partition.cells[index],
                    partition: partition, cellIndex: index, effectiveDomains: effective,
                    curve: curveLaw, surfaceHomogeneous: ruled.homogeneous, surfaceNormalNumerators: normal,
                    options: options, tolerance: tolerance, nativeDomains: (t, u, v),
                    retainingParameters: &parameters, retainingLocalizations: &localizations, usage: &usage))
            }
        }
        try OriginalPolynomialCurveSurfacePoints.admitStorage(usage: &usage)
        let receipt = OriginalPolynomialCurveSurfacePoints(curve: curveSource, source: binding, tolerance: tolerance,
            nativeDomains: native, requestedDomains: requested, effectiveDomains: effective,
            incidence: incidence, components: components, cellIndexes: indexes,
            parameterIsolations: parameters, parameterLocalizations: localizations)
        try RationalAlgebraStorage.retain(1, of: CurveSurfaceIntersectionResult.self, usage: &usage)
        try CurrentTaskCancellationChecker().checkCancellation()
        return .init(points: points, overlaps: [], originalPolynomialPoints: receipt)
    }

    private func failure(_ code: KernelErrorCode, _ message: String, _ tolerance: ModelingTolerance) -> KernelError {
        .init(phase: .geometry, code: code, tolerance: tolerance, message: message)
    }
}
