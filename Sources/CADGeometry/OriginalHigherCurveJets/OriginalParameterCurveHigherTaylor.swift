import CADCore

/// Original normalized UV chart coefficients with requested derivative order.
struct OriginalParameterCurveHigherTaylor {
    static func enclosure(_ curve: SurfaceParameterCurve, over range: ScalarInterval,
        order: Int, tolerance: ModelingTolerance, maximumSpanCount: Int,
        maximumSubdivisionDepth: Int, remainingSourceDepth: Int,
        maximumAlgebraicDepth: Int? = nil, using execution: inout OriginalQueryExecution) throws -> (u: SurfaceAreaIntervalTaylorScalarJet, v: SurfaceAreaIntervalTaylorScalarJet) {
        guard order >= 0, maximumSpanCount > 0, maximumSubdivisionDepth >= 0,
            range.lower >= 0, range.upper <= 1, remainingSourceDepth > 0 else {
            throw GeometryConversionError.invalidInput("Original higher pcurve requires normalized source range and caller depth.")
        }
        if let maximumAlgebraicDepth, !(0...32).contains(maximumAlgebraicDepth) {
            throw GeometryConversionError.invalidInput("Original UV algebra admission must lie in the supported independent range.")
        }
        do {
            switch curve {
            case .bSpline, .originalBSplineContinuation, .affine, .constantU, .constantV, .harmonic, .polyline, .certifiedImplicit, .originalAffineWord, .originalImage, .periodicTranslation, .offsetSurfaceImage: break
            default:
                // FIXME(INCOMPLETE_IMPLEMENTATION): Bounded pcurve value/higher
                // consumers need actual harmonic/inverse/implicit scratch BYTE
                // callbacks before those original families may succeed.
                throw KernelError(phase: .geometry, code: .unsupportedCapability, tolerance: tolerance,
                    message: "Original pcurve family has no complete query byte producer.")
            }
        }
        func recurse(_ source: SurfaceParameterCurve, _ query: ScalarInterval)
            throws -> (u: SurfaceAreaIntervalTaylorScalarJet, v: SurfaceAreaIntervalTaylorScalarJet) {
            try enclosure(source, over: query, order: order, tolerance: tolerance,
                maximumSpanCount: maximumSpanCount, maximumSubdivisionDepth: maximumSubdivisionDepth,
                remainingSourceDepth: remainingSourceDepth - 1, maximumAlgebraicDepth: maximumAlgebraicDepth, using: &execution)
        }
        func scaled(_ source: SurfaceAreaIntervalTaylorScalarJet, _ scale: OutwardScalarInterval)
            throws -> SurfaceAreaIntervalTaylorScalarJet {
            try OriginalCurveTaylorComposition.scaledParameter(source, scale: scale,
                order: order, using: &execution)
        }
        switch curve {
        case .originalAffineWord(let image):
            let original = try recurse(image.source.parameterCurve, image.mappedRange(range))
            let scale = OutwardScalarInterval.exact(image.endFraction) - .exact(image.startFraction)
            return try (scaled(original.u, scale), scaled(original.v, scale))
        case .originalImage(let image):
            let source = try recurse(image.source.parameterCurve,
                image.mappedRange(range, maximumAlgebraicDepth: maximumAlgebraicDepth, using: &execution))
            let scale = OutwardScalarInterval.exact(image.endFraction) - .exact(image.startFraction)
            func inverse(_ original: SurfaceAreaIntervalTaylorScalarJet,
                gain: OriginalParameterGain, offset: Double) throws -> SurfaceAreaIntervalTaylorScalarJet {
                let traversed = try scaled(original, scale)
                var result = try SurfaceAreaIntervalTaylorScalarJet(order: order, axis: .u,
                    tolerance: tolerance, using: &execution)
                let nativeValue = try traversed.coefficient(0, 0)
                let foreignValue = try image.inverseParameterInterval(
                    ScalarInterval(lower: nativeValue.lower, upper: nativeValue.upper), gain: gain,
                    offset: offset, maximumAlgebraicDepth: maximumAlgebraicDepth, using: &execution)
                try result.set(OutwardScalarInterval(lower: foreignValue.lower, upper: foreignValue.upper), 0, 0)
                if order > 0 { for k in 1...order {
                    try execution.consumeWork(1)
                    let bound = try traversed.coefficient(k, 0)
                    let mapped = try image.inverseParameterInterval(
                        ScalarInterval(lower: bound.lower, upper: bound.upper), gain: gain, offset: 0,
                        maximumAlgebraicDepth: maximumAlgebraicDepth, using: &execution)
                    try result.set(.init(lower: mapped.lower, upper: mapped.upper), k, 0)
                }
                }
                return result
            }
            return try (inverse(image.targetImage.swapAxes ? source.v : source.u,
                    gain: image.targetImage.uParameterGain, offset: image.targetImage.uOffset),
                inverse(image.targetImage.swapAxes ? source.u : source.v,
                    gain: image.targetImage.vParameterGain, offset: image.targetImage.vOffset))
        case .rigidImage:
            // FIXME(INCOMPLETE_IMPLEMENTATION): Original higher lift/UV queries
            // need a retained rigid source-to-target chart law computed from
            // original plane/frame equations. Rounded affineParameterTransform
            // coefficients remain candidates and cannot authorize exact jets.
            throw KernelError(phase: .geometry, code: .unsupportedCapability, tolerance: tolerance,
                message: "Original rigid UV chart needs its retained exact chart-law producer.")
        case .offsetSurfaceImage(let image): return try recurse(image.source, range)
        case .periodicTranslation(let source, let u, let v):
            let jet = try recurse(source, range)
            let shiftedU = u == 0 ? jet.u : try jet.u.adding(.constant(.exact(u), order: order, axis: .u,
                tolerance: tolerance, using: &execution),
                using: &execution)
            let shiftedV = v == 0 ? jet.v : try jet.v.adding(.constant(.exact(v), order: order, axis: .u,
                tolerance: tolerance, using: &execution),
                using: &execution)
            return (shiftedU, shiftedV)
        case .certifiedImplicit(let chart):
            let scale = OutwardScalarInterval.exact(chart.endFraction) - .exact(chart.startFraction)
            let mapped = .exact(chart.startFraction) + scale
                * OutwardScalarInterval(lower: range.lower, upper: range.upper)
            guard let query = mapped.intersection(with: .init(lower: min(chart.startFraction, chart.endFraction),
                upper: max(chart.startFraction, chart.endFraction))) else {
                throw GeometryConversionError.invalidInput("Original implicit higher pcurve has no native range.")
            }
            let all = try OriginalImplicitCurveHigherTaylor.parameterJets(of: chart.intersection,
                over: ScalarInterval(lower: query.lower, upper: query.upper), order: order,
                tolerance: tolerance, maximumSpanCount: maximumSpanCount,
                maximumSubdivisionDepth: maximumSubdivisionDepth,
                remainingSourceDepth: remainingSourceDepth - 1, using: &execution)
            let index = chart.role == .first ? 0 : 2
            return try (scaled(all[index], scale), scaled(all[index + 1], scale))
        case .bSpline(let source):
            guard case .closed(let lower, let upper) = source.domain else {
                throw GeometryConversionError.invalidInput("Original higher normalized rational pcurve needs a finite native domain.")
            }
            let scale = OutwardScalarInterval.exact(upper) - .exact(lower)
            let mapped = .exact(lower) + scale * OutwardScalarInterval(lower: range.lower, upper: range.upper)
            guard let query = mapped.intersection(with: .init(lower: lower, upper: upper)) else {
                throw GeometryConversionError.invalidInput("Original higher rational pcurve native range is empty.")
            }
            try OriginalCoefficientAllocation.reserve(count: source.controlPoints.count, of: Point3D.self, using: &execution)
            let spatial = BSplineCurve3D(degree: source.degree, knots: source.knots,
                controlPoints: try source.controlPoints.map {
                    try execution.consumeWork(1); return Point3D(x: $0.x, y: $0.y, z: 0)
                }, weights: source.weights)
            let jet = try OriginalCurveHigherJetProvider.intervalTaylorJet(of: .bSpline(spatial),
                over: ScalarInterval(lower: query.lower, upper: query.upper), tolerance: tolerance,
                throughOrder: order, maximumSpanCount: maximumSpanCount,
                maximumSubdivisionDepth: maximumSubdivisionDepth,
                remainingSourceDepth: remainingSourceDepth - 1, maximumAlgebraicDepth: maximumAlgebraicDepth, using: &execution)
            var u = try scaled(jet.x, scale), v = try scaled(jet.y, scale)
            guard let first = source.controlPoints.first else {
                throw GeometryConversionError.invalidInput("Original rational pcurve has no Cartesian control hull.")
            }
            var uLower = first.x, uUpper = first.x, vLower = first.y, vUpper = first.y
            for point in source.controlPoints {
                try CurrentTaskCancellationChecker().checkCancellation(); try execution.consumeWork(1)
                uLower = min(uLower, point.x); uUpper = max(uUpper, point.x)
                vLower = min(vLower, point.y); vUpper = max(vUpper, point.y)
            }
            // Positive original weights prove this hull only on native support.
            try execution.consumeWork(1)
            guard let uValue = try u.coefficient(0, 0).intersection(with: .init(lower: uLower, upper: uUpper)),
                  let vValue = try v.coefficient(0, 0).intersection(with: .init(lower: vLower, upper: vUpper)) else {
                throw GeometryConversionError.invalidInput("Original rational pcurve value contradicts its Cartesian control hull.")
            }
            try u.set(uValue, 0, 0); try v.set(vValue, 0, 0)
            return (u, v)
        case .originalBSplineContinuation(let source):
            try OriginalCoefficientAllocation.reserve(count: source.original.controlPoints.count, of: Point3D.self, using: &execution)
            let spatial = BSplineCurve3D(degree: source.original.degree, knots: source.original.knots,
                controlPoints: try source.original.controlPoints.map {
                    try execution.consumeWork(1); return Point3D(x: $0.x, y: $0.y, z: 0)
                }, weights: source.original.weights)
            let spans = try RationalBezierCurveJetEncloser().originalNativeSpans(of: spatial,
                tolerance: tolerance, using: &execution)
            guard let first = spans.first, let last = spans.last, !spatial.isPeriodic else {
                // FIXME(INCOMPLETE_IMPLEMENTATION): Requested-order periodic
                // endpoint continuation needs the original cyclic chart cover,
                // rather than extrapolation of an endpoint span.
                throw KernelError(phase: .geometry, code: .unsupportedCapability, tolerance: tolerance,
                    message: "Original periodic continuation higher chart is not yet available.")
            }
            let scale = OutwardScalarInterval.exact(source.endParameter) - .exact(source.startParameter)
            let mapped = .exact(source.startParameter) + scale
                * OutwardScalarInterval(lower: range.lower, upper: range.upper)
            var result: SurfaceAreaIntervalTaylorVectorJet?, count = 0
            for span in spans {
                try execution.consumeWork(1)
                let lower = span.index == first.index ? mapped.lower : max(span.lower, mapped.lower)
                let upper = span.index == last.index ? mapped.upper : min(span.upper, mapped.upper)
                guard lower <= upper else { continue }
                count += 1
                guard count <= maximumSpanCount else {
                    throw GeometryConversionError.resourceLimitExceeded("Original higher continuation exhausted caller span cover.")
                }
                let value = try OriginalNativeCurveHigherTaylor.enclosure(of: span,
                    over: ScalarInterval(lower: lower, upper: upper), order: order, tolerance: tolerance,
                    continuation: true, using: &execution)
                result = try result.map { try OriginalCurveTaylorComposition.hull($0, value,
                    order: order, using: &execution) } ?? value
            }
            guard let result else { throw GeometryConversionError.invalidInput("Original higher continuation has no endpoint source cover.") }
            return try (scaled(result.x, scale), scaled(result.y, scale))
        case .polyline(let points):
            guard let maximumAlgebraicDepth else {
                // FIXME(INCOMPLETE_IMPLEMENTATION): Bounded original UV/lift
                // consumers need an explicit independent algebra capability for
                // the retained exact Euclidean polyline prefix/total law. Legacy
                // numerical prefixes cannot establish original bounds or joins.
                throw KernelError(phase: .geometry, code: .unsupportedCapability, tolerance: tolerance,
                    message: "Original Euclidean polyline bounds require caller algebra admission.")
            }
            return try OriginalPolylineParameterBounds.enclosure(points, over: range, order: order,
                tolerance: tolerance, maximumSpanCount: maximumSpanCount,
                maximumAlgebraicDepth: maximumAlgebraicDepth, using: &execution)
        case .affine, .constantU, .constantV, .harmonic:
            guard let base = try SurfaceParameterIntervalJet.enclose(curve, over: range, tolerance: tolerance, using: &execution) else {
                throw GeometryConversionError.invalidInput("Original numeric higher chart lost its base derivative law.")
            }
            let factor: OutwardScalarInterval
            if case .harmonic(_, _, _, let start, let end) = curve {
                let width = OutwardScalarInterval.exact(end) - .exact(start)
                factor = width * width * .exact(-1)
            } else { factor = .exact(0) }
            let uHull: OutwardScalarInterval?, vHull: OutwardScalarInterval?
            switch curve {
            case .constantU(let u, let start, let end):
                uHull = .exact(u); vHull = .init(lower: min(start, end), upper: max(start, end))
            case .constantV(let v, let start, let end):
                uHull = .init(lower: min(start, end), upper: max(start, end)); vHull = .exact(v)
            case .affine(let origin, let direction, _, _):
                uHull = direction.x == 0 ? .exact(origin.x) : nil
                vHull = direction.y == 0 ? .exact(origin.y) : nil
            default: uHull = nil; vHull = nil
            }
            func coordinate(_ scalar: SurfaceIntervalJet, valueHull: OutwardScalarInterval?) throws -> SurfaceAreaIntervalTaylorScalarJet {
                let count = order.addingReportingOverflow(1)
                guard !count.overflow else { throw GeometryConversionError.resourceLimitExceeded("Original pcurve derivative count overflows.") }
                try OriginalCoefficientAllocation.reserve(count: max(4, count.partialValue), of: OutwardScalarInterval.self, using: &execution)
                var derivative: [OutwardScalarInterval] = []
                derivative.reserveCapacity(max(4, count.partialValue))
                for k in 0..<4 {
                    try execution.consumeWork(1)
                    switch k {
                    case 0: derivative.append(scalar.value)
                    case 1: derivative.append(scalar.derivativeU)
                    case 2: derivative.append(scalar.secondDerivativeUU)
                    default: derivative.append(scalar.thirdDerivativeUUU)
                    }
                }
                if order >= 4 { for k in 4...order { try execution.consumeWork(1); derivative.append(derivative[k - 2] * factor) } }
                var result = try SurfaceAreaIntervalTaylorScalarJet(order: order, axis: .u,
                    tolerance: tolerance, using: &execution)
                for k in 0...order {
                    var value = derivative[k]
                    if k == 0, let valueHull {
                        try execution.consumeWork(1)
                        guard let bounded = value.intersection(with: valueHull) else {
                            throw GeometryConversionError.invalidInput("Original pcurve value contradicts its authored coordinate hull.")
                        }
                        value = bounded
                    }
                    if k > 1 { for divisor in 2...k {
                        try execution.consumeWork(1)
                        guard let next = value.divided(by: .exact(Double(divisor))) else {
                            throw GeometryConversionError.resourceLimitExceeded("Original higher pcurve factorial scaling failed.")
                        }
                        value = next
                    } }
                    try result.set(value, k, 0)
                }
                return result
            }
            return try (coordinate(base.u, valueHull: uHull), coordinate(base.v, valueHull: vHull))
        default:
            // FIXME(INCOMPLETE_IMPLEMENTATION): Nonlinear projected analytic,
            // rigid spherical, analytic-pair and piecewise UV chart laws need
            // their genuine requested-order derivative authority. Production
            // higher lift consumers must propagate this explicit missing domain.
            throw KernelError(phase: .geometry, code: .unsupportedCapability, tolerance: tolerance,
                message: "Original nonlinear pcurve higher chart coefficients are not yet available.")
        }
    }
}
