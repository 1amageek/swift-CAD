import Foundation
import CADCore
import CADGeometry
import CADIR

package struct ExactBSplineCurveSpanBuilder: Sendable {
    private let tolerance: ModelingTolerance
    private let owner: OriginalSpanConstructionOwner

    package init(tolerance: ModelingTolerance, admission: GeometryConversionAdmission? = nil) {
        self.tolerance = tolerance
        owner = OriginalSpanConstructionOwner(tolerance: tolerance, admission: admission)
    }

    private func originalSource(_ curve: Curve3D) throws -> OriginalCurveSpanSource {
        let selected = try owner.admission()
        return try OriginalCurveSpanSource(curve: curve, tolerance: tolerance, admission: selected)
    }

    private func constructionSpan(curve: BSplineCurve3D, tolerance: ModelingTolerance,
        originalChart: OriginalCurveSpanParameterChart? = nil) throws -> ExactBSplineCurveSpan {
        try ExactBSplineCurveSpan(curve: curve, tolerance: tolerance,
            originalChart: originalChart, admission: owner.admission())
    }

    private func originalGeometry(_ curve: EvaluatedCurve,
        admission: GeometryConversionAdmission) throws -> OriginalEvaluatedCurveGeometry {
        try curve.validateOriginalGeometry(tolerance: tolerance,
            maximumSubdivisionDepth: admission.maximumSubdivisionDepth,
            remainingSourceDepth: admission.remainingSourceDepth,
            consumeWork: { try admission.visit(depth: $0) },
            consumeStorage: { try admission.chargeStorage(bytes: $0) },
            maximumAlgebraicDepth: admission.maximumAlgebraicDepth)
    }

    private func reversedConstructionSpan(_ span: ExactBSplineCurveSpan,
        admission: GeometryConversionAdmission) throws -> ExactBSplineCurveSpan {
        func retain<Value>(_ count: Int, of: Value.Type) throws {
            let bytes = count.multipliedReportingOverflow(by: MemoryLayout<Value>.stride)
            guard count >= 0, !bytes.overflow else {
                throw GeometryConversionError.resourceLimitExceeded("Directed span reversal payload overflows.")
            }
            try admission.chargeStorage(bytes: bytes.partialValue)
        }
        try retain(span.curve.knots.count, of: Double.self)
        try retain(span.curve.controlPoints.count, of: Point3D.self)
        try retain(span.curve.weights.count, of: Double.self)
        let knots = try span.curve.knots.reversed().map { knot in
            try admission.chargeWork(); return -knot
        }
        try admission.chargeWork(span.curve.controlPoints.count)
        try admission.chargeWork(span.curve.weights.count)
        let reversed = BSplineCurve3D(degree: span.curve.degree, knots: knots,
            controlPoints: Array(span.curve.controlPoints.reversed()),
            weights: Array(span.curve.weights.reversed()))
        return try constructionSpan(curve: reversed, tolerance: tolerance,
            originalChart: span.originalChart.reversed())
    }

    private func reverseConstructionSpans(_ spans: inout [ExactBSplineCurveSpan],
        admission: GeometryConversionAdmission) throws {
        for index in 0..<((spans.count + 1) / 2) {
            let other = spans.count - 1 - index
            let first = spans[index]
            let second = spans[other]
            spans[index] = try reversedConstructionSpan(second, admission: admission)
            if index != other { spans[other] = try reversedConstructionSpan(first, admission: admission) }
        }
    }

    package func normalizedConstructionSpan(
        from chart: OriginalCurveSpanParameterChart
    ) throws -> ExactBSplineCurveSpan {
        let admission = try owner.admission()
        let chart = chart.admittingConstruction(admission)
        let domain = try ScalarInterval(lower: 0, upper: 1)
        let source = try OriginalCurveConstructionSource(chart: chart, domain: domain,
            tolerance: tolerance, admission: admission)
        let result = try CertifiedGeometryConverter().approximateCurve(source: source,
            over: domain, requirements: GeometryConversionRequirements(
                maximumPositionError: tolerance.distance * 0.25,
                maximumTangentAngle: tolerance.angle,
                maximumCurvatureError: tolerance.distance),
            tolerance: tolerance, admission: admission)
        return try constructionSpan(curve: result.curve, tolerance: tolerance, originalChart: chart)
    }

    package func profileLoopSpans(
        from profile: Profile
    ) throws -> [[ExactBSplineCurveSpan]] {
        try profile.boundaryLoops.map { loop in
            try profileSpans(from: loop)
        }
    }

    /// Constructs from the retained original face edges, never its Profile image.
    package func faceLoopSpans(from section: ResolvedFaceSection) throws -> [[ExactBSplineCurveSpan]] {
        let admission = try owner.admission()
        func retain<Value>(_ count: Int, of: Value.Type) throws {
            let bytes = count.multipliedReportingOverflow(by: MemoryLayout<Value>.stride)
            guard count >= 0, !bytes.overflow else { throw GeometryConversionError.resourceLimitExceeded("Original face span payload overflows.") }
            try admission.chargeStorage(bytes: bytes.partialValue)
        }
        try retain(section.loops.count, of: [ExactBSplineCurveSpan].self)
        var loops: [[ExactBSplineCurveSpan]] = []
        loops.reserveCapacity(section.loops.count)
        for loop in section.loops {
            try admission.chargeWork()
            var result: [ExactBSplineCurveSpan] = []
            var capacity = 0
            for segment in loop.segments {
                try admission.chargeWork()
                var pieces = try spans(curve: segment.source.curve,
                    lower: min(segment.startParameter, segment.endParameter),
                    upper: max(segment.startParameter, segment.endParameter), sourceOwner: segment.source)
                if segment.endParameter < segment.startParameter {
                    try reverseConstructionSpans(&pieces, admission: admission)
                }
                let needed = result.count.addingReportingOverflow(pieces.count)
                guard !needed.overflow else { throw GeometryConversionError.resourceLimitExceeded("Original face span count overflows.") }
                if needed.partialValue > capacity {
                    let growth = capacity.multipliedReportingOverflow(by: 2)
                    let next = max(needed.partialValue, growth.overflow ? needed.partialValue : growth.partialValue)
                    try retain(next, of: ExactBSplineCurveSpan.self)
                    try admission.chargeWork(result.count)
                    result.reserveCapacity(next); capacity = next
                }
                for piece in pieces { try admission.chargeWork(); result.append(piece) }
            }
            try validateClosure(result)
            loops.append(result)
        }
        return loops
    }

    package func constructedRegionLoopSpans(from region: ResolvedBoundaryRegion) throws -> [[ExactBSplineCurveSpan]] {
        let admission = try owner.admission()
        try admission.chargeStorage(bytes: region.loops.count * MemoryLayout<[ExactBSplineCurveSpan]>.stride)
        var result: [[ExactBSplineCurveSpan]] = []
        result.reserveCapacity(region.loops.count)
        for charts in region.loops {
            try admission.chargeStorage(bytes: charts.count * MemoryLayout<ExactBSplineCurveSpan>.stride)
            var loop: [ExactBSplineCurveSpan] = []
            loop.reserveCapacity(charts.count)
            for chart in charts {
                try admission.chargeWork()
                loop.append(try normalizedConstructionSpan(from: chart))
            }
            try validateClosure(loop)
            result.append(loop)
        }
        return result
    }

    package func loopSpans(from section: ResolvedModelingSection) throws -> [[ExactBSplineCurveSpan]] {
        switch section {
        case .profile(let profile, _): return try profileLoopSpans(from: profile)
        case .face(let face, _): return try faceLoopSpans(from: face)
        case .constructedRegion(let region): return try constructedRegionLoopSpans(from: region)
        case .curve(let curve): return [try sectionSpans(from: curve)]
        }
    }

    package func profileSpans(
        from loop: ProfileLoop
    ) throws -> [ExactBSplineCurveSpan] {
        try tolerance.validate()
        var result: [ExactBSplineCurveSpan] = []
        for boundary in loop.boundarySegments {
            switch boundary {
            case let .line(line):
                result.append(try lineSpan(
                    from: line.start,
                    to: line.end
                ))
            case let .circularArc(arc):
                let circle = Circle3D(
                    center: arc.center,
                    normal: arc.normal,
                    radius: arc.radius
                )
                let exactCircle = Curve3D.circle(circle)
                let start = try exactCircle.parameterProjection(
                    of: arc.start,
                    tolerance: tolerance
                ).parameter
                result.append(contentsOf: try conicSpans(
                    curve: exactCircle,
                    center: circle.center,
                    lower: start,
                    sweep: arc.sweepAngle
                ))
            case let .spline(spline):
                result.append(contentsOf: try bSplineSpans(
                    spline.curve,
                    requestedDomain: spline.curve.domain
                ))
            }
        }
        guard result.count >= 2 else {
            throw SketchError.openProfile
        }
        try validateClosure(result)
        return result
    }

    /// The exact spans of a path; a closed path only when `allowsClosed`, for a consumer that
    /// closes it on itself.
    package func pathSpans(
        from segments: [EvaluatedCurvePathSegment],
        endingAt requestedEndPoint: Point3D? = nil,
        allowsClosed: Bool = false
    ) throws -> [ExactBSplineCurveSpan] {
        try tolerance.validate()
        guard segments.isEmpty == false else {
            throw FeatureEvaluationError.missingInput(
                "Exact sweep requires at least one path segment."
            )
        }
        var result: [ExactBSplineCurveSpan] = []
        let admission = try owner.admission()
        var capacity = 0
        for segment in segments {
            try admission.chargeWork()
            let original = try originalGeometry(segment.curve, admission: admission)
            let curve = original.curve
            let bounds: (lower: Double, upper: Double)
            switch original.parameterDomain {
            case let .closed(lower, upper):
                bounds = (lower, upper)
            case let .periodic(period) where allowsClosed && segments.count == 1 && original.isClosed:
                // A whole closed curve (a circle) taken once round as a closed path.
                bounds = (0, period)
            default:
                throw KernelError(
                    phase: .geometry,
                    code: .unsupportedCapability,
                    tolerance: tolerance,
                    message: "Exact sweep requires a bounded exact path curve."
                )
            }
            var spans = try spans(
                curve: curve,
                lower: bounds.lower,
                upper: bounds.upper,
                sourceOwner: originalSource(curve)
            )
            if segment.isReversed {
                try reverseConstructionSpans(&spans, admission: admission)
            }
            let needed = result.count.addingReportingOverflow(spans.count)
            guard !needed.overflow else { throw GeometryConversionError.resourceLimitExceeded("Original path span count overflows.") }
            if needed.partialValue > capacity {
                let growth = capacity.multipliedReportingOverflow(by: 2)
                let next = max(needed.partialValue, growth.overflow ? needed.partialValue : growth.partialValue)
                let bytes = next.multipliedReportingOverflow(by: MemoryLayout<ExactBSplineCurveSpan>.stride)
                guard !bytes.overflow else { throw GeometryConversionError.resourceLimitExceeded("Original path span payload overflows.") }
                try admission.chargeStorage(bytes: bytes.partialValue)
                try admission.chargeWork(result.count)
                result.reserveCapacity(next); capacity = next
            }
            for span in spans { try admission.chargeWork(); result.append(span) }
        }
        try validatePathContinuity(result)
        if let requestedEndPoint {
            result = try prefix(
                of: result,
                endingAt: requestedEndPoint
            )
        }
        guard let first = result.first,
              let last = result.last,
              allowsClosed || first.startPoint.isApproximatelyEqual(
                to: last.endPoint,
                tolerance: tolerance.distance
              ) == false else {
            throw KernelError(
                phase: .geometry,
                code: .unsupportedCapability,
                tolerance: tolerance,
                message: "Exact translational sweep currently requires an open path."
            )
        }
        return result
    }

    package func sectionSpans(sourceOwner: OriginalCurveSpanSource,
        lower: Double, upper: Double) throws -> [ExactBSplineCurveSpan] {
        let admission = try owner.admission()
        try admission.chargeWork()
        guard sourceOwner.prepared != nil, sourceOwner.preparationTolerance == tolerance,
              sourceOwner.admission != nil, lower.isFinite, upper.isFinite, lower < upper,
              try sourceOwner.curve.parameterDomain.containsSpan(from: lower, to: upper,
                tolerance: tolerance) else {
            throw GeometryConversionError.invalidInput("Original section spans require one prepared owner and its contained authored native trim.")
        }
        let result = try spans(curve: sourceOwner.curve, lower: lower, upper: upper,
            sourceOwner: sourceOwner)
        try validatePathContinuity(result)
        return result
    }

    package func sectionSpans(
        from section: EvaluatedCurve
    ) throws -> [ExactBSplineCurveSpan] {
        try tolerance.validate()
        let admission = try owner.admission()
        let original = try originalGeometry(section, admission: admission)
        let curve = original.curve
        let bounds: (lower: Double, upper: Double)
        switch original.parameterDomain {
        case let .closed(lower, upper):
            bounds = (lower, upper)
        case let .periodic(period):
            guard original.isClosed else {
                throw KernelError(
                    phase: .geometry,
                    code: .unsupportedCapability,
                    tolerance: tolerance,
                    message: "Exact sweep periodic sheet sections require an explicit closed trim."
                )
            }
            bounds = (0.0, period)
        case .unbounded:
            throw KernelError(
                phase: .geometry,
                code: .unsupportedCapability,
                tolerance: tolerance,
                message: "Exact sweep sheet sections require a bounded trim."
            )
        }
        let result = try spans(
            curve: curve,
            lower: bounds.lower,
            upper: bounds.upper,
            sourceOwner: originalSource(curve)
        )
        try validatePathContinuity(result)
        if original.isClosed {
            guard let first = result.first,
                  let last = result.last,
                  first.startPoint.isApproximatelyEqual(
                    to: last.endPoint,
                    tolerance: tolerance.distance
                  ) else {
                throw SketchError.openProfile
            }
        }
        return result
    }

    // FIXME(INCOMPLETE_IMPLEMENTATION): Requested-point Sweep paths currently
    // localize their final restriction on a construction candidate. Production
    // pathSpans(endingAt:) still needs a retained original endpoint localization
    // receipt and its exact directed chart restriction before this branch can
    // establish general original-law clipping or complete the Sweep contract.
    private func prefix(
        of spans: [ExactBSplineCurveSpan],
        endingAt requestedEndPoint: Point3D
    ) throws -> [ExactBSplineCurveSpan] {
        try requestedEndPoint.validate()
        var result: [ExactBSplineCurveSpan] = []
        for span in spans {
            if span.startPoint.isApproximatelyEqual(
                to: requestedEndPoint,
                tolerance: tolerance.distance
            ) {
                guard result.isEmpty == false else {
                    throw FeatureEvaluationError.invalidDistance(0.0)
                }
                return result
            }
            if span.endPoint.isApproximatelyEqual(
                to: requestedEndPoint,
                tolerance: tolerance.distance
            ) {
                result.append(span)
                return result
            }
            let parameter: Double
            do {
                parameter = try Curve3D.bSpline(span.curve).parameterProjection(
                    of: requestedEndPoint,
                    tolerance: tolerance
                ).parameter
            } catch let error as KernelError where error.code == .intersectionFailure {
                result.append(span)
                continue
            }
            guard case let .closed(lower, upper) = span.curve.domain else {
                throw KernelError(
                    phase: .geometry,
                    code: .invalidInput,
                    tolerance: tolerance,
                    message: "Exact sweep path span lost its bounded domain."
                )
            }
            let parameterTolerance = max(
                tolerance.angle,
                Double.ulpOfOne * max(abs(lower), abs(upper), 1.0) * 64.0
            )
            guard parameter > lower + parameterTolerance,
                  parameter < upper - parameterTolerance else {
                result.append(span)
                continue
            }
            let trimmed = try span.curve.trimmed(
                from: lower,
                to: parameter,
                tolerance: tolerance
            )
            result.append(try constructionSpan(
                curve: trimmed,
                tolerance: tolerance,
                originalChart: span.originalChart.restricted(from: lower, to: parameter,
                    in: span.curve.domain, tolerance: tolerance)
            ))
            guard result.last?.endPoint.isApproximatelyEqual(
                to: requestedEndPoint,
                tolerance: tolerance.distance
            ) == true else {
                throw KernelError(
                    phase: .geometry,
                    code: .intersectionFailure,
                    residual: result.last.map {
                        ($0.endPoint - requestedEndPoint).length
                    },
                    tolerance: tolerance,
                    message: "Exact sweep path prefix did not terminate at the requested path point."
                )
            }
            return result
        }
        throw KernelError(
            phase: .geometry,
            code: .intersectionFailure,
            tolerance: tolerance,
            message: "Exact sweep path endpoint does not lie on the ordered exact path."
        )
    }

    private func spans(
        curve: Curve3D,
        lower: Double,
        upper: Double,
        sourceOwner: OriginalCurveSpanSource? = nil
    ) throws -> [ExactBSplineCurveSpan] {
        guard lower.isFinite,
              upper.isFinite,
              (upper - lower).isFinite, upper > lower else {
            throw GeometryError.invalidDistance(upper - lower)
        }
        switch curve {
        case .line, .analytic(.line):
            let candidate = try lineSpan(from: curve.point(at: lower, tolerance: tolerance),
                to: curve.point(at: upper, tolerance: tolerance))
            return [try constructionSpan(curve: candidate.curve, tolerance: tolerance,
                originalChart: .init(source: try sourceOwner ?? originalSource(curve), startParameter: lower, endParameter: upper))]
        case let .circle(circle):
            return try conicSpans(
                curve: curve,
                center: circle.center,
                lower: lower,
                sweep: upper - lower, sourceOwner: sourceOwner, terminalParameter: upper
            )
        case let .analytic(analytic):
            let center: Point3D
            switch analytic {
            case let .circle(value, _, _),
                 let .arc(value, _, _, _, _),
                 let .ellipse(value, _, _, _, _):
                center = value
            case let .hyperbola(curve):
                return try hyperbolaSpans(
                    curve: curve,
                    lower: lower,
                    upper: upper
                )
            case let .parabola(curve):
                return [try parabolaSpan(
                    curve: curve,
                    lower: lower,
                    upper: upper
                )]
            case .line:
                throw KernelError(
                    phase: .geometry,
                    code: .invalidInput,
                    tolerance: tolerance,
                    message: "Exact line path dispatch is inconsistent."
                )
            case .planeTorus:
                return try certifiedNativeSpans(curve: curve, lower: lower, upper: upper, sourceOwner: sourceOwner)
            }
            return try conicSpans(
                curve: curve,
                center: center,
                lower: lower,
                sweep: upper - lower, sourceOwner: sourceOwner, terminalParameter: upper
            )
        case let .bSpline(spline):
            return try bSplineSpans(
                spline,
                requestedDomain: .closed(lower, upper), sourceOwner: sourceOwner
            )
        case .rigidImage, .affineImage, .originalAffineWord:
            // Certify the transformed original law; the previous candidate's
            // allowance does not survive rounding or affine amplification.
            return try certifiedNativeSpans(curve: curve, lower: lower, upper: upper, sourceOwner: sourceOwner)
        case let .parameterImage(image):
            if image.offset == 0, case let .binary(gain) = image.parameterGain, gain == -1 {
                return try spans(curve: image.source, lower: -upper, upper: -lower)
                    .reversed().map { span in
                        try constructionSpan(curve: span.curve.reversed(tolerance: tolerance),
                            tolerance: tolerance, originalChart: span.originalChart.reversed())
                    }
            }
            return try certifiedNativeSpans(curve: curve, lower: lower, upper: upper, sourceOwner: sourceOwner)
        case .implicit, .surfaceLift, .certifiedIntersection, .originalEndpointConnector,
             .originalGuideTraversalChain, .originalGuideEndpointConnector, .originalPolyline,
             .originalConstructionChart, .originalAngularTransport, .originalPlaneDerivative, .originalDrafted:
            return try certifiedNativeSpans(curve: curve, lower: lower, upper: upper, sourceOwner: sourceOwner)
        }
    }

    private func certifiedNativeSpans(curve: Curve3D, lower: Double, upper: Double,
        sourceOwner: OriginalCurveSpanSource? = nil) throws -> [ExactBSplineCurveSpan] {
        let original = try sourceOwner ?? originalSource(curve)
        let admission = try owner.admission()
        let parameters = try ScalarInterval(lower: lower, upper: upper)
        let source = try OriginalCurveConstructionSource(chart: .init(source: original,
            startParameter: lower, endParameter: upper), domain: parameters,
            tolerance: tolerance, admission: admission)
        let converted = try CertifiedGeometryConverter().approximateCurve(
            source: source, over: parameters,
            requirements: GeometryConversionRequirements(maximumPositionError: tolerance.distance * 0.25,
                maximumTangentAngle: tolerance.angle, maximumCurvatureError: tolerance.distance),
            tolerance: tolerance, admission: admission)
        return try bSplineSpans(converted.curve, requestedDomain: .closed(lower, upper),
            originalCurve: curve, sourceOwner: original)
    }

    private func lineSpan(
        from start: Point3D,
        to end: Point3D
    ) throws -> ExactBSplineCurveSpan {
        try constructionSpan(
            curve: BSplineCurve3D(
                degree: 1,
                knots: [0.0, 0.0, 1.0, 1.0],
                controlPoints: [start, end]
            ),
            tolerance: tolerance
        )
    }

    private func conicSpans(
        curve: Curve3D,
        center: Point3D,
        lower: Double,
        sweep: Double,
        sourceOwner: OriginalCurveSpanSource? = nil,
        terminalParameter: Double? = nil
    ) throws -> [ExactBSplineCurveSpan] {
        guard lower.isFinite, sweep.isFinite, abs(sweep) > 0, abs(sweep) <= 2 * Double.pi else {
            throw KernelError(phase: .geometry, code: .invalidInput, tolerance: tolerance,
                message: "Conic spans require a finite nonzero sweep covering at most one turn.")
        }
        let count = Int(ceil(abs(sweep) / (0.5 * Double.pi)))
        let originalSource = try sourceOwner ?? originalSource(curve)
        let firstPoint = try curve.point(at: lower, tolerance: tolerance)
        let closesPeriod: Bool
        if case let .periodic(period) = curve.parameterDomain {
            closesPeriod = abs(sweep) == period
        } else {
            closesPeriod = false
        }
        return try (0..<count).map { index in
            let start = index == 0 ? lower : lower + sweep * Double(index) / Double(count)
            let end = index == count - 1 ? (terminalParameter ?? (lower + sweep))
                : lower + sweep * Double(index + 1) / Double(count)
            let middle = 0.5 * (start + end)
            let halfAngle = 0.5 * (end - start)
            let weight = CanonicalSphereAngularPhase.candidate(at: halfAngle, cosine: true)
            guard weight > Double.ulpOfOne else {
                throw KernelError(
                    phase: .geometry,
                    code: .invalidInput,
                    tolerance: tolerance,
                    message: "Exact conic span produced a singular rational weight."
                )
            }
            let middlePoint = try curve.point(
                at: middle,
                tolerance: tolerance
            )
            return try constructionSpan(
                curve: BSplineCurve3D(
                    degree: 2,
                    knots: [0.0, 0.0, 0.0, 1.0, 1.0, 1.0],
                    controlPoints: [
                        index == 0 ? firstPoint : try curve.point(at: start, tolerance: tolerance),
                        center + (middlePoint - center) / weight,
                        index == count - 1 && closesPeriod
                            ? firstPoint : try curve.point(at: end, tolerance: tolerance),
                    ],
                    weights: [1.0, weight, 1.0]
                ),
                tolerance: tolerance,
                originalChart: .init(source: originalSource, startParameter: start,
                    endParameter: end, mapping: .circularRational)
            )
        }
    }

    private func hyperbolaSpans(
        curve: Hyperbola3D,
        lower: Double,
        upper: Double
    ) throws -> [ExactBSplineCurveSpan] {
        let exactCurve = Curve3D.analytic(.hyperbola(curve))
        let originalSource = try originalSource(exactCurve)
        let span = upper - lower
        let count = max(1, Int(ceil(abs(span))))
        return try (0..<count).map { index in
            let start = lower + span * Double(index) / Double(count)
            let end = lower + span * Double(index + 1) / Double(count)
            let middle = 0.5 * (start + end)
            let weight = cosh(0.5 * (end - start))
            guard weight.isFinite, weight > 0.0 else {
                throw KernelError(
                    phase: .geometry,
                    code: .resourceLimitExceeded,
                    residual: weight,
                    tolerance: tolerance,
                    message: "Exact hyperbola span exceeded finite rational weights."
                )
            }
            let middlePoint = try exactCurve.point(at: middle, tolerance: tolerance)
            return try constructionSpan(
                curve: BSplineCurve3D(
                    degree: 2,
                    knots: [0.0, 0.0, 0.0, 1.0, 1.0, 1.0],
                    controlPoints: [
                        try exactCurve.point(at: start, tolerance: tolerance),
                        curve.center + (middlePoint - curve.center) / weight,
                        try exactCurve.point(at: end, tolerance: tolerance),
                    ],
                    weights: [1.0, weight, 1.0]
                ),
                tolerance: tolerance,
                originalChart: .init(source: originalSource, startParameter: start,
                    endParameter: end, mapping: .hyperbolicRational)
            )
        }
    }

    private func parabolaSpan(
        curve: Parabola3D,
        lower: Double,
        upper: Double
    ) throws -> ExactBSplineCurveSpan {
        let exactCurve = Curve3D.analytic(.parabola(curve))
        let start = try curve.differentialGeometry(
            at: lower,
            tolerance: tolerance
        )
        let endPoint = try exactCurve.point(at: upper, tolerance: tolerance)
        return try constructionSpan(
            curve: BSplineCurve3D(
                degree: 2,
                knots: [0.0, 0.0, 0.0, 1.0, 1.0, 1.0],
                controlPoints: [
                    start.position,
                    start.position + start.firstDerivative * (0.5 * (upper - lower)),
                    endPoint,
                ]
            ),
            tolerance: tolerance,
            originalChart: .init(curve: exactCurve, startParameter: lower, endParameter: upper)
        )
    }

    private func bSplineSpans(
        _ source: BSplineCurve3D,
        requestedDomain: ParameterDomain,
        originalCurve: Curve3D? = nil,
        sourceOwner: OriginalCurveSpanSource? = nil
    ) throws -> [ExactBSplineCurveSpan] {
        try source.validate(tolerance: tolerance)
        guard case let .closed(lower, upper) = requestedDomain else {
            throw KernelError(
                phase: .geometry,
                code: .unsupportedCapability,
                tolerance: tolerance,
                message: "Exact sweep B-spline paths require a bounded trim."
            )
        }
        var breaks = [lower]
        for knot in source.knots where knot > lower && knot < upper {
            if breaks.last != knot {
                breaks.append(knot)
            }
        }
        breaks.append(upper)
        let start = try source.point(at: lower, tolerance: tolerance)
        let end = try source.point(at: upper, tolerance: tolerance)
        let originalSource = try sourceOwner ?? originalSource(originalCurve ?? .bSpline(source))
        if breaks.count == 2,
           start.isApproximatelyEqual(to: end, tolerance: tolerance.distance) {
            breaks.insert(0.5 * (lower + upper), at: 1)
        }
        return try (0..<(breaks.count - 1)).map { index in
            try constructionSpan(
                curve: source.trimmed(
                    from: breaks[index],
                    to: breaks[index + 1],
                    tolerance: tolerance
                ),
                tolerance: tolerance,
                originalChart: .init(source: originalSource,
                    startParameter: breaks[index], endParameter: breaks[index + 1])
            )
        }
    }

    private func validateClosure(
        _ spans: [ExactBSplineCurveSpan]
    ) throws {
        for index in spans.indices {
            let next = spans[(index + 1) % spans.count]
            guard spans[index].endPoint.isApproximatelyEqual(
                to: next.startPoint,
                tolerance: tolerance.distance
            ) else {
                throw SketchError.openProfile
            }
        }
    }

    private func validatePathContinuity(
        _ spans: [ExactBSplineCurveSpan]
    ) throws {
        guard spans.isEmpty == false else {
            throw FeatureEvaluationError.emptyResult(
                "Exact sweep path has no non-degenerate spans."
            )
        }
        for index in 0..<(spans.count - 1) {
            guard spans[index].endPoint.isApproximatelyEqual(
                to: spans[index + 1].startPoint,
                tolerance: tolerance.distance
            ) else {
                throw KernelError(
                    phase: .geometry,
                    code: .invalidInput,
                    tolerance: tolerance,
                    message: "Exact sweep path spans are disconnected."
                )
            }
        }
    }
}
