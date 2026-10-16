import CADCore
import CADGeometry

/// Original cumulative native arc-length receipts, independent of frame candidates.
package struct OriginalCurvedSweepArcLengthLaw: Sendable {
    private let charts: [OriginalCurveSpanParameterChart]
    private let preparations: [any CurveArcLengthParameterization]
    private let endpoints: [(first: OutwardScalarInterval, last: OutwardScalarInterval)]
    private let starts: [OutwardScalarInterval]
    private let lengths: [OutwardScalarInterval]
    package let total: OutwardScalarInterval
    private let tolerance: ModelingTolerance
    private let budget: CurvedSweepSourceBudget

    package init(spans: [ExactBSplineCurveSpan], tolerance: ModelingTolerance,
                 budget: CurvedSweepSourceBudget,
                 resolver: any CurveArcLengthResolving = DefaultCurveArcLengthResolver(), using execution: inout OriginalQueryExecution) throws {
        guard !spans.isEmpty else {
            throw KernelError(phase: .geometry, code: .invalidInput, tolerance: tolerance,
                message: "An original sweep arc-length law needs retained native spans.")
        }
        let elementBytes = MemoryLayout<OriginalCurveSpanParameterChart>.stride
            + 2 * MemoryLayout<any CurveArcLengthParameterization>.stride
            + MemoryLayout<(first: OutwardScalarInterval, last: OutwardScalarInterval)>.stride
            + 2 * MemoryLayout<OutwardScalarInterval>.stride
            + MemoryLayout<(source: OriginalCurveSpanSource, lower: Double, upper: Double)>.stride
            + MemoryLayout<Int>.stride
        let storage = spans.count.multipliedReportingOverflow(by: elementBytes)
        guard !storage.overflow else {
            throw KernelError(phase: .geometry, code: .resourceLimitExceeded,
                tolerance: tolerance, message: "Original arc-length span storage overflowed.")
        }
        try execution.retainStorage(bytes:storage.partialValue)
        var starts: [OutwardScalarInterval] = [], lengths: [OutwardScalarInterval] = []
        var preparations: [any CurveArcLengthParameterization] = []
        var endpoints: [(first: OutwardScalarInterval, last: OutwardScalarInterval)] = []
        var groups: [(source: OriginalCurveSpanSource, lower: Double, upper: Double)] = []
        var groupIndices: [Int] = []
        starts.reserveCapacity(spans.count)
        lengths.reserveCapacity(spans.count)
        preparations.reserveCapacity(spans.count)
        endpoints.reserveCapacity(spans.count)
        groups.reserveCapacity(spans.count)
        groupIndices.reserveCapacity(spans.count)
        var total = OutwardScalarInterval.exact(0)
        for span in spans {
            try budget.consume(depth: 0, using: &execution)
            let first = try span.originalChart.parameterBounds(atNormalizedFraction: 0,
                tolerance: tolerance, using: &execution)
            let last = try span.originalChart.parameterBounds(atNormalizedFraction: 1,
                tolerance: tolerance, using: &execution)
            guard first.isFinite, last.isFinite,
                  last.lower > first.upper || first.lower > last.upper else {
                throw KernelError(phase: .geometry, code: .invalidInput, tolerance: tolerance,
                    message: "A sweep arc-length source lost its original finite native interval.")
            }
            let native = try ScalarInterval(lower: min(first.lower, last.lower),
                upper: max(first.upper, last.upper))
            let source = span.originalChart.source
            var matchedGroup: Int?
            for index in groups.indices {
                try budget.consume(depth: 0, using: &execution)
                if groups[index].source === source { matchedGroup = index; break }
            }
            if let index = matchedGroup {
                groups[index].lower = min(groups[index].lower, native.lower)
                groups[index].upper = max(groups[index].upper, native.upper)
                groupIndices.append(index)
            } else {
                groupIndices.append(groups.count)
                groups.append((source, native.lower, native.upper))
            }
            endpoints.append((first, last))
        }
        var groupPreparations: [any CurveArcLengthParameterization] = []
        groupPreparations.reserveCapacity(groups.count)
        let limits = budget.limits
        for group in groups {
            try budget.consume(depth: 0, using: &execution)
            groupPreparations.append(try resolver.parameterization(of: group.source.curve,
                over: ScalarInterval(lower: group.lower, upper: group.upper), options: CurveArcLengthOptions(),
                tolerance: tolerance, maximumSubdivisionDepth: budget.maximumDepth,
                remainingSourceDepth: limits.remainingSourceDepth,
                maximumAlgebraicDepth: limits.maximumValueDepth, using: &execution))
        }
        for index in spans.indices {
            try budget.consume(depth: 0, using: &execution)
            let (first, last) = endpoints[index]
            let native = try ScalarInterval(lower: min(first.lower, last.lower),
                upper: max(first.upper, last.upper))
            let preparation = groupPreparations[groupIndices[index]]
            guard try preparation.hasSmoothNativeInterval(over: native, using: &execution) else {
                // FIXME(INCOMPLETE_IMPLEMENTATION): Original affine implicit/lifted
                // path charts need retained owning join continuity before the
                // original arc-length interpolation remainder may authorize twist.
                // A D2 hull by itself does not prove speed continuity at joins.
                throw KernelError(phase: .geometry, code: .unsupportedCapability,
                    tolerance: tolerance, message: "Original sweep fraction needs a smooth native chart or a certified source join.")
            }
            let inner = try preparation.enclosure(over: ScalarInterval(
                lower: min(first.upper, last.upper), upper: max(first.lower, last.lower)), using: &execution)
            let outer = try preparation.enclosure(over: native, using: &execution)
            let enclosed = OutwardScalarInterval(lower: inner.lowerBound,
                upper: outer.upperBound)
            preparations.append(preparation)
            starts.append(total)
            lengths.append(enclosed)
            total = total + enclosed
        }
        guard total.lower > 0, total.upper.isFinite else {
            throw KernelError(phase: .geometry, code: .singularSystem, tolerance: tolerance,
                message: "The original sweep path length is not certified finite and positive.")
        }
        charts = spans.map { $0.originalChart }
        self.preparations = preparations
        self.endpoints = endpoints
        self.starts = starts
        self.lengths = lengths
        self.total = total
        self.tolerance = tolerance
        self.budget = budget
    }

    package func fraction(span: Int, at normalizedParameter: Double, using execution: inout OriginalQueryExecution) throws -> OutwardScalarInterval {
        try budget.consume(depth: 0, using: &execution)
        guard charts.indices.contains(span), normalizedParameter.isFinite,
              normalizedParameter >= 0, normalizedParameter <= 1 else {
            throw KernelError(phase: .geometry, code: .invalidInput, tolerance: tolerance,
                message: "An original sweep station must lie in its retained normalized native span.")
        }
        if span == 0, normalizedParameter == 0 { return .exact(0) }
        if span == charts.count - 1, normalizedParameter == 1 { return .exact(1) }
        let prefix: OutwardScalarInterval
        if normalizedParameter == 0 {
            prefix = .exact(0)
        } else if normalizedParameter == 1 {
            prefix = lengths[span]
        } else {
            // Preserve the authored native affine chart before outward conversion.
            // A rounded native station cannot replace its original image interval.
            let station = try charts[span].parameterBounds(
                atNormalizedFraction: normalizedParameter, tolerance: tolerance, using: &execution)
            let first = endpoints[span].first
            let forward = endpoints[span].last.lower > first.upper
            let nativeLower = min(first.lower, endpoints[span].last.lower)
            let nativeUpper = max(first.upper, endpoints[span].last.upper)
            let boundedStation = OutwardScalarInterval(lower: max(nativeLower, station.lower),
                upper: min(nativeUpper, station.upper))
            let outerLower = min(first.lower, boundedStation.lower)
            let outerUpper = max(first.upper, boundedStation.upper)
            let upper = try preparations[span].enclosure(over: ScalarInterval(
                lower: outerLower, upper: outerUpper), using: &execution).upperBound
            let innerLower = forward ? first.upper : boundedStation.upper
            let innerUpper = forward ? boundedStation.lower : first.lower
            let lower: Double
            if innerLower < innerUpper {
                lower = try preparations[span].enclosure(over: ScalarInterval(
                    lower: innerLower, upper: innerUpper), using: &execution).lowerBound
            } else { lower = 0 }
            prefix = .init(lower: lower, upper: upper)
        }
        guard let fraction = (starts[span] + prefix).divided(by: total),
              fraction.lower.isFinite, fraction.upper.isFinite else {
            throw KernelError(phase: .geometry, code: .singularSystem, tolerance: tolerance,
                message: "Original cumulative length cannot bound the requested sweep fraction.")
        }
        return .init(lower: max(0, fraction.lower), upper: min(1, fraction.upper))
    }

    package func fractionInterpolationError(span: Int, from lower: Double, to upper: Double,
        depth: Int, using execution: inout OriginalQueryExecution) throws -> OutwardScalarInterval {
        try budget.consume(depth: depth, using: &execution)
        guard charts.indices.contains(span), lower >= 0, lower < upper, upper <= 1 else {
            throw KernelError(phase: .geometry, code: .invalidInput, tolerance: tolerance,
                message: "Original fraction interpolation needs one retained normalized source cell.")
        }
        let chart = charts[span]
        let labels = try chart.parameterJet(overNormalizedFraction: ScalarInterval(lower: lower, upper: upper),
            throughOrder: 2, tolerance: tolerance, using: &execution)
        let first = try chart.parameterBounds(atNormalizedFraction: lower, tolerance: tolerance, using: &execution)
        let last = try chart.parameterBounds(atNormalizedFraction: upper, tolerance: tolerance, using: &execution)
        let nativeLower = min(endpoints[span].first.lower, endpoints[span].last.lower)
        let nativeUpper = max(endpoints[span].first.upper, endpoints[span].last.upper)
        let jet = try preparations[span].differentialEnclosure(over: ScalarInterval(
            lower: max(nativeLower, min(first.lower, last.lower)),
            upper: min(nativeUpper, max(first.upper, last.upper))), using: &execution)
        // Original composition acceleration is C''(label) label'^2 +
        // C'(label) label''. Child normalization contributes width squared;
        // circular construction fractions are not linear native angles.
        let width = OutwardScalarInterval.exact(upper) - .exact(lower)
        let gain = labels.derivatives[1] * width
        let secondGain = labels.derivatives[2] * width * width
        func magnitude(_ value: ScalarInterval) -> Double { max(abs(value.lower), abs(value.upper)) }
        let acceleration = OutwardScalarInterval.exact(magnitude(jet.secondDerivative.x))
            + .exact(magnitude(jet.secondDerivative.y))
            + .exact(magnitude(jet.secondDerivative.z))
        let velocity = OutwardScalarInterval.exact(magnitude(jet.firstDerivative.x))
            + .exact(magnitude(jet.firstDerivative.y))
            + .exact(magnitude(jet.firstDerivative.z))
        let composedAcceleration = acceleration * .exact(gain.absoluteUpperBound) * .exact(gain.absoluteUpperBound)
            + velocity * .exact(secondGain.absoluteUpperBound)
        guard let error = composedAcceleration.divided(by: .exact(8) * total),
              error.isFinite else {
            throw KernelError(phase: .geometry, code: .resourceLimitExceeded, tolerance: tolerance,
                message: "Original arc-length interpolation has no finite acceleration bound.")
        }
        return .init(lower: 0, upper: error.absoluteUpperBound)
    }
}
