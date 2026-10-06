import CADCore

/// Requested-order original derivative coefficients with explicit caller admission.
package struct OriginalCurveHigherJetProvider {
    package static func intervalTaylorJet(of curve: Curve3D, over range: ScalarInterval,
        tolerance: ModelingTolerance, throughOrder order: Int, maximumSpanCount: Int,
        maximumSubdivisionDepth: Int, remainingSourceDepth: Int,
        consumeWork: () throws -> Void, consumeStorage: ((Int) throws -> Void)? = nil,
        maximumAlgebraicDepth: Int? = nil) throws -> SurfaceAreaIntervalTaylorVectorJet {
        guard order >= 0, maximumSpanCount > 0, remainingSourceDepth >= 0,
              maximumSubdivisionDepth >= 0, range.lower.isFinite, range.upper.isFinite else {
            throw GeometryConversionError.invalidInput("Original higher curve queries require caller order, span, source-depth and subdivision admission.")
        }
        if let maximumAlgebraicDepth, !(0...32).contains(maximumAlgebraicDepth) {
            throw GeometryConversionError.invalidInput("Original higher curve queries require an independent algebra cap in zero through thirty-two.")
        }
        try CurrentTaskCancellationChecker().checkCancellation(); try consumeWork()
        try curve.validateOriginalSource(tolerance: tolerance, remainingSourceDepth: remainingSourceDepth,
            maximumSubdivisionDepth: maximumSubdivisionDepth, consumeWork: { _ in try consumeWork() }, consumeStorage: consumeStorage,
            maximumAlgebraicDepth: maximumAlgebraicDepth)
        if consumeStorage != nil {
            switch curve {
            case .originalAngularTransport, .originalConstructionChart, .originalEndpointConnector, .originalPlaneDerivative, .originalGuideTraversalChain, .originalGuideEndpointConnector, .originalPolyline, .originalDrafted, .line, .circle, .analytic(.line), .analytic(.circle), .analytic(.arc),
                 .analytic(.ellipse), .analytic(.hyperbola), .analytic(.parabola),
                 .parameterImage, .rigidImage, .affineImage, .originalAffineWord, .surfaceLift, .implicit: break
            case .bSpline(let source) where !source.isPeriodic: break
            default:
                // FIXME(INCOMPLETE_IMPLEMENTATION): Bounded original higher
                // curve consumers request paid Taylor storage. Periodic native,
                // implicit, lifted and certified branches still need their
                // actual remaining temporary allocation callbacks before success.
                throw KernelError(phase: .geometry, code: .unsupportedCapability, tolerance: tolerance,
                    message: "Original higher curve family has no complete Taylor byte admission.")
            }
        }
        func child(_ source: Curve3D, _ parameters: ScalarInterval) throws -> SurfaceAreaIntervalTaylorVectorJet {
            guard remainingSourceDepth > 0 else {
                throw GeometryConversionError.resourceLimitExceeded("Original higher curve source recursion exhausted caller depth.")
            }
            return try intervalTaylorJet(of: source, over: parameters, tolerance: tolerance,
                throughOrder: order, maximumSpanCount: maximumSpanCount,
                maximumSubdivisionDepth: maximumSubdivisionDepth,
                remainingSourceDepth: remainingSourceDepth - 1, consumeWork: consumeWork, consumeStorage: consumeStorage,
                maximumAlgebraicDepth: maximumAlgebraicDepth)
        }
        switch curve {
        case .originalAngularTransport(let image):
            return try image.intervalTaylorJet(over: range, throughOrder: order, tolerance: tolerance,
                consumeWork: consumeWork, consumeStorage: consumeStorage)
        case .originalConstructionChart(let image):
            return try image.intervalTaylorJet(over: range, throughOrder: order, tolerance: tolerance,
                maximumSpanCount: maximumSpanCount, maximumSubdivisionDepth: maximumSubdivisionDepth,
                remainingSourceDepth: remainingSourceDepth, consumeWork: consumeWork, consumeStorage: consumeStorage)
        case .originalPlaneDerivative(let original):
            return try original.intervalTaylorJet(over: range, throughOrder: order, tolerance: tolerance,
                maximumSpanCount: maximumSpanCount, maximumSubdivisionDepth: maximumSubdivisionDepth,
                remainingSourceDepth: remainingSourceDepth, consumeWork: consumeWork, consumeStorage: consumeStorage)
        case .originalGuideTraversalChain(let original):
            guard order <= 3 else {
                // FIXME(INCOMPLETE_IMPLEMENTATION): Shared higher consumers
                // require original guide derivatives above D3. The current
                // retained guide source supplies D0-D3 only; no construction
                // or aggregate hull may replace that missing derivative law.
                throw KernelError(phase: .geometry, code: .unsupportedCapability, tolerance: tolerance,
                    message: "Original guide chain has no derivative issuer above D3.")
            }
            return try original.intervalTaylorJet(over: range, throughOrder: order, tolerance: tolerance,
                maximumSpanCount: maximumSpanCount, maximumSubdivisionDepth: maximumSubdivisionDepth,
                remainingSourceDepth: remainingSourceDepth, consumeWork: consumeWork, consumeStorage: consumeStorage,
                maximumAlgebraicDepth: maximumAlgebraicDepth)
        case .originalPolyline(let original):
            guard order <= 3 else {
                // FIXME(INCOMPLETE_IMPLEMENTATION): General higher consumers
                // need a selected original polyline smooth law above D3. Owning
                // segment jets cannot authorize derivatives across a corner.
                throw KernelError(phase: .geometry, code: .unsupportedCapability, tolerance: tolerance,
                    message: "Original polyline has no shared higher issuer above D3.")
            }
            return try original.intervalTaylorJet(over: range, throughOrder: order, tolerance: tolerance,
                maximumSpanCount: maximumSpanCount, maximumSubdivisionDepth: maximumSubdivisionDepth,
                remainingSourceDepth: remainingSourceDepth, consumeWork: consumeWork, consumeStorage: consumeStorage,
                maximumAlgebraicDepth: maximumAlgebraicDepth)
        case .originalGuideEndpointConnector(let original):
            guard order <= 3 else {
                // FIXME(INCOMPLETE_IMPLEMENTATION): Shared higher consumers
                // require original guide derivatives above D3. The current
                // retained guide source supplies D0-D3 only; no construction
                // or aggregate hull may replace that missing derivative law.
                throw KernelError(phase: .geometry, code: .unsupportedCapability, tolerance: tolerance,
                    message: "Original guide endpoint correction has no derivative issuer above D3.")
            }
            return try original.intervalTaylorJet(over: range, throughOrder: order, tolerance: tolerance,
                maximumSpanCount: maximumSpanCount, maximumSubdivisionDepth: maximumSubdivisionDepth,
                remainingSourceDepth: remainingSourceDepth, consumeWork: consumeWork, consumeStorage: consumeStorage,
                maximumAlgebraicDepth: maximumAlgebraicDepth)
        case .originalDrafted(let original):
            return try original.intervalTaylorJet(over: range, throughOrder: order, tolerance: tolerance,
                maximumSpanCount: maximumSpanCount, maximumSubdivisionDepth: maximumSubdivisionDepth,
                remainingSourceDepth: remainingSourceDepth, consumeWork: consumeWork, consumeStorage: consumeStorage)
        case .originalEndpointConnector(let connector):
            return try connector.intervalTaylorJet(over: range, throughOrder: order, tolerance: tolerance,
                maximumSpanCount: maximumSpanCount, maximumSubdivisionDepth: maximumSubdivisionDepth,
                remainingSourceDepth: remainingSourceDepth, consumeWork: consumeWork, consumeStorage: consumeStorage)
        case .bSpline(let source):
            let spans = try RationalBezierCurveJetEncloser().originalNativeSpans(of: source,
                tolerance: tolerance, consumeWork: consumeWork, consumeStorage: consumeStorage)
            guard let first = spans.first, let last = spans.last else {
                throw GeometryConversionError.invalidInput("Original higher native curve has no span authority.")
            }
            func admitSmooth(_ query: ScalarInterval) throws {
                var index = source.degree
                while index <= source.controlPoints.count {
                    try consumeWork()
                    let knot = source.knots[index]
                    var end = index + 1
                    while end < source.knots.count, source.knots[end] == knot { try consumeWork(); end += 1 }
                    var start = index
                    while start > 0, source.knots[start - 1] == knot { try consumeWork(); start -= 1 }
                    let interior = knot > first.lower && knot < last.upper
                    if interior, (knot > query.lower && knot < query.upper
                        || query.lower == query.upper && knot == query.lower),
                        source.degree - (end - start) < order {
                        let left = start - 1, right = end - 1
                        try OriginalCurveHigherContinuity.prove(source: source,
                            leftSpan: left, rightSpan: right, leftParameter: knot, rightParameter: knot,
                            throughOrder: order, maximumSubdivisionDepth: maximumSubdivisionDepth,
                            tolerance: tolerance, consumeWork: consumeWork, consumeStorage: consumeStorage)
                    }
                    index = end
                }
            }
            var result: SurfaceAreaIntervalTaylorVectorJet?, count = 0
            func retain(_ query: ScalarInterval) throws {
                try admitSmooth(query)
                for span in spans {
                    try consumeWork()
                    let lower = max(query.lower, span.lower), upper = min(query.upper, span.upper)
                    guard lower <= upper, query.lower == query.upper || lower < upper else { continue }
                    count += 1
                    guard count <= maximumSpanCount else {
                        throw GeometryConversionError.resourceLimitExceeded("Original higher native curve cover exhausted caller span admission.")
                    }
                    let value = try OriginalNativeCurveHigherTaylor.enclosure(of: span,
                        over: ScalarInterval(lower: lower, upper: upper), order: order,
                        tolerance: tolerance, consumeWork: consumeWork, consumeStorage: consumeStorage)
                    result = try result.map { try OriginalCurveTaylorComposition.hull($0, value,
                        order: order, consumeWork: consumeWork, consumeStorage: consumeStorage) } ?? value
                }
            }
            if source.isPeriodic {
                let independent = source.controlPoints.count - source.degree
                for knotIndex in 0..<(source.knots.count - independent) {
                    try consumeWork()
                    let left = FloatingPointExpansion.difference(source.knots[knotIndex + independent], source.knots[knotIndex])
                    let reference = FloatingPointExpansion.difference(last.upper, first.lower)
                    guard FloatingPointExpansion.sign(FloatingPointExpansion.subtract(left, reference)) == .zero else {
                        // FIXME(INCOMPLETE_IMPLEMENTATION): Periodic source values
                        // whose stored knot translation is only numerically close
                        // need an original exact seam chart, not rounded shifting.
                        throw KernelError(phase: .geometry, code: .unsupportedCapability, tolerance: tolerance,
                            message: "Original periodic higher source lacks an exact stored knot translation.")
                    }
                }
                let seamMultiplicity = source.knots.reduce(0) { $0 + ($1 == first.lower ? 1 : 0) }
                if source.degree - seamMultiplicity < order {
                    guard let firstPositive = (source.degree..<source.controlPoints.count).first(where: {
                        source.knots[$0] < source.knots[$0 + 1]
                    }), let lastPositive = (source.degree..<source.controlPoints.count).last(where: {
                        source.knots[$0] < source.knots[$0 + 1]
                    }) else {
                        throw GeometryConversionError.invalidInput("Original periodic curve has no native seam sides.")
                    }
                    try OriginalCurveHigherContinuity.prove(source: source, leftSpan: lastPositive,
                        rightSpan: firstPositive, leftParameter: last.upper, rightParameter: first.lower,
                        throughOrder: order, maximumSubdivisionDepth: maximumSubdivisionDepth,
                        tolerance: tolerance, consumeWork: consumeWork)
                }
                let period = OutwardScalarInterval.exact(last.upper) - .exact(first.lower)
                guard period.lower > 0, period.lower.isFinite, period.upper.isFinite else {
                    throw GeometryConversionError.invalidInput("Original periodic higher source has no positive finite period.")
                }
                let estimatedPeriod = last.upper - first.lower
                let lowerCycle = ((range.lower - last.upper) / estimatedPeriod).rounded(.down)
                let upperCycle = ((range.upper - first.lower) / estimatedPeriod).rounded(.up)
                guard lowerCycle.isFinite, upperCycle.isFinite,
                    abs(lowerCycle) <= 9_007_199_254_740_990, abs(upperCycle) <= 9_007_199_254_740_990 else {
                    throw GeometryConversionError.resourceLimitExceeded("Original higher periodic source exceeds exact integer cycle admission.")
                }
                var cycle = lowerCycle
                while cycle <= upperCycle {
                    try CurrentTaskCancellationChecker().checkCancellation(); try consumeWork()
                    let shifted = OutwardScalarInterval(lower: range.lower, upper: range.upper)
                        - period * .exact(cycle)
                    if let native = shifted.intersection(with: .init(lower: first.lower, upper: last.upper)) {
                        try retain(ScalarInterval(lower: native.lower, upper: native.upper))
                    }
                    cycle += 1
                }
            } else {
                guard range.lower >= first.lower, range.upper <= last.upper else {
                    throw GeometryConversionError.invalidInput("Original higher curve query exceeds the native domain.")
                }
                try retain(range)
            }
            guard let result else { throw GeometryConversionError.invalidInput("Original higher curve span cover is empty.") }
            return result
        case .parameterImage(let image):
            let source = try child(image.source, image.originalInterval(range, consumeWork:consumeWork))
            let scale = try image.parameterGain.interval()
            return try .init(x: OriginalCurveTaylorComposition.scaledParameter(source.x, scale: scale, order: order, consumeWork: consumeWork, consumeStorage: consumeStorage),
                y: OriginalCurveTaylorComposition.scaledParameter(source.y, scale: scale, order: order, consumeWork: consumeWork, consumeStorage: consumeStorage),
                z: OriginalCurveTaylorComposition.scaledParameter(source.z, scale: scale, order: order, consumeWork: consumeWork, consumeStorage: consumeStorage))
        case .originalAffineWord(let image):
            if let coefficients = image.circularCoefficients {
                return try coefficients.intervalTaylorJet(over: range, throughOrder: order,
                    tolerance: tolerance, consumeWork: consumeWork, consumeStorage: consumeStorage)
            }
            return try OriginalAffineWordJetTransport.applying(image.preparedWord,
                to: intervalTaylorJet(of: image.source, over: range,
                    tolerance: image.sourceCalculationTolerance(tolerance: tolerance, consumeWork: consumeWork, consumeStorage: consumeStorage),
                    throughOrder: order, maximumSpanCount: maximumSpanCount,
                    maximumSubdivisionDepth: maximumSubdivisionDepth, remainingSourceDepth: remainingSourceDepth - 1,
                    consumeWork: consumeWork, consumeStorage: consumeStorage,
                    maximumAlgebraicDepth: maximumAlgebraicDepth),
                consumeWork: consumeWork, consumeStorage: consumeStorage).retagTolerance(to: tolerance)
        case .affineImage(let image):
            return try OriginalCurveTaylorComposition.transformed(child(image.source, range),
                by: image.transform, consumeWork: consumeWork, consumeStorage: consumeStorage)
        case .rigidImage(let image):
            let transform = try AffineTransform3D(basisX: image.transform.basisX,
                basisY: image.transform.basisY, basisZ: image.transform.basisZ,
                translation: image.transform.translation)
            return try OriginalCurveTaylorComposition.transformed(child(image.source, range),
                by: transform, consumeWork: consumeWork, consumeStorage: consumeStorage)
        case .implicit(let intersection):
            let uv = try OriginalImplicitCurveHigherTaylor.parameterJets(of: intersection, over: range,
                order: order, tolerance: tolerance, maximumSpanCount: maximumSpanCount,
                maximumSubdivisionDepth: maximumSubdivisionDepth,
                remainingSourceDepth: remainingSourceDepth, consumeWork: consumeWork, consumeStorage: consumeStorage,
                maximumAlgebraicDepth: maximumAlgebraicDepth)
            return try lift(surface: intersection.firstSurface, u: uv[0], v: uv[1], order: order,
                tolerance: tolerance, maximumSpanCount: maximumSpanCount,
                maximumSubdivisionDepth: maximumSubdivisionDepth, remainingSourceDepth: remainingSourceDepth, consumeWork: consumeWork, consumeStorage: consumeStorage,
                maximumAlgebraicDepth: maximumAlgebraicDepth)
        case .surfaceLift(let source):
            if case .originalAffineWord(let image) = source.parameterCurve {
                let original = try child(.surfaceLift(image.source), image.mappedRange(range))
                let scale = OutwardScalarInterval.exact(image.endFraction) - .exact(image.startFraction)
                let scaled = try SurfaceAreaIntervalTaylorVectorJet(
                    x: OriginalCurveTaylorComposition.scaledParameter(original.x, scale: scale, order: order, consumeWork: consumeWork, consumeStorage: consumeStorage),
                    y: OriginalCurveTaylorComposition.scaledParameter(original.y, scale: scale, order: order, consumeWork: consumeWork, consumeStorage: consumeStorage),
                    z: OriginalCurveTaylorComposition.scaledParameter(original.z, scale: scale, order: order, consumeWork: consumeWork, consumeStorage: consumeStorage))
                return try OriginalAffineWordJetTransport.applying(image.target.preparedWord,
                    to: scaled, consumeWork: consumeWork, consumeStorage: consumeStorage)
            }
            if case .originalImage(let image) = source.parameterCurve {
                let original = try child(.surfaceLift(image.source), image.mappedRange(range))
                let scale = OutwardScalarInterval.exact(image.endFraction) - .exact(image.startFraction)
                let scaled = try SurfaceAreaIntervalTaylorVectorJet(
                    x: OriginalCurveTaylorComposition.scaledParameter(original.x, scale: scale, order: order, consumeWork: consumeWork, consumeStorage: consumeStorage),
                    y: OriginalCurveTaylorComposition.scaledParameter(original.y, scale: scale, order: order, consumeWork: consumeWork, consumeStorage: consumeStorage),
                    z: OriginalCurveTaylorComposition.scaledParameter(original.z, scale: scale, order: order, consumeWork: consumeWork, consumeStorage: consumeStorage))
                return try OriginalCurveTaylorComposition.transformed(scaled, by: image.targetImage.transform, consumeWork: consumeWork, consumeStorage: consumeStorage)
            }
            if case .certifiedImplicit(let chart) = source.parameterCurve {
                // FIXME(INCOMPLETE_IMPLEMENTATION): Original implicit lifted
                // jets now retain paid cell-local recurrence. Complete critical
                // transitions and cross-cell smoothness remain original lower
                // obligations before a whole-chain higher result can succeed.
                let scale = OutwardScalarInterval.exact(chart.endFraction) - .exact(chart.startFraction)
                let mapped = .exact(chart.startFraction) + scale
                    * OutwardScalarInterval(lower: range.lower, upper: range.upper)
                let domain = OutwardScalarInterval(lower: min(chart.startFraction, chart.endFraction),
                    upper: max(chart.startFraction, chart.endFraction))
                guard let contained = mapped.intersection(with: domain) else {
                    throw GeometryConversionError.invalidInput("Original implicit higher lift has no directed native image.")
                }
                let all = try OriginalImplicitCurveHigherTaylor.parameterJets(of: chart.intersection,
                    over: ScalarInterval(lower: contained.lower, upper: contained.upper), order: order,
                    tolerance: tolerance, maximumSpanCount: maximumSpanCount,
                    maximumSubdivisionDepth: maximumSubdivisionDepth,
                    remainingSourceDepth: remainingSourceDepth, consumeWork: consumeWork, consumeStorage: consumeStorage,
                maximumAlgebraicDepth: maximumAlgebraicDepth)
                let index = chart.role == .first ? 0 : 2
                let u = try OriginalCurveTaylorComposition.scaledParameter(all[index], scale: scale, order: order, consumeWork: consumeWork, consumeStorage: consumeStorage)
                let v = try OriginalCurveTaylorComposition.scaledParameter(all[index + 1], scale: scale, order: order, consumeWork: consumeWork, consumeStorage: consumeStorage)
                return try lift(surface: source.surface, u: u, v: v, order: order,
                    tolerance: tolerance, maximumSpanCount: maximumSpanCount,
                    maximumSubdivisionDepth: maximumSubdivisionDepth, remainingSourceDepth: remainingSourceDepth, consumeWork: consumeWork, consumeStorage: consumeStorage,
                maximumAlgebraicDepth: maximumAlgebraicDepth)
            }
            let uv = try OriginalParameterCurveHigherTaylor.enclosure(source.parameterCurve,
                over: range, order: order, tolerance: tolerance, maximumSpanCount: maximumSpanCount,
                maximumSubdivisionDepth: maximumSubdivisionDepth,
                remainingSourceDepth: remainingSourceDepth, consumeWork: consumeWork, consumeStorage: consumeStorage,
                maximumAlgebraicDepth: maximumAlgebraicDepth)
            return try lift(surface: source.surface, u: uv.u, v: uv.v, order: order,
                tolerance: tolerance, maximumSpanCount: maximumSpanCount,
                maximumSubdivisionDepth: maximumSubdivisionDepth, remainingSourceDepth: remainingSourceDepth, consumeWork: consumeWork, consumeStorage: consumeStorage,
                maximumAlgebraicDepth: maximumAlgebraicDepth)
        case .line, .circle, .analytic:
            return try analytic(curve, over: range, order: order, tolerance: tolerance,
                consumeWork: consumeWork, consumeStorage: consumeStorage)
        case .certifiedIntersection:
            // FIXME(INCOMPLETE_IMPLEMENTATION): Original certified analytic-pair
            // branch laws need their requested-order scalar implicit recurrence.
            // Silhouette and offset callers must not promote their existing D3
            // certificate or a converted spline into an original C4 source.
            throw KernelError(phase: .geometry, code: .unsupportedCapability, tolerance: tolerance,
                message: "Original analytic intersection higher branch coefficients are not yet available.")
        }
    }

    private static func lift(surface: Surface3D, u: SurfaceAreaIntervalTaylorScalarJet,
        v: SurfaceAreaIntervalTaylorScalarJet, order: Int, tolerance: ModelingTolerance,
        maximumSpanCount: Int, maximumSubdivisionDepth: Int, remainingSourceDepth: Int, consumeWork: () throws -> Void,
        consumeStorage: ((Int) throws -> Void)? = nil, maximumAlgebraicDepth: Int? = nil)
        throws -> SurfaceAreaIntervalTaylorVectorJet {
        let a = try u.coefficient(0, 0), b = try v.coefficient(0, 0)
        let source = try OriginalSurfaceHigherJetProvider.intervalTaylorJet(of: surface,
            over: SurfaceParameterBox(u: ScalarInterval(lower: a.lower, upper: a.upper),
                v: ScalarInterval(lower: b.lower, upper: b.upper)), tolerance: tolerance,
            throughOrder: order, maximumSpanCount: maximumSpanCount,
            maximumSubdivisionDepth: maximumSubdivisionDepth, remainingSourceDepth: remainingSourceDepth, consumeWork: consumeWork, consumeStorage: consumeStorage,
            maximumAlgebraicDepth: maximumAlgebraicDepth ?? 32)
        return try OriginalCurveTaylorComposition.compose(surface: source, u: u, v: v,
            order: order, consumeWork: consumeWork, consumeStorage: consumeStorage)
    }

    private static func analytic(_ curve: Curve3D, over range: ScalarInterval, order: Int,
        tolerance: ModelingTolerance, consumeWork: () throws -> Void,
        consumeStorage: ((Int) throws -> Void)?) throws -> SurfaceAreaIntervalTaylorVectorJet {
        guard let source = try DefaultCurveDifferentialEncloser().directJet(curve,
            parameters: range, tolerance: tolerance, consumeWork: consumeWork,
            consumeStorage: consumeStorage) else {
            // FIXME(INCOMPLETE_IMPLEMENTATION): Plane-torus source branches
            // need original requested-order branch derivatives before this
            // public higher-jet production path may claim their coverage.
            throw KernelError(phase: .geometry, code: .unsupportedCapability, tolerance: tolerance,
                message: "Original analytic branch higher Taylor law is unavailable.")
        }
        let cycle: OutwardScalarInterval
        switch curve {
        case .circle, .analytic(.circle), .analytic(.arc), .analytic(.ellipse):
            cycle = -(CanonicalSphereAngularPhase.scaleBounds * CanonicalSphereAngularPhase.scaleBounds)
        case .analytic(.hyperbola): cycle = .exact(1)
        default: cycle = .exact(0)
        }
        func coordinate(_ jet: SurfaceIntervalJet) throws -> SurfaceAreaIntervalTaylorScalarJet {
            var result = try SurfaceAreaIntervalTaylorScalarJet(order: order, axis: .u,
                tolerance: tolerance, consumeWork: consumeWork, consumeStorage: consumeStorage)
            let count = order.addingReportingOverflow(1)
            guard !count.overflow else { throw GeometryConversionError.resourceLimitExceeded("Original analytic derivative count overflows.") }
            try OriginalCoefficientAllocation.reserve(count: count.partialValue,
                of: OutwardScalarInterval.self, consumeStorage: consumeStorage)
            var derivatives: [OutwardScalarInterval] = []
            derivatives.reserveCapacity(count.partialValue)
            for k in 0...min(order, 3) {
                try consumeWork()
                switch k {
                case 0: derivatives.append(jet.value)
                case 1: derivatives.append(jet.derivativeU)
                case 2: derivatives.append(jet.secondDerivativeUU)
                default: derivatives.append(jet.thirdDerivativeUUU)
                }
            }
            if order >= 4 {
                for k in 4...order { try consumeWork(); derivatives.append(derivatives[k - 2] * cycle) }
            }
            for k in 0...order {
                var value = derivatives[k]
                if k > 1 { for i in 2...k {
                    try consumeWork()
                    guard let divided = value.divided(by: .exact(Double(i))) else {
                        throw GeometryConversionError.resourceLimitExceeded("Original analytic factorial scaling failed.")
                    }
                    value = divided
                } }
                try result.set(value, k, 0)
            }
            return result
        }
        return try .init(x: coordinate(source.x), y: coordinate(source.y), z: coordinate(source.z))
    }
}
