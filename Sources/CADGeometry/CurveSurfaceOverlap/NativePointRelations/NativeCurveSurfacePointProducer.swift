import CADCore
#if !hasFeature(Embedded)
import Foundation
#elseif canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(WASILibc)
import WASILibc
#else
#error("CADGeometry numeric algorithms require the target C math module.")
#endif

/// Complete original native point publication, before any legacy dispatch.
struct NativeCurveSurfacePointProducer {
    func resolve(curve: Curve3D, surface: Surface3D, options: CurveSurfaceIntersectionOptions,
        tolerance: ModelingTolerance, invocation: CurveSurfaceQueryInvocation? = nil,
        retainingRelations: Bool = false)
        throws -> CurveSurfaceIntersectionResult? {
        guard case .bSpline(let source) = curve, case .bSpline(let target) = surface else { return nil }
        try options.validate(tolerance: tolerance)
        var usage = try NativeCurveSurfacePointAllowance(options: options, invocation: invocation)
        try usage.consumeExactWork(1)
        guard invocation.map({ $0.remainingSourceDepth > 0 }) ?? true else {
            throw failure(.resourceLimitExceeded, "Native point preparation exhausted original source depth.", tolerance)
        }
        try invocation?.consume(depth: 0)
        guard max(source.degree, target.uDegree, target.vDegree) <= options.maximumPolynomialDegree else {
            throw failure(.resourceLimitExceeded, "Native point source degree exceeds the admitted ceiling.", tolerance)
        }
        try source.validate(tolerance: tolerance, consumeWork: { try usage.consumeExactWork(1) })
        try target.validate(tolerance: tolerance, consumeWork: { try usage.consumeExactWork(1) })
        let t = try ScalarInterval(lower: source.knots[source.degree], upper: source.knots[source.controlPointCount])
        let u = try ScalarInterval(lower: target.uKnots[target.uDegree], upper: target.uKnots[target.uControlPointCount])
        let v = try ScalarInterval(lower: target.vKnots[target.vDegree], upper: target.vKnots[target.vControlPointCount])
        func selected(_ explicit: ScalarInterval?, native: ScalarInterval, periodic: Bool) throws -> ScalarInterval {
            if let explicit { return explicit }
            return periodic ? try .init(lower: 0, upper: native.upper - native.lower) : native
        }
        let selectedT = try selected(options.curveRange, native: t, periodic: source.isPeriodic)
        let selectedU = try selected(options.surfaceURange, native: u, periodic: target.isUPeriodic)
        let selectedV = try selected(options.surfaceVRange, native: v, periodic: target.isVPeriodic)
        try RationalAlgebraStorage.retain(9, of: OriginalRationalParameterDomain.self, usage: &usage)
        let native = try [OriginalRationalParameterDomain(source.isPeriodic ? nil : t, usage: &usage),
            OriginalRationalParameterDomain(target.isUPeriodic ? nil : u, usage: &usage),
            OriginalRationalParameterDomain(target.isVPeriodic ? nil : v, usage: &usage)]
        let requested = try [OriginalRationalParameterDomain(selectedT, usage: &usage),
            OriginalRationalParameterDomain(selectedU, usage: &usage), OriginalRationalParameterDomain(selectedV, usage: &usage)]
        var effective: [OriginalRationalParameterDomain]? = []
        effective?.reserveCapacity(3)
        for axis in 0..<3 {
            if let intersection = try native[axis].intersecting(requested[axis], usage: &usage) {
                effective?.append(intersection)
            } else { effective = nil }
        }
        let maximumSpans = min(invocation?.maximumSpanCount ?? options.maximumCandidateCount, 262_144)
        let curveCover = try OriginalNativeCurveChartCover(source: source,
            over: source.isPeriodic ? selectedT : t, tolerance: tolerance,
            maximumSpanCount: maximumSpans, usage: &usage)
        let nativeBox = SurfaceParameterBox(u: target.isUPeriodic ? selectedU : u, v: target.isVPeriodic ? selectedV : v)
        let prepared = try PreparedBSplineSurfaceDifferentialEncloser(surface: target, tolerance: tolerance,
            consumeWork: { try usage.consumeExactWork(1) }, consumeStorage: { try usage.retainBytes($0) })
        let spans = try prepared.originalIntersectionNativeSpans(over: nativeBox, tolerance: tolerance,
            maximumSpanCount: maximumSpans, consumeWork: { try usage.consumeExactWork(1) },
            consumeStorage: { try usage.retainBytes($0) })
        let productCount = try rationalAlgebraCount(curveCover.spans.count, spans.count, multiply: true)
        guard productCount > 0, productCount <= maximumSpans else {
            throw failure(.resourceLimitExceeded, "Native point product count exceeds the cumulative span ceiling.", tolerance)
        }
        try RationalAlgebraStorage.retain(productCount, of: NativeCurveSurfacePointChart.self, usage: &usage)
        var charts: [NativeCurveSurfacePointChart] = []; charts.reserveCapacity(productCount)
        var references: [NativeCurveSurfacePointCell] = []
        var points: [CurveSurfaceIntersection] = []
        var retainedParameters: [OriginalSingularFieldValueIsolation] = []
        var retainedLocalizations: [NativeCurveSurfaceScalarLocalization?] = []
        var capacity = 0
        for curveOwner in curveCover.spans {
            try usage.consumeExactWork(1)
            let curveLaw = curveOwner.law
            for span in spans {
                try usage.consumeExactWork(1)
                let surfaceLaw = try OriginalRationalSurfacePolynomial(source: target, native: span,
                    domain: .init(u: span.uBounds, v: span.vBounds), view: .init(x: 0, y: 0, z: 1),
                    tolerance: tolerance, usage: &usage)
                let system = try OriginalRationalIntersectionSystem(curve: curveLaw, surface: surfaceLaw, usage: &usage)
                let decomposition: OriginalRationalIntersectionDecomposition?
                let domains: [OriginalRationalParameterDomain]
                if retainingRelations && productCount > 1 {
                    // The whole common refinement proves these retained original source bindings.
                    decomposition = nil
                    try RationalAlgebraStorage.retain(3, of: OriginalRationalParameterDomain.self, usage: &usage)
                    domains = try [.init(lower: curveLaw.lowerParameter, upper: curveLaw.upperParameter, usage: &usage),
                        .init(span.uBounds, usage: &usage), .init(span.vBounds, usage: &usage)]
                } else {
                    let proved = try OriginalRationalIntersectionDecomposition.prepare(system: system,
                        requestedDomains: requested, pruneExcludedPrefixes: true, normalizeDenominatorFactors: true,
                        isolatedOnly: !retainingRelations, preferIsolatedCells: retainingRelations,
                        maximumDepth: usage.maximumAlgebraicDepth, usage: &usage)
                    decomposition = proved; domains = proved.nativeDomains
                }
                let chartIndex = charts.count
                charts.append(.init(curveOwner: curveOwner, surfaceOwner: span, surface: surfaceLaw,
                    system: system, nativeDomains: domains, decomposition: decomposition))
                if let decomposition,
                    case .parameterCells(let strata, _, _) = decomposition.coverage,
                    let chartDomains = decomposition.effectiveDomains {
                    let partition = strata.partition
                    var hasPositiveDimension = false
                    for index in partition.solutionCells {
                        try usage.consumeExactWork(1)
                        if partition.cells[index].dimension > 0 { hasPositiveDimension = true }
                    }
                    if hasPositiveDimension {
                        guard retainingRelations else {
                            throw failure(.nonDiscreteIntersection,
                                "The original requested native product contains a positive-dimensional intersection.", tolerance)
                        }
                    }
                    try RationalAlgebraStorage.retain(partition.solutionCells.count, of: Int.self, usage: &usage)
                    var isolatedCells: [Int] = []; isolatedCells.reserveCapacity(partition.solutionCells.count)
                    if case .parameterCells(_, _, let connected) = decomposition.coverage {
                        for component in connected.components {
                            var dimension = 0
                            for index in component.cellIndexes {
                                try usage.consumeExactWork(1)
                                dimension = max(dimension, partition.cells[index].dimension)
                            }
                            if dimension == 0 { isolatedCells.append(contentsOf: component.cellIndexes) }
                        }
                    }
                    for index in isolatedCells {
                        try RationalAlgebraStorage.retain(3, of: OriginalSingularFieldValueIsolation.self, usage: &usage)
                        try RationalAlgebraStorage.retain(3, of: NativeCurveSurfaceScalarLocalization?.self, usage: &usage)
                        var parameters: [OriginalSingularFieldValueIsolation] = []; parameters.reserveCapacity(3)
                        var localizations: [NativeCurveSurfaceScalarLocalization?] = []; localizations.reserveCapacity(3)
                        let point = try NativeCurveSurfacePointPublisher().publish(cell: partition.cells[index], partition: partition,
                            cellIndex: index, effectiveDomains: chartDomains, curve: curveLaw, surfaceHomogeneous: surfaceLaw.homogeneous,
                            surfaceNormalNumerators: surfaceLaw.normalNumerators,
                            options: options, tolerance: tolerance,
                            nativeDomains: (curveOwner.nativeDomain, span.uBounds, span.vBounds),
                            retainingParameters: &parameters, retainingLocalizations: &localizations, usage: &usage)
                        // Source basis chooses the right positive span at every internal knot.
                        // Chart closure remains retained for coverage, but does not duplicate a tuple.
                        var owns = true
                        for axis in 0..<3 {
                            let upper: Double, final: Double
                            switch axis {
                            case 0: upper = curveOwner.nativeDomain.upper; final = t.upper
                            case 1: upper = span.uBounds.upper; final = u.upper
                            default: upper = span.vBounds.upper; final = v.upper
                            }
                            let periodic = axis == 0 ? source.isPeriodic : axis == 1 ? target.isUPeriodic : target.isVPeriodic
                            if !periodic && upper == final { continue }
                            let comparison = try parameters[axis].compared(to: .originalDouble(upper, usage: &usage),
                                maximumDepth: usage.maximumAlgebraicDepth, usage: &usage)
                            parameters[axis] = comparison.isolation
                            if comparison.sign == .zero { owns = false }
                        }
                        guard owns else { continue }
                        guard points.count < options.maximumCandidateCount else {
                            throw failure(.resourceLimitExceeded, "Native isolated tuple count exceeds the cumulative result ceiling.", tolerance)
                        }
                        if points.count == capacity {
                            let doubled = try rationalAlgebraCount(max(1, capacity), 2, multiply: true)
                            capacity = min(options.maximumCandidateCount, doubled)
                            let scalarCapacity = try rationalAlgebraCount(capacity, 3, multiply: true)
                            try RationalAlgebraStorage.retain(capacity, of: CurveSurfaceIntersection.self, usage: &usage)
                            try RationalAlgebraStorage.retain(capacity, of: NativeCurveSurfacePointCell.self, usage: &usage)
                            try RationalAlgebraStorage.retain(scalarCapacity, of: OriginalSingularFieldValueIsolation.self, usage: &usage)
                            try RationalAlgebraStorage.retain(scalarCapacity, of: NativeCurveSurfaceScalarLocalization?.self, usage: &usage)
                            points.reserveCapacity(capacity); references.reserveCapacity(capacity)
                            retainedParameters.reserveCapacity(scalarCapacity); retainedLocalizations.reserveCapacity(scalarCapacity)
                        }
                        points.append(point); references.append(.init(chartIndex: chartIndex, cellIndex: index))
                        retainedParameters.append(contentsOf: parameters); retainedLocalizations.append(contentsOf: localizations)
                    }
                }
            }
        }
        try RationalAlgebraStorage.retain(charts.count, of: OriginalNativeCurveSurfaceChart.self, usage: &usage)
        var sourceCharts: [OriginalNativeCurveSurfaceChart] = []; sourceCharts.reserveCapacity(charts.count)
        for chart in charts { try usage.consumeExactWork(1); sourceCharts.append(.init(chart: chart)) }
        let relation: OriginalNativeCurveSurfaceRelation?
        if retainingRelations {
            try RationalAlgebraStorage.retain(1, of: OriginalNativeCurveSurfaceRelation.self, usage: &usage)
            relation = try .init(charts: charts, sourceCharts: sourceCharts,
                curve: source, surface: target, tolerance: tolerance,
                nativeDomains: native, requestedDomains: requested, effectiveDomains: effective,
                maximumCandidateCount: options.maximumCandidateCount,
                maximumDepth: usage.maximumAlgebraicDepth, usage: &usage)
        } else { relation = nil }
        if let common = relation?.composition, let effective {
            for component in common.connected.components {
                var dimension = 0
                for index in component.cellIndexes {
                    try usage.consumeExactWork(1)
                    dimension = max(dimension, common.partition.cells[index].dimension)
                }
                guard dimension == 0 else { continue }
                for index in component.cellIndexes {
                    let chartIndex = common.chartOwners[index], chart = charts[chartIndex]
                    try RationalAlgebraStorage.retain(3, of: OriginalSingularFieldValueIsolation.self, usage: &usage)
                    try RationalAlgebraStorage.retain(3, of: NativeCurveSurfaceScalarLocalization?.self, usage: &usage)
                    var parameters: [OriginalSingularFieldValueIsolation] = []; parameters.reserveCapacity(3)
                    var localizations: [NativeCurveSurfaceScalarLocalization?] = []; localizations.reserveCapacity(3)
                    let point = try NativeCurveSurfacePointPublisher().publish(cell: common.partition.cells[index], partition: common.partition,
                        cellIndex: index, effectiveDomains: effective, curve: chart.curve, surfaceHomogeneous: chart.surface.homogeneous,
                        surfaceNormalNumerators: chart.surface.normalNumerators,
                        options: options, tolerance: tolerance,
                        nativeDomains: (chart.curveOwner.nativeDomain, chart.surfaceOwner.uBounds, chart.surfaceOwner.vBounds),
                        retainingParameters: &parameters, retainingLocalizations: &localizations, usage: &usage)
                    guard points.count < options.maximumCandidateCount else {
                        throw failure(.resourceLimitExceeded, "Native composed isolated tuple count exceeds the cumulative result ceiling.", tolerance)
                    }
                    if points.count == capacity {
                        let doubled = try rationalAlgebraCount(max(1, capacity), 2, multiply: true)
                        capacity = min(options.maximumCandidateCount, doubled)
                        let scalarCapacity = try rationalAlgebraCount(capacity, 3, multiply: true)
                        try RationalAlgebraStorage.retain(capacity, of: CurveSurfaceIntersection.self, usage: &usage)
                        try RationalAlgebraStorage.retain(capacity, of: NativeCurveSurfacePointCell.self, usage: &usage)
                        try RationalAlgebraStorage.retain(scalarCapacity, of: OriginalSingularFieldValueIsolation.self, usage: &usage)
                        try RationalAlgebraStorage.retain(scalarCapacity, of: NativeCurveSurfaceScalarLocalization?.self, usage: &usage)
                        points.reserveCapacity(capacity); references.reserveCapacity(capacity)
                        retainedParameters.reserveCapacity(scalarCapacity); retainedLocalizations.reserveCapacity(scalarCapacity)
                    }
                    points.append(point); references.append(.init(chartIndex: chartIndex, cellIndex: index))
                    retainedParameters.append(contentsOf: parameters); retainedLocalizations.append(contentsOf: localizations)
                }
            }
        }
        try order(points: &points, references: &references, parameters: &retainedParameters,
            localizations: &retainedLocalizations, charts: charts, usage: &usage)
        try RationalAlgebraStorage.retainBytes(MemoryLayout<BSplineCurve3D>.stride + MemoryLayout<BSplineSurface3D>.stride
            + MemoryLayout<ModelingTolerance>.stride + 9 * MemoryLayout<[Int]>.stride
            + MemoryLayout<OriginalRationalIntersectionCells?>.stride
            + 2 * MemoryLayout<UnsafeRawPointer>.stride, usage: &usage)
        let receipt = OriginalNativeCurveSurfacePoints(curve: source, surface: target, tolerance: tolerance,
            nativeDomains: native, requestedDomains: requested, effectiveDomains: effective,
            charts: charts, sourceCharts: sourceCharts, composedPartition: relation?.composition?.partition, pointCells: references,
            parameterIsolations: retainedParameters, parameterLocalizations: retainedLocalizations)
        try RationalAlgebraStorage.retain(1, of: CurveSurfaceIntersectionResult.self, usage: &usage)
        try CurrentTaskCancellationChecker().checkCancellation()
        return .init(points: points, overlaps: [], originalNativePoints: receipt,
            originalNativeRelations: relation)
    }

