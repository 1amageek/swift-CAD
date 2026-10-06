import CADCore

/// Complete finite coverage by original closed native curve laws, with each
/// unwrapped source parameter owner and its independent cycle retained.
package struct OriginalNativeCurveChartCover: Sendable {
    package let source: BSplineCurve3D
    package let parameters: ScalarInterval
    package let tolerance: ModelingTolerance
    package let spans: [OwnedSpan]

    package struct OwnedSpan: Sendable {
        package let law: OriginalRationalCurvePolynomial
        package let nativeDomain: ScalarInterval
        package let parameters: ScalarInterval
        package let cycle: Int
        package let tolerance: ModelingTolerance
        package var nativeIndex: Int { law.spanIndex }
        package var originalTranslation: Double { law.originalTranslation }

        /// Evaluates the retained original law without a rounded base station.
        package func intervalJet<B: RationalAlgebraAdmitting>(over query: ScalarInterval,
            on source: BSplineCurve3D, tolerance: ModelingTolerance,
            throughOrder: Int = 3, usage: inout B) throws -> IntervalVectorDerivativeJet {
            try CurrentTaskCancellationChecker().checkCancellation()
            try tolerance.validate()
            try GeometryStructuralComparisonWork.charge(curve: .bSpline(source),
                using: { try usage.consumeExactWork($0) })
            try GeometryStructuralComparisonWork.charge(curve: .bSpline(law.source),
                using: { try usage.consumeExactWork($0) })
            guard source == law.source, tolerance == self.tolerance,
                query.lower.isFinite, query.upper.isFinite, query.lower <= query.upper,
                query.lower >= parameters.lower, query.upper <= parameters.upper,
                (0...3).contains(throughOrder) else {
                throw Self.failure(.invalidInput, "Original curve chart evaluation requires its source, tolerance and selected closed support.", tolerance)
            }
            let lower = try ExactRationalCoefficient.originalDouble(query.lower, usage: &usage)
            let upper = try ExactRationalCoefficient.originalDouble(query.upper, usage: &usage)
            let selected = try OriginalRationalCurveIntervalJet(original: law,
                parameterMap: .init(gain: .one, offset: .zero),
                normalizedLower: lower, normalizedUpper: upper,
                throughOrder: throughOrder, usage: &usage)
            try CurrentTaskCancellationChecker().checkCancellation()
            return selected.jet
        }

        private static func failure(_ code: KernelErrorCode, _ message: String,
            _ tolerance: ModelingTolerance) -> KernelError {
            KernelError(phase: .geometry, code: code, tolerance: tolerance, message: message)
        }
    }

    package init<B: RationalAlgebraAdmitting>(source: BSplineCurve3D,
        over parameters: ScalarInterval, tolerance: ModelingTolerance,
        maximumSpanCount: Int, usage: inout B) throws {
        try CurrentTaskCancellationChecker().checkCancellation()
        try tolerance.validate()
        guard maximumSpanCount > 0, parameters.lower.isFinite,
            parameters.upper.isFinite, parameters.lower <= parameters.upper else {
            throw Self.failure(.invalidInput, "Original curve chart coverage requires a finite ordered interval and positive caller span admission.", tolerance)
        }
        try source.validate(tolerance: tolerance, consumeWork: { try usage.consumeExactWork(1) })
        let lower = source.knots[source.degree], upper = source.knots[source.controlPointCount]
        let firstCycle: Int, lastCycle: Int, period: Double
        if source.isPeriodic {
            let exact = try PreparedBSplineSurfaceDifferentialEncloser.exactDifference(upper, lower, tolerance: tolerance)
            guard exact.head > 0, exact.tail == 0 else {
                throw Self.failure(.unsupportedCapability, "Original periodic curve charts require an exact stored wrapping period.", tolerance)
            }
            period = exact.head
            let cycleCount = source.controlPointCount - source.degree
            for index in 0..<(source.knots.count - cycleCount) {
                try CurrentTaskCancellationChecker().checkCancellation(); try usage.consumeExactWork(1)
                let difference = try PreparedBSplineSurfaceDifferentialEncloser.exactDifference(
                    source.knots[index + cycleCount], source.knots[index], tolerance: tolerance)
                guard difference.head == period, difference.tail == 0 else {
                    throw Self.failure(.unsupportedCapability, "Original periodic curve charts require exact translated original knots.", tolerance)
                }
            }
            guard let firstQuotient = (OutwardScalarInterval.exact(parameters.lower) - .exact(lower)).divided(by: .exact(period)),
                let lastQuotient = (OutwardScalarInterval.exact(parameters.upper) - .exact(lower)).divided(by: .exact(period)) else {
                throw Self.failure(.resourceLimitExceeded, "Original periodic curve cycle bounds are not finite.", tolerance)
            }
            let first = firstQuotient.lower.rounded(.down) - 1
            let last = lastQuotient.upper.rounded(.down)
            guard first.isFinite, last.isFinite, abs(first) <= 4_503_599_627_370_496,
                abs(last) <= 4_503_599_627_370_496, first > Double(Int.min), last < Double(Int.max), last >= first else {
                throw Self.failure(.resourceLimitExceeded, "Original periodic curve cycles exceed exact finite enumeration.", tolerance)
            }
            firstCycle = Int(first); lastCycle = Int(last)
            let distance = lastCycle.subtractingReportingOverflow(firstCycle)
            guard !distance.overflow, !distance.partialValue.addingReportingOverflow(1).overflow else {
                throw Self.failure(.resourceLimitExceeded, "Original periodic curve cycle count overflowed.", tolerance)
            }
        } else {
            guard parameters.lower >= lower, parameters.upper <= upper else {
                throw Self.failure(.invalidInput, "Original open curve selection exceeds its native domain.", tolerance)
            }
            period = 0; firstCycle = 0; lastCycle = 0
        }
        var result: [OwnedSpan] = []
        var capacity = 0
        for cycle in firstCycle...lastCycle {
            try CurrentTaskCancellationChecker().checkCancellation(); try usage.consumeExactWork(1)
            let translation = Double(cycle) * period
            guard translation.isFinite, (-translation).addingProduct(Double(cycle), period) == 0 else {
                throw Self.failure(.resourceLimitExceeded, "Original curve cycle translation is not exactly represented.", tolerance)
            }
            for index in source.degree..<source.controlPointCount {
                try CurrentTaskCancellationChecker().checkCancellation(); try usage.consumeExactWork(1)
                guard source.knots[index] < source.knots[index + 1] else { continue }
                let a = try PreparedBSplineSurfaceDifferentialEncloser.exactDifference(source.knots[index], -translation, tolerance: tolerance)
                let b = try PreparedBSplineSurfaceDifferentialEncloser.exactDifference(source.knots[index + 1], -translation, tolerance: tolerance)
                guard a.tail == 0, b.tail == 0 else {
                    throw Self.failure(.resourceLimitExceeded, "Original curve native endpoints have no exact represented cycle lift.", tolerance)
                }
                let selectedLower = max(parameters.lower, a.head), selectedUpper = min(parameters.upper, b.head)
                guard selectedLower <= selectedUpper else { continue }
                guard result.count < maximumSpanCount else {
                    throw Self.failure(.resourceLimitExceeded, "Original curve charts exhausted the caller aggregate span admission.", tolerance)
                }
                if result.count == capacity {
                    let doubled = capacity.multipliedReportingOverflow(by: 2)
                    guard !doubled.overflow else {
                        throw Self.failure(.resourceLimitExceeded, "Original curve chart capacity overflowed.", tolerance)
                    }
                    capacity = min(maximumSpanCount, max(1, doubled.partialValue))
                    try RationalAlgebraStorage.retain(capacity, of: OwnedSpan.self, usage: &usage)
                    result.reserveCapacity(capacity)
                }
                let law = try OriginalRationalCurvePolynomial(source: source, spanIndex: index,
                    originalTranslation: translation, tolerance: tolerance, usage: &usage)
                try usage.consumeExactWork(1)
                result.append(.init(law: law, nativeDomain: try .init(lower: a.head, upper: b.head),
                    parameters: try .init(lower: selectedLower, upper: selectedUpper), cycle: cycle, tolerance: tolerance))
            }
        }
        guard !result.isEmpty else {
            throw Self.failure(.classificationFailure, "Original curve selection has no complete native chart coverage.", tolerance)
        }
        try CurrentTaskCancellationChecker().checkCancellation()
        self.source = source; self.parameters = parameters; self.tolerance = tolerance; self.spans = result
    }

    private static func failure(_ code: KernelErrorCode, _ message: String,
        _ tolerance: ModelingTolerance) -> KernelError {
        KernelError(phase: .geometry, code: code, tolerance: tolerance, message: message)
    }
}
