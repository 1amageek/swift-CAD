import CADCore
import CADGeometry

/// A restricted original traversal shared by curved-frame and Hermite proofs.
package struct OriginalSweepPathPiece: Sendable {
    package enum Place { case whole, start, end }

    private enum Traversal: Sendable {
        case native(OriginalCurveRootSpan3D)
        case constructionChart(OriginalCurveSpanParameterChart)
    }
    private let traversal: Traversal
    private let sourceOwner: OriginalCurveSpanSource
    private let lower: Double
    private let upper: Double
    private let depth: Int
    private let tolerance: ModelingTolerance
    private let budget: CurvedSweepSourceBudget

    package init(span: ExactBSplineCurveSpan, tolerance: ModelingTolerance,
        budget: CurvedSweepSourceBudget) throws {
        let chart = span.originalChart
        let nativeFirst = try chart.authoredEndpointParameter(atEnd: false, tolerance: tolerance)
        let nativeLast = try chart.authoredEndpointParameter(atEnd: true, tolerance: tolerance)
        let usesConstructionChart: Bool
        switch chart.mapping {
        case .affine: usesConstructionChart = nativeFirst == nil || nativeLast == nil
        case .circularRational, .hyperbolicRational: usesConstructionChart = true
        }
        if usesConstructionChart {
            traversal = .constructionChart(chart)
            sourceOwner = chart.source
            lower = 0; upper = 1; depth = 0
            self.tolerance = tolerance; self.budget = budget
            return
        }
        guard case .affine = chart.mapping,
              let first = nativeFirst, let last = nativeLast else {
            throw KernelError(phase: .geometry, code: .invalidInput,
                tolerance: tolerance, message: "Original sweep frames need retained directed native endpoint charts.")
        }
        let nativeLower = min(first, last), nativeUpper = max(first, last)
        var owningSpan: Int?
        if case .bSpline(let curve) = chart.curve {
            for index in curve.degree..<curve.controlPoints.count {
                try budget.consume(depth: 0)
                if curve.knots[index] < curve.knots[index + 1],
                   nativeLower >= curve.knots[index], nativeUpper <= curve.knots[index + 1] {
                    owningSpan = index
                    break
                }
            }
            guard owningSpan != nil else {
                throw KernelError(phase: .geometry, code: .invalidInput,
                    tolerance: tolerance, message: "An original sweep span must retain one positive native owner.")
            }
        }
        var usage = budget
        // FIXME(INCOMPLETE_IMPLEMENTATION): Native and ideal analytic owning
        // traversals now forward explicit source/depth and actual Taylor bytes.
        // Periodic native, implicit/lifted and certified-intersection higher-byte
        // producers remain required before full curved-path source admission.
        traversal = .native(try OriginalCurveRootSpan3D(source: chart.curve,
            start: .authored(first), end: .authored(last), nativeSpanIndex: owningSpan,
            maximumParameterWidth: chart.curve.parameterDomain.parameterResolution(tolerance: tolerance),
            maximumSubdivisionDepth: budget.maximumDepth, tolerance: tolerance, usage: &usage,
            maximumSpanCount: budget.maximumSpanCount, remainingSourceDepth: budget.maximumDepth,
            consumeStorage: { try budget.retainBytes($0) }))
        sourceOwner = chart.source
        lower = 0; upper = 1; depth = 0
        self.tolerance = tolerance
        self.budget = budget
    }

    private init(traversal: Traversal, sourceOwner: OriginalCurveSpanSource,
        lower: Double, upper: Double,
        depth: Int, tolerance: ModelingTolerance, budget: CurvedSweepSourceBudget) {
        self.traversal = traversal
        self.sourceOwner = sourceOwner
        self.lower = lower; self.upper = upper; self.depth = depth
        self.tolerance = tolerance; self.budget = budget
    }

    package func halves() -> (Self, Self) {
        let middle = lower + (upper - lower) * 0.5
        return (Self(traversal: traversal, sourceOwner: sourceOwner, lower: lower, upper: middle,
                    depth: depth + 1, tolerance: tolerance, budget: budget),
                Self(traversal: traversal, sourceOwner: sourceOwner, lower: middle, upper: upper,
                    depth: depth + 1, tolerance: tolerance, budget: budget))
    }

    package static func prepare(_ spans: [ExactBSplineCurveSpan], tolerance: ModelingTolerance,
        budget: CurvedSweepSourceBudget) throws -> [Self] {
        let bytes = spans.count.multipliedReportingOverflow(by: MemoryLayout<Self>.stride)
        guard !bytes.overflow else {
            throw KernelError(phase: .geometry, code: .resourceLimitExceeded,
                tolerance: tolerance, message: "Original sweep traversal capacity overflowed.")
        }
        try budget.retainBytes(bytes.partialValue)
        var prepared: [Self] = []
        prepared.reserveCapacity(spans.count)
        for span in spans { prepared.append(try Self(span: span, tolerance: tolerance, budget: budget)) }
        return prepared
    }

    package func belongs(to span: ExactBSplineCurveSpan, tolerance: ModelingTolerance,
        budget: CurvedSweepSourceBudget) throws -> Bool {
        try budget.consume(depth: 0)
        guard self.tolerance == tolerance, self.budget === budget,
              sourceOwner === span.originalChart.source, lower == 0, upper == 1 else { return false }
        switch traversal {
        case .native(let native):
            guard case .authored(let first) = native.start,
                  case .authored(let last) = native.end else { return false }
            return try span.originalChart.authoredEndpointParameter(atEnd: false, tolerance: tolerance) == first
                && span.originalChart.authoredEndpointParameter(atEnd: true, tolerance: tolerance) == last
        case .constructionChart(let chart):
            return chart.identity === span.originalChart.identity
        }
    }

    package func derivativeJet(over place: Place, order: Int) throws -> IntervalVectorDerivativeJet {
        try budget.consume(depth: depth)
        guard order >= 0, order <= 5, lower < upper else {
            throw KernelError(phase: .geometry, code: .invalidInput,
                tolerance: tolerance, message: "Original frame queries need an admitted derivative order and positive piece.")
        }
        let range: ScalarInterval
        switch place {
        case .whole: range = try ScalarInterval(lower: lower, upper: upper)
        case .start: range = try ScalarInterval(lower: lower, upper: lower)
        case .end: range = try ScalarInterval(lower: upper, upper: upper)
        }
        if case .constructionChart(let chart) = traversal {
            let label = try chart.parameterJet(overNormalizedFraction: range, throughOrder: order,
                tolerance: tolerance, consumeWork: { try budget.consume(depth: depth) },
                consumeStorage: { try budget.retainBytes($0) })
            let native = try OriginalCurveHigherJetProvider.intervalTaylorJet(of: chart.curve,
                over: ScalarInterval(lower: max(min(chart.startParameter, chart.endParameter), label.value.lower),
                    upper: min(max(chart.startParameter, chart.endParameter), label.value.upper)),
                tolerance: tolerance, throughOrder: max(4, order), maximumSpanCount: budget.maximumSpanCount,
                maximumSubdivisionDepth: budget.maximumDepth - depth,
                remainingSourceDepth: budget.maximumDepth - depth,
                consumeWork: { try budget.consume(depth: depth) }, consumeStorage: { try budget.retainBytes($0) })
            try budget.retainBytes(4 * (order + 1) * MemoryLayout<OutwardScalarInterval>.stride)
            func source(_ scalar: SurfaceAreaIntervalTaylorScalarJet) throws -> IntervalDerivativeJet {
                var derivatives: [OutwardScalarInterval] = []
                derivatives.reserveCapacity(order + 1)
                var factorial = OutwardScalarInterval.exact(1)
                for n in 0...order {
                    try budget.consume(depth: depth)
                    if n > 1 { factorial = factorial * .exact(Double(n)) }
                    derivatives.append(try scalar.coefficient(n, 0) * factorial)
                }
                return .init(derivatives: derivatives)
            }
            var parameters: [OutwardScalarInterval] = []
            parameters.reserveCapacity(order + 1)
            let width = OutwardScalarInterval.exact(upper) - .exact(lower)
            var power = OutwardScalarInterval.exact(1)
            for n in 0...order {
                try budget.consume(depth: depth)
                parameters.append(label.derivatives[n] * power)
                power = power * width
            }
            return try OriginalCurveJetComposition().compose(
                .init(x: source(native.x), y: source(native.y), z: source(native.z)),
                parameter: .init(derivatives: parameters), order: order,
                consumeWork: { try budget.consume(depth: depth) }, consumeStorage: { try budget.retainBytes($0) })
        }
        guard case .native(let traversal) = traversal else {
            throw GeometryConversionError.invalidInput("Original sweep piece lost its native traversal.")
        }
        let original = try traversal.intervalTaylorJet(over: range,
            throughOrder: max(4, order), tolerance: tolerance,
            consumeWork: { try budget.consume(depth: depth) },
            maximumSpanCount: budget.maximumSpanCount,
            remainingSourceDepth: budget.maximumDepth - depth,
            consumeStorage: { try budget.retainBytes($0) })
        try budget.retainBytes(3 * (order + 1) * MemoryLayout<OutwardScalarInterval>.stride)
        var x: [OutwardScalarInterval] = [], y: [OutwardScalarInterval] = [], z: [OutwardScalarInterval] = []
        x.reserveCapacity(order + 1); y.reserveCapacity(order + 1); z.reserveCapacity(order + 1)
        let gain = OutwardScalarInterval.exact(upper) - .exact(lower)
        var factor = OutwardScalarInterval.exact(1)
        for derivative in 0...order {
            try budget.consume(depth: depth)
            if derivative > 0 { factor = factor * .exact(Double(derivative)) * gain }
            x.append(try original.x.coefficient(derivative, 0) * factor)
            y.append(try original.y.coefficient(derivative, 0) * factor)
            z.append(try original.z.coefficient(derivative, 0) * factor)
        }
        return .init(x: .init(derivatives: x), y: .init(derivatives: y), z: .init(derivatives: z))
    }
}
