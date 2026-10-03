import CADCore
import Foundation

struct CurveSurfaceOverlapResolver {
    private struct Candidate {
        let range: ScalarInterval
        let deviation: Double
        var isoparametric: OverlapIsoparametricCorrespondence? = nil
    }

    func resolve(curve: Curve3D, surface: Surface3D, options: CurveSurfaceIntersectionOptions,
                 tolerance: ModelingTolerance, intersector: DefaultCurveSurfaceIntersector) throws -> CurveSurfaceIntersectionResult {
        try options.validate(tolerance: tolerance)
        try curve.validate(tolerance: tolerance)
        try surface.validate(tolerance: tolerance)
        try Task.checkCancellation()
        let range = try DefaultCurveSurfaceSearchRangeResolver().curveRange(curve: curve, surface: surface,
                                                                          requestedRange: options.curveRange, tolerance: tolerance)
        guard range.width.isFinite, range.width > 0, try curve.parameterDomain.containsSpan(from: range.lower, to: range.upper, tolerance: tolerance) else {
            throw failure(.invalidInput, "Continuous intersection queries require a positive interval in the curve domain.", tolerance)
        }
        let support = try proofSupport(surface, tolerance: tolerance)
        var rawOptions = options
        rawOptions.curveRange = range
        rawOptions.surfaceURange = nil
        rawOptions.surfaceVRange = nil
        var points: [CurveSurfaceIntersection] = []
        var candidates: [Candidate] = []

        if case .bSpline(let spline) = curve, case .bSpline(let target) = surface,
           let certificate = try OverlapIsoparametricMembershipCertifier().certificate(
               curve: spline, surface: target, range: range, options: options, tolerance: tolerance) {
            candidates.append(Candidate(range: range, deviation: certificate.deviation,
                isoparametric: certificate.correspondence))
        } else if case .bSpline(let spline) = curve {
            let spans = try BSplineCurveBezierDecomposer().curvePatches(curve: spline, intersecting: range, tolerance: tolerance)
            guard spans.count <= options.maximumSubdivisionCells else {
                throw failure(.resourceLimitExceeded, "Overlap source spans exceed the cell budget.", tolerance)
            }
            for span in spans {
                try Task.checkCancellation()
                let lower = max(span.lower, range.lower), upper = min(span.upper, range.upper)
                guard upper > lower else { continue }
                let interval = try ScalarInterval(lower: lower, upper: upper)
                let degree = span.controlPoints.count - 1
                let piece = BSplineCurve3D(degree: degree,
                    knots: Array(repeating: span.lower, count: degree + 1) + Array(repeating: span.upper, count: degree + 1),
                    controlPoints: span.controlPoints, weights: span.weights)
                var pieceOptions = rawOptions
                pieceOptions.curveRange = interval
                do {
                    points.append(contentsOf: try intersector.intersections(curve: .bSpline(piece), surface: support,
                                                                          options: pieceOptions, tolerance: tolerance))
                } catch let error as KernelError where error.code == .nonDiscreteIntersection {
                    // FIXME(INCOMPLETE_IMPLEMENTATION): Non-isoparametric free-surface
                    // coincidence without retained hosting provenance has no proof here.
                    // intersectionResult may succeed only after its complete correspondence
                    // and whole-span membership certificate are implemented.
                    if case .unsupported = CanonicalAnalyticSurface(support) {
                        throw failure(.unsupportedCapability, "Rational overlap on this free surface has no membership certificate.", tolerance)
                    }
                    let bound = try OverlapSpanMembershipCertifier(maximumDegree: options.maximumPolynomialDegree, tolerance: tolerance)
                        .deviation(of: span, on: CanonicalAnalyticSurface(support))
                    guard bound <= tolerance.distance else {
                        throw failure(.intersectionFailure, "A non-discrete rational span has no certified overlap distance bound at this tolerance.", tolerance)
                    }
                    candidates.append(Candidate(range: interval, deviation: bound))
                }
                try checkCount(points.count + candidates.count, options: options, tolerance: tolerance)
            }
        } else {
            do {
                if case .periodic(let period) = curve.parameterDomain {
                    var fundamentalOptions = rawOptions
                    fundamentalOptions.curveRange = try ScalarInterval(lower: 0, upper: period)
                    let fundamental = try intersector.intersections(curve: curve, surface: support,
                                                                   options: fundamentalOptions, tolerance: tolerance)
                    for event in fundamental {
                        let lowerCycle = ceil((range.lower - event.curveParameter) / period)
                        let upperCycle = floor((range.upper - event.curveParameter) / period)
                        guard lowerCycle.isFinite, upperCycle.isFinite,
                              abs(lowerCycle) <= 9_007_199_254_740_991, abs(upperCycle) <= 9_007_199_254_740_991,
                              upperCycle - lowerCycle < Double(options.maximumCandidateCount) else {
                            throw failure(.resourceLimitExceeded, "Periodic overlap boundary events exceed the finite cycle budget.", tolerance)
                        }
                        var cycle = lowerCycle
                        while cycle <= upperCycle {
                            try Task.checkCancellation()
                            points.append(try CurveSurfaceIntersection(point: event.point,
                                curveParameter: event.curveParameter + cycle * period,
                                surfaceU: event.surfaceU, surfaceV: event.surfaceV, kind: event.kind,
                                residual: event.residual, iterations: event.iterations))
                            try checkCount(points.count, options: options, tolerance: tolerance)
                            cycle += 1
                        }
                    }
                } else {
                    points = try intersector.intersections(curve: curve, surface: support, options: rawOptions, tolerance: tolerance)
                }
            } catch let error as KernelError where error.code == .nonDiscreteIntersection {
                let bound = try membershipBound(curve: curve, surface: surface, support: support,
                                                range: range, options: options, tolerance: tolerance)
                candidates.append(Candidate(range: range, deviation: bound))
            }
        }

        var admitted: [Candidate] = []
        for candidate in candidates {
            let clipping = try clip(candidate, curve: curve, surface: surface, options: options,
                                    tolerance: tolerance, intersector: intersector)
            admitted.append(contentsOf: clipping.candidates)
            points.append(contentsOf: clipping.points)
            try checkCount(points.count + admitted.count, options: options, tolerance: tolerance)
        }
        let merged = try merge(admitted)
        var uniquePoints: [CurveSurfaceIntersection] = []
        for event in points.sorted(by: { $0.curveParameter < $1.curveParameter }) {
            try Task.checkCancellation()
            let correspondence = candidates.first { $0.range.contains(event.curveParameter) }?.isoparametric
            guard !merged.contains(where: { $0.range.contains(event.curveParameter) }),
                  try contains(curve: curve, surface: surface, parameter: event.curveParameter, options: options,
                               tolerance: tolerance, isoparametric: correspondence) else { continue }
            if let last = uniquePoints.last, last.curveParameter == event.curveParameter { continue }
            let endpoint = try CurveSurfaceOverlap.evaluate(curve: curve, surface: surface, parameter: event.curveParameter,
                uRange: options.surfaceURange, vRange: options.surfaceVRange, tolerance: tolerance,
                isoparametric: correspondence)
            uniquePoints.append(try CurveSurfaceIntersection(point: endpoint.point, curveParameter: endpoint.curveParameter,
                surfaceU: endpoint.surfaceParameter.u, surfaceV: endpoint.surfaceParameter.v, kind: event.kind,
                residual: endpoint.residual, iterations: event.iterations))
        }
        let overlaps = try merged.map {
            try CurveSurfaceOverlap(curve: curve, surface: surface, range: $0.range, deviation: $0.deviation,
                                    options: options, tolerance: tolerance, isoparametric: $0.isoparametric)
        }
        try checkCount(uniquePoints.count + overlaps.count, options: options, tolerance: tolerance)
        return CurveSurfaceIntersectionResult(points: uniquePoints, overlaps: overlaps)
    }

