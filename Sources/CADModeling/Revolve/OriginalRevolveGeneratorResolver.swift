import CADCore
import CADGeometry

// FIXME(INCOMPLETE_IMPLEMENTATION): This original rational chart producer is
// consumed by CurvedRevolveBodyBuilder's native public sheet path and persistent
// original revolution boundaries. Original analytic-conic, transformed and cyclic
// endpoint charts must also reach publication before general S7 may be reported.
package struct OriginalRevolveGeneratorResolver: Sendable {
    package struct Span: Sendable {
        package let chart: OriginalCurveRootSpan3D
        package let isWholeAxis: Bool
        package let originalAxisOrigin: Point3D
        package let originalAxisDirection: Vector3D
        package let followsOriginalParameterDirection: Bool

        fileprivate init(chart: OriginalCurveRootSpan3D, isWholeAxis: Bool,
            originalAxisOrigin: Point3D, originalAxisDirection: Vector3D,
            followsOriginalParameterDirection: Bool = true) {
            self.chart = chart
            self.isWholeAxis = isWholeAxis
            self.originalAxisOrigin = originalAxisOrigin
            self.originalAxisDirection = originalAxisDirection
            self.followsOriginalParameterDirection = followsOriginalParameterDirection
        }

        package func reversed() -> Self {
            Self(chart: chart.reversed(), isWholeAxis: isWholeAxis,
                originalAxisOrigin: originalAxisOrigin, originalAxisDirection: originalAxisDirection,
                followsOriginalParameterDirection: !followsOriginalParameterDirection)
        }
    }

    package init() {}

    /// Preserves the exact negation law used by authored reversed section references.
    package func resolve<B: RationalAlgebraAdmitting>(source: Curve3D,
        over parameters: ScalarInterval, origin: Point3D, direction: Vector3D,
        maximumParameterWidth: Double, maximumSubdivisionDepth: Int,
        maximumSpanCount: Int, tolerance: ModelingTolerance, usage: inout B) throws -> [Span] {
        var original = source
        var nativeParameters = parameters
        var reversesTraversal = false
        while case let .parameterImage(image) = original {
            try usage.consumeExactWork(1)
            guard image.parameterGain == .binary(-1), image.offset == 0 else {
                // FIXME(INCOMPLETE_IMPLEMENTATION): Public Revolve requires an
                // original endpoint chart for general parameter ratios and
                // offsets. Rounded mapped scalar stations cannot replace it.
                throw KernelError(phase: .geometry, code: .unsupportedCapability,
                    tolerance: tolerance,
                    message: "Original revolution parameter images require retained endpoint chart authority.")
            }
            nativeParameters = try ScalarInterval(lower: -nativeParameters.upper,
                upper: -nativeParameters.lower)
            original = image.source
            reversesTraversal.toggle()
        }
        guard case let .bSpline(spline) = original else {
            // FIXME(INCOMPLETE_IMPLEMENTATION): Original analytic generators
            // need their source-bound line/conic endpoint charts. Public Revolve
            // must not classify a rational candidate image as the original law.
            throw KernelError(phase: .geometry, code: .unsupportedCapability,
                tolerance: tolerance,
                message: "Original revolution requires the source family's retained root chart.")
        }
        let spans = try resolve(source: spline, over: nativeParameters,
            origin: origin, direction: direction, maximumParameterWidth: maximumParameterWidth,
            maximumSubdivisionDepth: maximumSubdivisionDepth, maximumSpanCount: maximumSpanCount,
            tolerance: tolerance, usage: &usage)
        if !reversesTraversal { return spans }
        var reversed: [Span] = []
        for span in spans.reversed() {
            try usage.consumeExactWork(1)
            try usage.retainExactStorage(1)
            reversed.append(span.reversed())
        }
        return reversed
    }

    /// Retains the original native coefficients, all incidence roots and owning sides.
    package func resolve<B: RationalAlgebraAdmitting>(source: BSplineCurve3D,
        over parameters: ScalarInterval, origin: Point3D, direction: Vector3D,
        maximumParameterWidth: Double, maximumSubdivisionDepth: Int,
        maximumSpanCount: Int, tolerance: ModelingTolerance, usage: inout B) throws -> [Span] {
        try source.validate(tolerance: tolerance)
        try origin.validate()
        try direction.validate()
        guard parameters.width.isFinite, parameters.width > 0,
              maximumParameterWidth.isFinite, maximumParameterWidth > 0,
              maximumSubdivisionDepth >= 0, maximumSubdivisionDepth <= 32,
              maximumSpanCount > 0, maximumSpanCount <= 65_536,
              direction.x != 0 || direction.y != 0 || direction.z != 0 else {
            throw GeometryConversionError.invalidInput("Original revolution requires a finite trim, nonzero raw axis and admitted chart limits.")
        }
        let nativeLower = source.knots[source.degree]
        let nativeUpper = source.knots[source.controlPoints.count]
        guard parameters.lower >= nativeLower, parameters.upper <= nativeUpper else {
            // FIXME(INCOMPLETE_IMPLEMENTATION): Periodically translated original
            // knot spans need source-bound translated root receipts. Public Revolve
            // must not wrap numeric endpoints and drop their original parameter chart.
            if case .periodic = source.domain {
                throw KernelError(phase: .geometry, code: .unsupportedCapability,
                    tolerance: tolerance,
                    message: "Periodic original revolution requires retained translated native root charts.")
            }
            throw GeometryConversionError.invalidInput("Original rational revolution trim exceeds its owning native knot interval.")
        }
        let classified = try DefaultOriginalCurveRootBoundaryClassifier().roots(
            of: source, over: parameters, constraint: .axis(origin: origin, direction: direction),
            maximumSpanCount: maximumSpanCount, maximumSubdivisionDepth: maximumSubdivisionDepth,
            tolerance: tolerance, usage: &usage)
        guard classified.isolated.count <= maximumSpanCount else {
            throw GeometryConversionError.resourceLimitExceeded("Original revolution exhausted its root boundary count admission.")
        }
        var rootsBySpan: [Int: [OriginalCurveRootBoundary]] = [:]
        for root in classified.isolated {
            try usage.consumeExactWork(1)
            try usage.retainExactStorage(1)
            rootsBySpan[root.spanIndex, default: []].append(root)
        }
        try usage.retainExactStorage(classified.coincidentSpans.count)
        let wholeAxisIntervals = Set(classified.coincidentSpans)
        var output: [Span] = []
        for spanIndex in source.degree..<source.controlPoints.count {
            let lower = max(parameters.lower, source.knots[spanIndex])
            let upper = min(parameters.upper, source.knots[spanIndex + 1])
            guard lower < upper else { continue }
            try usage.visitExactCell(depth: 0)
            let interval = try ScalarInterval(lower: lower, upper: upper)
            let exactLower = try ExactRationalCoefficient.originalDouble(lower, usage: &usage)
            let exactUpper = try ExactRationalCoefficient.originalDouble(upper, usage: &usage)
            var first = OriginalCurveRootEndpoint.authored(lower)
            var last = OriginalCurveRootEndpoint.authored(upper)
            var interior: [OriginalCurveRootBoundary] = []
            for boundary in rootsBySpan[spanIndex] ?? [] {
                try usage.consumeExactWork(1)
                let isRationalStation = boundary.isolationLower == boundary.isolationUpper
                if isRationalStation, boundary.isolationLower == exactLower {
                    first = .algebraic(boundary)
                } else if isRationalStation, boundary.isolationLower == exactUpper {
                    last = .algebraic(boundary)
                } else {
                    guard interior.count < maximumSpanCount else {
                        throw GeometryConversionError.resourceLimitExceeded("Original revolution exhausted its root boundary count admission.")
                    }
                    try usage.retainExactStorage(1)
                    interior.append(boundary)
                }
            }
            try usage.retainExactStorage(interior.count)
            interior = try interior.sorted { a, b in
                let difference = try a.isolationLower.subtracting(b.isolationLower, usage: &usage)
                if !difference.isZero { return difference.isNegative }
                // Exact rational stations precede roots whose interval excludes
                // that same lower station. No floating root estimate orders them.
                return !a.excludesLowerEndpoint && b.excludesLowerEndpoint
            }
            try usage.retainExactStorage(interior.count + 2)
            var endpoints: [OriginalCurveRootEndpoint] = []
            endpoints.reserveCapacity(interior.count + 2)
            endpoints.append(first)
            for boundary in interior { endpoints.append(.algebraic(boundary)) }
            endpoints.append(last)
            for index in 0..<(endpoints.count - 1) {
                guard output.count < maximumSpanCount else {
                    throw GeometryConversionError.resourceLimitExceeded("Original revolution exhausted its chart count admission.")
                }
                try usage.retainExactStorage(1)
                let chart = try OriginalCurveRootSpan3D(source: .bSpline(source),
                    start: endpoints[index], end: endpoints[index + 1], nativeSpanIndex: spanIndex,
                    maximumParameterWidth: maximumParameterWidth,
                    maximumSubdivisionDepth: maximumSubdivisionDepth,
                    tolerance: tolerance, usage: &usage)
                output.append(Span(chart: chart, isWholeAxis: wholeAxisIntervals.contains(interval),
                    originalAxisOrigin: origin, originalAxisDirection: direction))
            }
        }
        guard !output.isEmpty else {
            throw GeometryConversionError.invalidInput("Original revolution has no positive native generator interval.")
        }
        return output
    }
}