    /// Stable merge ordering compares original tuples, never their numerical image.
    private func order(points: inout [CurveSurfaceIntersection],
        references: inout [NativeCurveSurfacePointCell],
        parameters: inout [OriginalSingularFieldValueIsolation],
        localizations: inout [NativeCurveSurfaceScalarLocalization?],
        charts: [NativeCurveSurfacePointChart], usage: inout NativeCurveSurfacePointAllowance) throws {
        guard points.count > 1, charts.count > 1 else { return }
        let count = points.count
        try RationalAlgebraStorage.retain(count, of: Int.self, usage: &usage)
        try RationalAlgebraStorage.retain(count, of: Int.self, usage: &usage)
        var indices: [Int] = []; indices.reserveCapacity(count)
        for index in 0..<count { try usage.consumeExactWork(1); indices.append(index) }
        var scratch = [Int](repeating: 0, count: count)
        func precedes(_ first: Int, _ second: Int, usage: inout NativeCurveSurfacePointAllowance) throws -> Bool {
            for axis in 0..<3 {
                var a = parameters[first * 3 + axis], b = parameters[second * 3 + axis]
                let sign = try OriginalSingularFieldValueOrder.compare(&a, &b,
                    maximumDepth: usage.maximumAlgebraicDepth, maximumCoefficientDepth: 0, usage: &usage)
                parameters[first * 3 + axis] = a; parameters[second * 3 + axis] = b
                if sign != .zero { return sign == .negative }
            }
            // Exact source ownership forbids a duplicate tuple across different products.
            throw rationalAlgebraFailure("Distinct native chart owners issued the same exact parameter tuple.")
        }
        var width = 1
        while width < count {
            var start = 0
            while start < count {
                let middle = min(count, try rationalAlgebraCount(start, width))
                let end = min(count, try rationalAlgebraCount(middle, width))
                var left = start, right = middle, destination = start
                while left < middle || right < end {
                    try usage.consumeExactWork(1)
                    let useLeft: Bool
                    if right == end { useLeft = true }
                    else if left == middle { useLeft = false }
                    else { useLeft = try precedes(indices[left], indices[right], usage: &usage) }
                    if useLeft { scratch[destination] = indices[left]; left += 1 }
                    else { scratch[destination] = indices[right]; right += 1 }
                    destination += 1
                }
                start = end
            }
            swap(&indices, &scratch)
            width = try rationalAlgebraCount(width, 2, multiply: true)
        }
        try RationalAlgebraStorage.retain(count, of: CurveSurfaceIntersection.self, usage: &usage)
        try RationalAlgebraStorage.retain(count, of: NativeCurveSurfacePointCell.self, usage: &usage)
        let scalarCount = try rationalAlgebraCount(count, 3, multiply: true)
        try RationalAlgebraStorage.retain(scalarCount, of: OriginalSingularFieldValueIsolation.self, usage: &usage)
        try RationalAlgebraStorage.retain(scalarCount, of: NativeCurveSurfaceScalarLocalization?.self, usage: &usage)
        var orderedPoints: [CurveSurfaceIntersection] = []; orderedPoints.reserveCapacity(count)
        var orderedReferences: [NativeCurveSurfacePointCell] = []; orderedReferences.reserveCapacity(count)
        var orderedParameters: [OriginalSingularFieldValueIsolation] = []; orderedParameters.reserveCapacity(scalarCount)
        var orderedLocalizations: [NativeCurveSurfaceScalarLocalization?] = []; orderedLocalizations.reserveCapacity(scalarCount)
        for ordinal in indices {
            try usage.consumeExactWork(1)
            orderedPoints.append(points[ordinal]); orderedReferences.append(references[ordinal])
            for axis in 0..<3 {
                orderedParameters.append(parameters[ordinal * 3 + axis])
                orderedLocalizations.append(localizations[ordinal * 3 + axis])
            }
        }
        points = orderedPoints; references = orderedReferences
        parameters = orderedParameters; localizations = orderedLocalizations
    }

    private func failure(_ code: KernelErrorCode, _ message: String, _ tolerance: ModelingTolerance) -> KernelError {
        .init(phase: .geometry, code: code, tolerance: tolerance, message: message)
    }
}