    private func membershipBound(curve: Curve3D, surface: Surface3D, support: Surface3D,
                                 range: ScalarInterval, options: CurveSurfaceIntersectionOptions, tolerance: ModelingTolerance) throws -> Double {
        if try OverlapSourceMembershipResolver().isExactSource(surface, of: curve, tolerance: tolerance) {
            return tolerance.distance
        }
        if case .plane(let plane) = CanonicalAnalyticSurface(support) {
            return try OverlapPlanarMembershipCertifier().deviation(of: curve, over: range, on: plane, tolerance: tolerance)
        }
        if let rational = try AnalyticCurveBSplineBuilder().boundedCurve(curve: curve, interval: range,
            maximumSpanCount: options.maximumCandidateCount, tolerance: tolerance) {
            let spans = try BSplineCurveBezierDecomposer().curvePatches(curve: rational, tolerance: tolerance)
            let proof = OverlapSpanMembershipCertifier(maximumDegree: options.maximumPolynomialDegree, tolerance: tolerance)
            var bound = 0.0
            for span in spans {
                try Task.checkCancellation()
                bound = max(bound, try proof.deviation(of: span, on: CanonicalAnalyticSurface(support)))
            }
            guard bound <= tolerance.distance else {
                throw failure(.intersectionFailure, "The continuous analytic candidate cannot meet the whole-span distance bound.", tolerance)
            }
            return bound
        }
        // FIXME(INCOMPLETE_IMPLEMENTATION): Unretained non-affine free-surface coincidence
        // has no whole-span proof in intersectionResult. Completion requires certified
        // membership and complete overlap-domain isolation before this branch can succeed.
        throw failure(.unsupportedCapability, "This continuous curve-surface domain has no whole-span membership certificate.", tolerance)
    }

