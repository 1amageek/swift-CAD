import CADCore

/// Complete isolated original Native curve/Coons publication before legacy dispatch.
struct OriginalCoonsCurveSurfacePointProducer {
    func resolve(curve: Curve3D, surface: Surface3D, options: CurveSurfaceIntersectionOptions,
        tolerance: ModelingTolerance, using usage: inout OriginalQueryExecution)
        throws -> CurveSurfaceIntersectionResult? {
        guard case .bSpline(let curveSource) = curve,
            case .procedural(.originalCoons(let surfaceSource)) = surface else { return nil }
        try options.validate(tolerance: tolerance)
        usage.context = usage.context.at(stage: .source)
        try usage.consumeWork(1)
        let sourceDepth = min(1, usage.effectiveLimits.remainingSourceDepth)
        guard sourceDepth > 0 else {
            throw failure(.resourceLimitExceeded, "Original curve/Coons preparation exhausted surface-to-boundary source depth.", tolerance)
        }
        // FIXME(INCOMPLETE_IMPLEMENTATION): This public producer covers direct
        // aperiodic single-span Native curves against the bounded Coons issuer.
        // Periodic and multi-span curves require complete original chart
        // composition before this checkpoint can authorize their publication.
        guard !curveSource.isPeriodic else {
            throw failure(.unsupportedCapability, "Original curve/Coons points require an aperiodic single-span Native curve.", tolerance)
        }
        try curveSource.validate(tolerance: tolerance, using: &usage)
        var span: Int?
        for index in curveSource.degree..<curveSource.controlPointCount {
            try usage.consumeWork(1)
            if curveSource.knots[index] < curveSource.knots[index + 1] {
                guard span == nil else {
                    throw failure(.unsupportedCapability, "Original curve/Coons points require one complete Native curve span.", tolerance)
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
        let u = try ScalarInterval(lower: 0, upper: 1)
        let v = try ScalarInterval(lower: 0, upper: 1)
        let coons = try OriginalCoonsSurfacePolynomial(source: surfaceSource, over: .init(u: u, v: v),
            remainingSourceDepth: sourceDepth, tolerance: tolerance, usage: &usage)
        for boundary in coons.boundaries {
            try usage.consumeWork(1)
            guard boundary.source.degree <= options.maximumPolynomialDegree else {
                throw failure(.resourceLimitExceeded, "Original Coons boundary degree exceeds the admitted ceiling.", tolerance)
            }
        }
        try usage.admitSourceDepth(1)
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
        usage.context = usage.context.at(stage: .relation)
        let binding = try coons.curveRelation(curve: curveLaw, curveDomain: native[0], usage: &usage)
        var incidence: OriginalRationalIntersectionIncidence?
        var components: OriginalRationalParameterComponents?
        var points: [CurveSurfaceIntersection] = []
        var indexes: [Int] = []
        var parameters: [OriginalSingularFieldValueIsolation] = []
        var localizations: [NativeCurveSurfaceScalarLocalization?] = []
        if let effective {
            guard case .rational(let original) = binding.relation.polynomials, original.count == 5 else {
                throw rationalAlgebraFailure("Original curve/Coons equality lost its five raw guarded laws.")
            }
            try RationalAlgebraStorage.retain(5, of: ExactIntersectionPolynomial.self, usage: &usage)
            var equations: [ExactIntersectionPolynomial] = []; equations.reserveCapacity(3)
            var guards: [ExactIntersectionPolynomial] = []; guards.reserveCapacity(2)
            for ordinal in original.indices {
                try usage.consumeWork(1)
                if ordinal < 3 { equations.append(original[ordinal].original) }
                else { guards.append(original[ordinal].original) }
            }
            let partition = try OriginalRationalIntersectionCells.prepare(equations: equations,
                variableCount: 3, exactDomains: effective, nonzeroPolynomials: guards,
                thomEncoding: true, pruneExcludedPrefixes: true,
                maximumDepth: usage.effectiveLimits.maximumValueDepth, usage: &usage)
            // Inspect the entire selected relation before publishing any tuple.
            for index in partition.solutionCells {
                try usage.consumeWork(1)
                guard partition.cells[index].dimension == 0 else {
                    throw failure(.nonDiscreteIntersection,
                        "The original curve/Coons requested product contains a positive-dimensional intersection.", tolerance)
                }
            }
            guard partition.solutionCells.count <= options.maximumCandidateCount else {
                throw failure(.resourceLimitExceeded, "Original curve/Coons tuple count exceeds the admitted candidate ceiling.", tolerance)
            }
            let proved = try OriginalRationalIntersectionIncidence.prepare(partition: partition,
                maximumDepth: usage.effectiveLimits.maximumValueDepth, usage: &usage)
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
            let normal = try OriginalPolynomialCurveSurfaceNormal.prepare(homogeneous: coons.homogeneous, usage: &usage)
            for index in indexes {
                try usage.consumeWork(1)
                points.append(try NativeCurveSurfacePointPublisher().publish(cell: partition.cells[index],
                    partition: partition, cellIndex: index, effectiveDomains: effective,
                    curve: curveLaw, surfaceHomogeneous: coons.homogeneous, surfaceNormalNumerators: normal,
                    options: options, tolerance: tolerance, nativeDomains: (t, u, v),
                    retainingParameters: &parameters, retainingLocalizations: &localizations, usage: &usage))
            }
        }
        usage.context = usage.context.at(stage: .publication)
        try OriginalCoonsCurveSurfacePoints.admitStorage(usage: &usage)
        let receipt = OriginalCoonsCurveSurfacePoints(curve: curveSource, source: binding, tolerance: tolerance,
            nativeDomains: native, requestedDomains: requested, effectiveDomains: effective,
            incidence: incidence, components: components, cellIndexes: indexes,
            parameterIsolations: parameters, parameterLocalizations: localizations)
        try RationalAlgebraStorage.retain(1, of: CurveSurfaceIntersectionResult.self, usage: &usage)
        try usage.consumeWork(0)
        try usage.checkpoint()
        return .init(points: points, overlaps: [], originalCoonsPoints: receipt)
    }

    private func failure(_ code: KernelErrorCode, _ message: String, _ tolerance: ModelingTolerance) -> KernelError {
        .init(phase: .geometry, code: code, tolerance: tolerance, message: message)
    }
}
