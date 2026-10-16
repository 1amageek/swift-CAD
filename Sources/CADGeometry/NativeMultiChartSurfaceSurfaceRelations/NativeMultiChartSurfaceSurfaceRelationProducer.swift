import CADCore

/// Geometry adapter from complete Native source charts to genuine original SSI coverage.
struct NativeMultiChartSurfaceSurfaceRelationProducer {
    func resolve(first: Surface3D, second: Surface3D,
        firstBox: SurfaceParameterBox? = nil, secondBox: SurfaceParameterBox? = nil,
        options: SurfaceSurfaceIntersectionOptions, tolerance: ModelingTolerance,
        includeRelations: Bool = false, using usage: inout OriginalQueryExecution) throws -> SurfaceSurfaceIntersectionResult? {
        guard case .bSpline(let source) = first, case .bSpline(let target) = second,
            !source.isUPeriodic, !source.isVPeriodic, !target.isUPeriodic, !target.isVPeriodic else { return nil }
        guard source.uDegree >= 0, source.uDegree < Int.max, source.vDegree >= 0, source.vDegree < Int.max,
            target.uDegree >= 0, target.uDegree < Int.max, target.vDegree >= 0, target.vDegree < Int.max else { return nil }
        // The established single-span producer remains the first public route.
        guard source.uControlPointCount != source.uDegree + 1 || source.vControlPointCount != source.vDegree + 1
            || target.uControlPointCount != target.uDegree + 1 || target.vControlPointCount != target.vDegree + 1 else { return nil }
        try options.validate(tolerance: tolerance)
        usage.context = usage.context.at(stage: .source)
        try usage.consumeWork(1)
        guard usage.effectiveLimits.remainingSourceDepth > 0 else {
            throw failure(.resourceLimitExceeded, "Native multi-chart SSI preparation exhausted original source depth.", tolerance)
        }
        try source.validate(tolerance: tolerance, using: &usage)
        try target.validate(tolerance: tolerance, using: &usage)
        let firstNative = SurfaceParameterBox(
            u: try .init(lower: source.uKnots[source.uDegree], upper: source.uKnots[source.uControlPointCount]),
            v: try .init(lower: source.vKnots[source.vDegree], upper: source.vKnots[source.vControlPointCount]))
        let secondNative = SurfaceParameterBox(
            u: try .init(lower: target.uKnots[target.uDegree], upper: target.uKnots[target.uControlPointCount]),
            v: try .init(lower: target.vKnots[target.vDegree], upper: target.vKnots[target.vControlPointCount]))
        let firstPrepared = try PreparedBSplineSurfaceDifferentialEncloser(surface: source, tolerance: tolerance,
            using: &usage)
        let secondPrepared = try PreparedBSplineSurfaceDifferentialEncloser(surface: target, tolerance: tolerance,
            using: &usage)
        let maximumSpans = min(usage.effectiveLimits.maximumSpans, PreparedBSplineSurfaceDifferentialEncloser.maximumOriginalNativeSpanCount)
        let firstSpans = try firstPrepared.originalIntersectionNativeSpans(over: firstNative, tolerance: tolerance,
            maximumSpanCount: maximumSpans, using: &usage)
        let secondSpans = try secondPrepared.originalIntersectionNativeSpans(over: secondNative, tolerance: tolerance,
            maximumSpanCount: maximumSpans, using: &usage)
        let chartCount = try rationalAlgebraCount(firstSpans.count, secondSpans.count, multiply: true)
        guard chartCount > 0, chartCount <= maximumSpans else {
            throw failure(.resourceLimitExceeded, "Native SSI tensor chart product exceeds its cumulative span admission.", tolerance)
        }
        try RationalAlgebraStorage.retain(8, of: ScalarInterval.self, usage: &usage)
        let nativeIntervals = [firstNative.u, firstNative.v, secondNative.u, secondNative.v]
        let requestedIntervals = [firstBox?.u ?? firstNative.u, firstBox?.v ?? firstNative.v,
            secondBox?.u ?? secondNative.u, secondBox?.v ?? secondNative.v]
        try RationalAlgebraStorage.retain(12, of: OriginalRationalParameterDomain.self, usage: &usage)
        var native: [OriginalRationalParameterDomain] = []; native.reserveCapacity(4)
        var requested: [OriginalRationalParameterDomain] = []; requested.reserveCapacity(4)
        var effective: [OriginalRationalParameterDomain]? = []; effective?.reserveCapacity(4)
        for axis in 0..<4 {
            native.append(try .init(nativeIntervals[axis], usage: &usage))
            requested.append(try .init(requestedIntervals[axis], usage: &usage))
            if let selection = try native[axis].intersecting(requested[axis], usage: &usage) { effective?.append(selection) }
            else { effective = nil }
        }
        try RationalAlgebraStorage.retain(chartCount, of: NativeSurfaceSurfaceSourceChart.self, usage: &usage)
        var charts: [NativeSurfaceSurfaceSourceChart] = []; charts.reserveCapacity(chartCount)
        for firstOwner in firstSpans {
            let firstLaw = try OriginalRationalSurfacePolynomial(source: source, native: firstOwner,
                domain: .init(u: firstOwner.uBounds, v: firstOwner.vBounds), view: .init(x: 0, y: 0, z: 1),
                tolerance: tolerance, usage: &usage)
            for secondOwner in secondSpans {
                let secondLaw = try OriginalRationalSurfacePolynomial(source: target, native: secondOwner,
                    domain: .init(u: secondOwner.uBounds, v: secondOwner.vBounds), view: .init(x: 0, y: 0, z: 1),
                    tolerance: tolerance, usage: &usage)
                let system = try OriginalRationalIntersectionSystem(first: firstLaw, second: secondLaw, usage: &usage)
                try RationalAlgebraStorage.retain(4, of: OriginalRationalParameterDomain.self, usage: &usage)
                let domains = try [OriginalRationalParameterDomain(firstOwner.uBounds, usage: &usage),
                    .init(firstOwner.vBounds, usage: &usage), .init(secondOwner.uBounds, usage: &usage), .init(secondOwner.vBounds, usage: &usage)]
                charts.append(.init(firstOwner: firstOwner, secondOwner: secondOwner, first: firstLaw,
                    second: secondLaw, system: system, nativeDomains: domains))
            }
        }
        usage.context = usage.context.at(stage: .relation)
        let common = try NativeSurfaceSurfaceCommonCoverage.prepare(charts: charts, nativeDomains: native,
            requestedDomains: requested, effectiveDomains: effective, maximumComponentCount: options.maximumSeedCount,
            maximumDepth: usage.effectiveLimits.maximumValueDepth, tolerance: tolerance, usage: &usage)
        let coverage = NativeSurfaceSurfaceCoverage.common(common), partition = common.partition
        var hasPositive = false, isolatedCount = 0
        for index in partition.solutionCells {
            try usage.consumeWork(1)
            if partition.cells[index].dimension > 0 { hasPositive = true }
        }
        guard includeRelations || !hasPositive else {
            throw failure(.nonDiscreteIntersection, "The complete original multi-chart native surface product is non-discrete.", tolerance)
        }
        let sourceMapProof = includeRelations && hasPositive
            ? try NativeSurfaceSurfaceChartInjectionProof.prepare(charts: charts, usage: &usage) : nil
        let relation = includeRelations ? try NativeSurfaceSurfaceRelationPublisher.publish(first: source, second: target,
            tolerance: tolerance, coverage: coverage, maximumDepth: usage.effectiveLimits.maximumValueDepth, sourceMapProof: sourceMapProof, usage: &usage) : nil
        try RationalAlgebraStorage.retain(partition.cells.count, of: Bool.self, usage: &usage)
        var isolated = Array(repeating: false, count: partition.cells.count)
        for component in common.connected.components {
            try usage.consumeWork(component.cellIndexes.count)
            if component.cellIndexes.allSatisfy({ partition.cells[$0].dimension == 0 }) {
                isolatedCount = try rationalAlgebraCount(isolatedCount, component.cellIndexes.count)
                for index in component.cellIndexes { try usage.consumeWork(1); isolated[index] = true }
            }
        }
        try RationalAlgebraStorage.retain(isolatedCount, of: Int.self, usage: &usage)
        var indices: [Int] = []; indices.reserveCapacity(isolatedCount)
        for index in partition.solutionCells { try usage.consumeWork(1); if isolated[index] { indices.append(index) } }
        let parameterCount = try rationalAlgebraCount(isolatedCount, 4, multiply: true)
        try RationalAlgebraStorage.retain(isolatedCount, of: SurfaceSurfaceIntersectionPoint.self, usage: &usage)
        try RationalAlgebraStorage.retain(parameterCount, of: OriginalSingularFieldValueIsolation.self, usage: &usage)
        try RationalAlgebraStorage.retain(parameterCount, of: NativeCurveSurfaceScalarLocalization?.self, usage: &usage)
        var points: [SurfaceSurfaceIntersectionPoint] = []; points.reserveCapacity(isolatedCount)
        var parameters: [OriginalSingularFieldValueIsolation] = []; parameters.reserveCapacity(parameterCount)
        var localizations: [NativeCurveSurfaceScalarLocalization?] = []; localizations.reserveCapacity(parameterCount)
        if let effective {
            for index in indices {
                let chart = charts[common.chartOwners[index]]
                try RationalAlgebraStorage.retain(4, of: ScalarInterval.self, usage: &usage)
                let chartIntervals = [chart.firstOwner.uBounds, chart.firstOwner.vBounds,
                    chart.secondOwner.uBounds, chart.secondOwner.vBounds]
                points.append(try NativeSurfaceSurfacePointPublisher.publish(cell: partition.cells[index], partition: partition,
                    cellIndex: index, effectiveDomains: effective, first: chart.first, second: chart.second,
                    options: options, tolerance: tolerance, nativeDomains: chartIntervals, requestedDomains: requestedIntervals,
                    retainingParameters: &parameters, retainingLocalizations: &localizations, usage: &usage))
            }
        }
        let receipt: OriginalNativeSurfaceSurfacePoints?
        if !hasPositive || !indices.isEmpty {
            try RationalAlgebraStorage.retainBytes(2 * MemoryLayout<BSplineSurface3D>.stride
                + MemoryLayout<ModelingTolerance>.stride + 3 * MemoryLayout<[Int]>.stride
                + MemoryLayout<NativeSurfaceSurfaceCoverage>.stride + 2 * MemoryLayout<UnsafeRawPointer>.stride, usage: &usage)
            receipt = .init(first: source, second: target, tolerance: tolerance, coverage: coverage,
                cellIndices: indices, parameterIsolations: parameters, parameterLocalizations: localizations)
        } else { receipt = nil }
        try RationalAlgebraStorage.retain(indices.count, of: SurfaceSurfaceIntersection.self, usage: &usage)
        var intersections: [SurfaceSurfaceIntersection] = []; intersections.reserveCapacity(indices.count)
        for ordinal in points.indices {
            try usage.consumeWork(1)
            guard let receipt else { throw rationalAlgebraFailure("Native SSI isolated point lost its complete owner.") }
            intersections.append(.point(.init(numerical: points[ordinal], originalNativePoint: try receipt.point(at: ordinal))))
        }
        try RationalAlgebraStorage.retain(1, of: SurfaceSurfaceIntersectionResult.self, usage: &usage)
        try usage.checkpoint()
        return .init(intersections: intersections, originalNativePoints: receipt, originalNativeRelations: relation)
    }
    private func failure(_ code: KernelErrorCode, _ message: String, _ tolerance: ModelingTolerance) -> KernelError {
        .init(phase: .geometry, code: code, tolerance: tolerance, message: message)
    }
}