    private func proofSupport(_ surface: Surface3D, tolerance: ModelingTolerance) throws -> Surface3D {
        if case .bSpline(let spline) = surface, let affine = ExactAffineBSplineSurfacePatch(spline) {
            let normal = try affine.uDirection.cross(affine.vDirection).normalized(tolerance: tolerance.distance)
            return .plane(Plane3D(origin: affine.origin, normal: normal))
        }
        return surface
    }

    private func clip(_ candidate: Candidate, curve: Curve3D, surface: Surface3D, options: CurveSurfaceIntersectionOptions,
                      tolerance: ModelingTolerance, intersector: DefaultCurveSurfaceIntersector) throws -> (candidates: [Candidate], points: [CurveSurfaceIntersection]) {
        let boundaries = try OverlapChartBoundaryResolver().boundaries(curve: curve, surface: surface, options: options,
            tolerance: tolerance, isoparametric: candidate.isoparametric)
        var cuts = [candidate.range.lower, candidate.range.upper]
        for boundary in boundaries {
            try Task.checkCancellation()
            switch boundary {
            case .certifiedSourceParameter(let parameter):
                if candidate.range.contains(parameter) { cuts.append(parameter) }
            case let .plane(plane, parameterPlaneSource):
                var boundaryOptions = options
                boundaryOptions.curveRange = candidate.range
                boundaryOptions.surfaceURange = nil
                boundaryOptions.surfaceVRange = nil
                let source = parameterPlaneSource ?? curve
                let result = try resolve(curve: source, surface: plane, options: boundaryOptions,
                                         tolerance: tolerance, intersector: intersector)
                cuts.append(contentsOf: result.points.map(\.curveParameter))
                for overlap in result.overlaps { cuts.append(overlap.curveRange.lower); cuts.append(overlap.curveRange.upper) }
            }
            try checkCount(cuts.count, options: options, tolerance: tolerance)
        }
        cuts.sort()
        var unique: [Double] = []
        for cut in cuts where unique.last != cut { unique.append(cut) }
        var regions: [Candidate] = []
        for index in 0..<(unique.count - 1) {
            try Task.checkCancellation()
            let lower = unique[index], upper = unique[index + 1]
            guard upper > lower else { continue }
            let middle = lower + (upper - lower) * 0.5
            guard middle > lower, middle < upper else {
                throw failure(.classificationFailure, "An overlap clipping cell has no representable interior parameter.", tolerance)
            }
            // Each cut came from a complete boundary result. An open connected
            // cell has no boundary crossing, so one membership test classifies it.
            if try contains(curve: curve, surface: surface, parameter: middle, options: options, tolerance: tolerance,
                            isoparametric: candidate.isoparametric) {
                regions.append(Candidate(range: try ScalarInterval(lower: lower, upper: upper), deviation: candidate.deviation,
                                         isoparametric: candidate.isoparametric))
            }
        }
        var points: [CurveSurfaceIntersection] = []
        for cut in unique where !regions.contains(where: { $0.range.contains(cut) }) {
            if try contains(curve: curve, surface: surface, parameter: cut, options: options, tolerance: tolerance,
                            isoparametric: candidate.isoparametric) {
                let endpoint = try CurveSurfaceOverlap.evaluate(curve: curve, surface: surface, parameter: cut,
                    uRange: options.surfaceURange, vRange: options.surfaceVRange, tolerance: tolerance,
                    isoparametric: candidate.isoparametric)
                points.append(try CurveSurfaceIntersection(point: endpoint.point, curveParameter: cut,
                    surfaceU: endpoint.surfaceParameter.u, surfaceV: endpoint.surfaceParameter.v,
                    kind: .tangent, residual: endpoint.residual, iterations: 0))
            }
        }
        return (regions, points)
    }

