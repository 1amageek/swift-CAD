import CADCore

/// Original normalized UV chart coefficients with requested derivative order.
struct OriginalParameterCurveHigherTaylor {
    static func enclosure(_ curve: SurfaceParameterCurve, over range: ScalarInterval,
        order: Int, tolerance: ModelingTolerance, maximumSpanCount: Int,
        maximumSubdivisionDepth: Int, remainingSourceDepth: Int,
        consumeWork: () throws -> Void, consumeStorage: ((Int) throws -> Void)? = nil,
        maximumAlgebraicDepth: Int? = nil) throws -> (u: SurfaceAreaIntervalTaylorScalarJet, v: SurfaceAreaIntervalTaylorScalarJet) {
        guard order >= 0, maximumSpanCount > 0, maximumSubdivisionDepth >= 0,
            range.lower >= 0, range.upper <= 1, remainingSourceDepth > 0 else {
            throw GeometryConversionError.invalidInput("Original higher pcurve requires normalized source range and caller depth.")
        }
        if let maximumAlgebraicDepth, !(0...32).contains(maximumAlgebraicDepth) {
            throw GeometryConversionError.invalidInput("Original UV algebra admission must lie in the supported independent range.")
        }
        if consumeStorage != nil {
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
                remainingSourceDepth: remainingSourceDepth - 1, consumeWork: consumeWork, consumeStorage: consumeStorage,
                maximumAlgebraicDepth: maximumAlgebraicDepth)
        }
        func scaled(_ source: SurfaceAreaIntervalTaylorScalarJet, _ scale: OutwardScalarInterval)
            throws -> SurfaceAreaIntervalTaylorScalarJet {
            try OriginalCurveTaylorComposition.scaledParameter(source, scale: scale,
                order: order, consumeWork: consumeWork, consumeStorage: consumeStorage)
        }
        switch curve {
        case .originalAffineWord(let image):
            let original = try recurse(image.source.parameterCurve, image.mappedRange(range))
            let scale = OutwardScalarInterval.exact(image.endFraction) - .exact(image.startFraction)
            return try (scaled(original.u, scale), scaled(original.v, scale))
        case .originalImage(let image):
            let source = try recurse(image.source.parameterCurve,
                image.mappedRange(range, consumeWork: consumeWork, consumeStorage: consumeStorage,
                    maximumAlgebraicDepth: maximumAlgebraicDepth))
            let scale = OutwardScalarInterval.exact(image.endFraction) - .exact(image.startFraction)
            func inverse(_ original: SurfaceAreaIntervalTaylorScalarJet,
                gain: OriginalParameterGain, offset: Double) throws -> SurfaceAreaIntervalTaylorScalarJet {
                let traversed = try scaled(original, scale)
                var result = try SurfaceAreaIntervalTaylorScalarJet(order: order, axis: .u,
                    tolerance: tolerance, consumeWork: consumeWork, consumeStorage: consumeStorage)
                let nativeValue = try traversed.coefficient(0, 0)
                let foreignValue = try image.inverseParameterInterval(
                    ScalarInterval(lower: nativeValue.lower, upper: nativeValue.upper), gain: gain,
                    offset: offset, consumeWork: consumeWork, consumeStorage: consumeStorage,
                    maximumAlgebraicDepth: maximumAlgebraicDepth)
                try result.set(OutwardScalarInterval(lower: foreignValue.lower, upper: foreignValue.upper), 0, 0)
                if order > 0 { for k in 1...order {
                    try consumeWork()
                    let bound = try traversed.coefficient(k, 0)
                    let mapped = try image.inverseParameterInterval(
                        ScalarInterval(lower: bound.lower, upper: bound.upper), gain: gain, offset: 0,
                        consumeWork: consumeWork, consumeStorage: consumeStorage,
                        maximumAlgebraicDepth: maximumAlgebraicDepth)
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
                tolerance: tolerance, consumeWork: consumeWork, consumeStorage: consumeStorage),
                consumeWork: consumeWork, consumeStorage: consumeStorage)
            let shiftedV = v == 0 ? jet.v : try jet.v.adding(.constant(.exact(v), order: order, axis: .u,
                tolerance: tolerance, consumeWork: consumeWork, consumeStorage: consumeStorage),
                consumeWork: consumeWork, consumeStorage: consumeStorage)
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
                remainingSourceDepth: remainingSourceDepth - 1, consumeWork: consumeWork, consumeStorage: consumeStorage)
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
            try OriginalCoefficientAllocation.reserve(count: source.controlPoints.count, of: Point3D.self, consumeStorage: consumeStorage)
            let spatial = BSplineCurve3D(degree: source.degree, knots: source.knots,
                controlPoints: try source.controlPoints.map {
                    try consumeWork(); return Point3D(x: $0.x, y: $0.y, z: 0)
                }, weights: source.weights)
            let jet = try OriginalCurveHigherJetProvider.intervalTaylorJet(of: .bSpline(spatial),
                over: ScalarInterval(lower: query.lower, upper: query.upper), tolerance: tolerance,
                throughOrder: order, maximumSpanCount: maximumSpanCount,
                maximumSubdivisionDepth: maximumSubdivisionDepth,
                remainingSourceDepth: remainingSourceDepth - 1, consumeWork: consumeWork, consumeStorage: consumeStorage,
                maximumAlgebraicDepth: maximumAlgebraicDepth)
            return try (scaled(jet.x, scale), scaled(jet.y, scale))
        case .originalBSplineContinuation(let source):
            try OriginalCoefficientAllocation.reserve(count: source.original.controlPoints.count, of: Point3D.self, consumeStorage: consumeStorage)
            let spatial = BSplineCurve3D(degree: source.original.degree, knots: source.original.knots,
                controlPoints: try source.original.controlPoints.map {
                    try consumeWork(); return Point3D(x: $0.x, y: $0.y, z: 0)
                }, weights: source.original.weights)
            let spans = try RationalBezierCurveJetEncloser().originalNativeSpans(of: spatial,
                tolerance: tolerance, consumeWork: consumeWork, consumeStorage: consumeStorage)
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
                try consumeWork()
                let lower = span.index == first.index ? mapped.lower : max(span.lower, mapped.lower)
                let upper = span.index == last.index ? mapped.upper : min(span.upper, mapped.upper)
                guard lower <= upper else { continue }
                count += 1
                guard count <= maximumSpanCount else {
                    throw GeometryConversionError.resourceLimitExceeded("Original higher continuation exhausted caller span cover.")
                }
                let value = try OriginalNativeCurveHigherTaylor.enclosure(of: span,
                    over: ScalarInterval(lower: lower, upper: upper), order: order, tolerance: tolerance,
                    continuation: true, consumeWork: consumeWork, consumeStorage: consumeStorage)
                result = try result.map { try OriginalCurveTaylorComposition.hull($0, value,
                    order: order, consumeWork: consumeWork, consumeStorage: consumeStorage) } ?? value
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
                maximumAlgebraicDepth: maximumAlgebraicDepth, consumeWork: consumeWork,
                consumeStorage: consumeStorage)
        case .affine, .constantU, .constantV, .harmonic:
            guard let base = try SurfaceParameterIntervalJet.enclose(curve, over: range, tolerance: tolerance, consumeWork: consumeWork) else {
                throw GeometryConversionError.invalidInput("Original numeric higher chart lost its base derivative law.")
            }
            let factor: OutwardScalarInterval
            if case .harmonic(_, _, _, let start, let end) = curve {
                let width = OutwardScalarInterval.exact(end) - .exact(start)
                factor = width * width * .exact(-1)
            } else { factor = .exact(0) }
            func coordinate(_ scalar: SurfaceIntervalJet) throws -> SurfaceAreaIntervalTaylorScalarJet {
                let count = order.addingReportingOverflow(1)
                guard !count.overflow else { throw GeometryConversionError.resourceLimitExceeded("Original pcurve derivative count overflows.") }
                try OriginalCoefficientAllocation.reserve(count: max(4, count.partialValue), of: OutwardScalarInterval.self, consumeStorage: consumeStorage)
                var derivative: [OutwardScalarInterval] = []
                derivative.reserveCapacity(max(4, count.partialValue))
                for k in 0..<4 {
                    try consumeWork()
                    switch k {
                    case 0: derivative.append(scalar.value)
                    case 1: derivative.append(scalar.derivativeU)
                    case 2: derivative.append(scalar.secondDerivativeUU)
                    default: derivative.append(scalar.thirdDerivativeUUU)
                    }
                }
                if order >= 4 { for k in 4...order { try consumeWork(); derivative.append(derivative[k - 2] * factor) } }
                var result = try SurfaceAreaIntervalTaylorScalarJet(order: order, axis: .u,
                    tolerance: tolerance, consumeWork: consumeWork, consumeStorage: consumeStorage)
                for k in 0...order {
                    var value = derivative[k]
                    if k > 1 { for divisor in 2...k {
                        try consumeWork()
                        guard let next = value.divided(by: .exact(Double(divisor))) else {
                            throw GeometryConversionError.resourceLimitExceeded("Original higher pcurve factorial scaling failed.")
                        }
                        value = next
                    } }
                    try result.set(value, k, 0)
                }
                return result
            }
            return try (coordinate(base.u), coordinate(base.v))
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