    private func contains(curve: Curve3D, surface: Surface3D, parameter: Double,
                          options: CurveSurfaceIntersectionOptions, tolerance: ModelingTolerance,
                          isoparametric: OverlapIsoparametricCorrespondence? = nil) throws -> Bool {
        let point = try curve.point(at: parameter, tolerance: tolerance)
        let coordinates: SurfaceParameter
        if let isoparametric {
            coordinates = isoparametric.parameter(at: parameter)
        } else if case let .surfaceLift(lift) = curve, lift.surface == surface {
            coordinates = try lift.parameterCurve.parameter(atNormalizedFraction: parameter, tolerance: tolerance)
        } else {
            switch try surface.parameterProjectionResult(of: point, tolerance: tolerance) {
            case .projected(let projection): coordinates = SurfaceParameter(u: projection.u, v: projection.v)
            case .outsideTolerance:
                if case .bSpline(let spline) = surface, ExactAffineBSplineSurfacePatch(spline) != nil { return false }
                throw failure(.intersectionFailure, "A certified overlap candidate failed target membership verification.", tolerance)
            }
        }
        let resolver = SurfaceParameterRangeResolver()
        return resolver.resolvedParameter(coordinates.u, domain: surface.uDomain, requestedRange: options.surfaceURange, tolerance: tolerance) != nil
            && resolver.resolvedParameter(coordinates.v, domain: surface.vDomain, requestedRange: options.surfaceVRange, tolerance: tolerance) != nil
    }

    private func merge(_ candidates: [Candidate]) throws -> [Candidate] {
        var result: [Candidate] = []
        for candidate in candidates.sorted(by: { $0.range.lower < $1.range.lower }) {
            if let previous = result.last, candidate.range.lower <= previous.range.upper,
               previous.isoparametric == candidate.isoparametric {
                result[result.count - 1] = Candidate(range: try ScalarInterval(lower: previous.range.lower,
                    upper: max(previous.range.upper, candidate.range.upper)), deviation: max(previous.deviation, candidate.deviation),
                    isoparametric: previous.isoparametric)
            } else { result.append(candidate) }
        }
        return result
    }

    private func checkCount(_ count: Int, options: CurveSurfaceIntersectionOptions, tolerance: ModelingTolerance) throws {
        guard count <= options.maximumCandidateCount else { throw failure(.resourceLimitExceeded, "Continuous intersection results exceed the candidate budget.", tolerance) }
    }

    private func failure(_ code: KernelErrorCode, _ message: String, _ tolerance: ModelingTolerance) -> KernelError {
        KernelError(phase: .geometry, code: code, tolerance: tolerance, message: message)
    }
}
