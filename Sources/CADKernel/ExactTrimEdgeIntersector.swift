import Foundation
import CADCore
import CADGeometry
import CADModeling
import CADTopology

enum ExactTrimEdgeIntersectionResult: Sendable {
    case subdivisionPoints([Point3D])
    case coincident
}

struct ExactTrimEdgeIntersector {
    func intersections(
        _ first: BRepSewingEdge,
        _ second: BRepSewingEdge,
        tolerance: ModelingTolerance
    ) throws -> ExactTrimEdgeIntersectionResult {
        try tolerance.validate()
        if try spansAreEquivalent(first, second, tolerance: tolerance) {
            return .coincident
        }

        if let partitioned = try partitionedCoincidenceIntersections(
            first,
            second,
            tolerance: tolerance
        ) {
            return .subdivisionPoints(partitioned)
        }

        return .subdivisionPoints(try discreteIntersections(
            first,
            second,
            tolerance: tolerance
        ))
    }

    private func discreteIntersections(
        _ first: BRepSewingEdge,
        _ second: BRepSewingEdge,
        tolerance: ModelingTolerance
    ) throws -> [Point3D] {
        if let lifted = try surfaceLiftIntersections(
            first,
            second,
            tolerance: tolerance
        ) {
            return lifted
        }

        let firstCurve = try exactRationalCurve(first, tolerance: tolerance)
        let secondCurve = try exactRationalCurve(second, tolerance: tolerance)
        var attempts: [(source: BRepSewingEdge, ruled: BRepSewingEdge, curve: BSplineCurve3D)] = []
        if let secondCurve {
            attempts.append((source: first, ruled: second, curve: secondCurve))
        }
        if let firstCurve {
            attempts.append((source: second, ruled: first, curve: firstCurve))
        }
        guard attempts.isEmpty == false else {
            throw KernelError(
                phase: .geometry,
                code: .unsupportedCapability,
                tolerance: tolerance,
                message: "Exact trim-edge intersection requires at least one bounded analytic or rational B-spline span."
            )
        }

        var failures: [KernelError] = []
        for attempt in attempts {
            for direction in [Vector3D.unitX, .unitY, .unitZ] {
                do {
                    let points = try intersections(
                        source: attempt.source,
                        ruled: attempt.ruled,
                        ruledCurve: attempt.curve,
                        extrusionDirection: direction,
                        tolerance: tolerance
                    )
                    return points
                } catch let error as KernelError {
                    failures.append(error)
                }
            }
        }

        let residual = failures.compactMap(\.residual).min()
        let details = failures.prefix(3).map {
            "\($0.code.rawValue): \($0.message)"
        }.joined(separator: " | ")
        throw KernelError(
            phase: .geometry,
            code: failures.contains(where: { $0.code == .nonDiscreteIntersection })
                ? .nonDiscreteIntersection
                : .intersectionFailure,
            residual: residual,
            tolerance: tolerance,
            message: "Every exact ruled-surface chart failed to certify the trim-edge intersection. \(details)"
        )
    }

    private func partitionedCoincidenceIntersections(
        _ first: BRepSewingEdge,
        _ second: BRepSewingEdge,
        tolerance: ModelingTolerance
    ) throws -> [Point3D]? {
        let candidates = try structuralPoints(first, tolerance: tolerance)
            + structuralPoints(second, tolerance: tolerance)
        var sharedPoints: [Point3D] = []
        for point in candidates where
            try BRepSewingEdgeSubdivider().contains(
                point,
                on: first,
                tolerance: tolerance
            ) && BRepSewingEdgeSubdivider().contains(
                point,
                on: second,
                tolerance: tolerance
            ) {
            appendUnique(point, to: &sharedPoints, tolerance: tolerance)
        }
        guard sharedPoints.count >= 2 else { return nil }

        let firstSegments = try BRepSewingEdgeSubdivider().subdivide(
            first,
            at: sharedPoints,
            tolerance: tolerance
        )
        let secondSegments = try BRepSewingEdgeSubdivider().subdivide(
            second,
            at: sharedPoints,
            tolerance: tolerance
        )
        let pairCount = firstSegments.count * secondSegments.count
        guard pairCount <= 16_384 else {
            throw KernelError(
                phase: .geometry,
                code: .resourceLimitExceeded,
                residual: Double(pairCount),
                tolerance: tolerance,
                message: "Exact coincident trim partitioning exceeded its span-pair budget."
            )
        }

        var coincidentPairs = Set<SpanPair>()
        for firstIndex in firstSegments.indices {
            for secondIndex in secondSegments.indices where try spansAreEquivalent(
                firstSegments[firstIndex],
                secondSegments[secondIndex],
                tolerance: tolerance
            ) {
                coincidentPairs.insert(SpanPair(
                    firstIndex: firstIndex,
                    secondIndex: secondIndex
                ))
            }
        }
        guard coincidentPairs.isEmpty == false else { return nil }

        var points: [Point3D] = []
        for pair in coincidentPairs {
            let span = firstSegments[pair.firstIndex]
            appendUnique(span.startPoint, to: &points, tolerance: tolerance)
            appendUnique(span.endPoint, to: &points, tolerance: tolerance)
        }
        for firstIndex in firstSegments.indices {
            for secondIndex in secondSegments.indices {
                let pair = SpanPair(
                    firstIndex: firstIndex,
                    secondIndex: secondIndex
                )
                guard coincidentPairs.contains(pair) == false else { continue }
                let discrete = try discreteIntersections(
                    firstSegments[firstIndex],
                    secondSegments[secondIndex],
                    tolerance: tolerance
                )
                for point in discrete {
                    appendUnique(point, to: &points, tolerance: tolerance)
                }
            }
        }
        return points.sorted(by: pointOrder)
    }

    private func structuralPoints(
        _ edge: BRepSewingEdge,
        tolerance: ModelingTolerance
    ) throws -> [Point3D] {
        var points = [edge.startPoint, edge.endPoint]
        let curve: BSplineCurve3D
        let pointAt: (Double) throws -> Point3D
        let lower: Double
        let upper: Double
        switch edge.curve {
        case let .bSpline(bSpline):
            curve = bSpline
            lower = min(edge.startParameter, edge.endParameter)
            upper = max(edge.startParameter, edge.endParameter)
            pointAt = { parameter in
                try bSpline.point(at: parameter, tolerance: tolerance)
            }
        case let .surfaceLift(lift):
            guard case let .bSpline(parameterCurve) = edge.surfaceParameterCurve else {
                return points
            }
            curve = embedded(parameterCurve)
            guard case let .closed(domainLower, domainUpper) = parameterCurve.domain else {
                return points
            }
            lower = domainLower
            upper = domainUpper
            pointAt = { parameter in
                let uv = try parameterCurve.point(at: parameter, tolerance: tolerance)
                return try lift.surface.point(
                    u: uv.x,
                    v: uv.y,
                    tolerance: tolerance
                )
            }
        case .line, .circle, .analytic, .implicit, .certifiedIntersection:
            return points
        }
        let scale = max(abs(lower), abs(upper), abs(upper - lower), 1.0)
        let resolution = max(
            tolerance.relative * scale,
            Double.ulpOfOne * scale * 256.0
        )
        var previous: Double?
        for knot in curve.knots.sorted() where
            knot > lower + resolution && knot < upper - resolution {
            if let previous, abs(knot - previous) <= resolution { continue }
            appendUnique(
                try pointAt(knot),
                to: &points,
                tolerance: tolerance
            )
            previous = knot
        }
        return points
    }

    private func surfaceLiftIntersections(
        _ first: BRepSewingEdge,
        _ second: BRepSewingEdge,
        tolerance: ModelingTolerance
    ) throws -> [Point3D]? {
        guard case let .surfaceLift(firstLift) = first.curve,
              case let .surfaceLift(secondLift) = second.curve,
              firstLift.surface == secondLift.surface,
              case let .bSpline(firstPcurve) = first.surfaceParameterCurve,
              case let .bSpline(secondPcurve) = second.surfaceParameterCurve else {
            return nil
        }
        try first.surfaceParameterCurve.validate(
            on: firstLift.surface,
            tolerance: tolerance
        )
        try second.surfaceParameterCurve.validate(
            on: secondLift.surface,
            tolerance: tolerance
        )
        let firstCurve = embedded(firstPcurve)
        let secondCurve = embedded(secondPcurve)
        let extent = max(
            firstPcurve.controlPoints.reduce(0.0) { result, point in
                max(result, hypot(point.x, point.y))
            },
            secondPcurve.controlPoints.reduce(0.0) { result, point in
                max(result, hypot(point.x, point.y))
            },
            1.0
        )
        let ruled = try ruledSurface(
            curve: secondCurve,
            offset: .unitZ * extent,
            tolerance: tolerance
        )
        let intersections = try DefaultCurveSurfaceIntersector().intersections(
            curve: .bSpline(firstCurve),
            surface: .bSpline(ruled),
            options: CurveSurfaceIntersectionOptions(
                curveRange: try parameterRange(firstCurve),
                surfaceURange: try parameterRange(secondCurve),
                surfaceVRange: try ScalarInterval(lower: 0.0, upper: 1.0),
                maximumSubdivisionDepth: 16,
                maximumSubdivisionCells: 1_048_576,
                maximumIterations: 64,
                maximumCandidateCount: 16_384
            ),
            tolerance: tolerance
        )
        var points: [Point3D] = []
        for intersection in intersections {
            let liftedPoint = try firstLift.surface.point(
                u: intersection.point.x,
                v: intersection.point.y,
                tolerance: tolerance
            )
            guard try BRepSewingEdgeSubdivider().contains(
                liftedPoint,
                on: first,
                tolerance: tolerance
            ), try BRepSewingEdgeSubdivider().contains(
                liftedPoint,
                on: second,
                tolerance: tolerance
            ) else {
                continue
            }
            appendUnique(liftedPoint, to: &points, tolerance: tolerance)
        }
        return points.sorted(by: pointOrder)
    }

    private func embedded(_ curve: BSplineCurve2D) -> BSplineCurve3D {
        BSplineCurve3D(
            degree: curve.degree,
            knots: curve.knots,
            controlPoints: curve.controlPoints.map {
                Point3D(x: $0.x, y: $0.y, z: 0.0)
            },
            weights: curve.weights
        )
    }

    private func intersections(
        source: BRepSewingEdge,
        ruled: BRepSewingEdge,
        ruledCurve: BSplineCurve3D,
        extrusionDirection: Vector3D,
        tolerance: ModelingTolerance
    ) throws -> [Point3D] {
        let extent = max(
            (source.endPoint - source.startPoint).length,
            (ruled.endPoint - ruled.startPoint).length,
            tolerance.distance * 1_024.0
        )
        let surface = try ruledSurface(
            curve: ruledCurve,
            offset: extrusionDirection * extent,
            tolerance: tolerance
        )
        let sourceRange = try parameterRange(source)
        let ruledRange = try parameterRange(ruledCurve)
        let intersections = try DefaultCurveSurfaceIntersector().intersections(
            curve: source.curve,
            surface: .bSpline(surface),
            options: CurveSurfaceIntersectionOptions(
                curveRange: sourceRange,
                surfaceURange: ruledRange,
                surfaceVRange: try ScalarInterval(lower: 0.0, upper: 1.0),
                maximumSubdivisionDepth: 16,
                maximumSubdivisionCells: 1_048_576,
                maximumIterations: 64,
                maximumCandidateCount: 16_384
            ),
            tolerance: tolerance
        )
        var points: [Point3D] = []
        for intersection in intersections {
            guard try BRepSewingEdgeSubdivider().contains(
                intersection.point,
                on: source,
                tolerance: tolerance
            ), try BRepSewingEdgeSubdivider().contains(
                intersection.point,
                on: ruled,
                tolerance: tolerance
            ) else {
                continue
            }
            appendUnique(intersection.point, to: &points, tolerance: tolerance)
        }
        return points.sorted(by: pointOrder)
    }

    private func spansAreEquivalent(
        _ first: BRepSewingEdge,
        _ second: BRepSewingEdge,
        tolerance: ModelingTolerance
    ) throws -> Bool {
        let matcher = CurveSpanCoincidenceMatcher()
        let firstSpan = CurveSpanDefinition(first)
        let secondSpan = CurveSpanDefinition(second)
        return try matcher.matches(
            firstSpan,
            secondSpan,
            orientation: .forward,
            tolerance: tolerance
        ) || matcher.matches(
            firstSpan,
            secondSpan,
            orientation: .reversed,
            tolerance: tolerance
        )
    }

    private func exactRationalCurve(
        _ edge: BRepSewingEdge,
        tolerance: ModelingTolerance
    ) throws -> BSplineCurve3D? {
        let range = try parameterRange(edge)
        if case let .bSpline(curve) = edge.curve {
            return try curve.trimmed(
                from: range.lower,
                to: range.upper,
                tolerance: tolerance
            )
        }
        return try AnalyticCurveBSplineBuilder().boundedCurve(
            curve: edge.curve,
            interval: range,
            maximumSpanCount: 4_096,
            tolerance: tolerance
        )
    }

    private func ruledSurface(
        curve: BSplineCurve3D,
        offset: Vector3D,
        tolerance: ModelingTolerance
    ) throws -> BSplineSurface3D {
        let lower = curve.controlPoints.map { $0 + offset * -1.0 }
        let upper = curve.controlPoints.map { $0 + offset }
        let surface = BSplineSurface3D(
            uDegree: curve.degree,
            vDegree: 1,
            uKnots: curve.knots,
            vKnots: [0.0, 0.0, 1.0, 1.0],
            controlPoints: [lower, upper],
            weights: [curve.weights, curve.weights]
        )
        try surface.validate(tolerance: tolerance)
        return surface
    }

    private func parameterRange(_ edge: BRepSewingEdge) throws -> ScalarInterval {
        try ScalarInterval(
            lower: min(edge.startParameter, edge.endParameter),
            upper: max(edge.startParameter, edge.endParameter)
        )
    }

    private func parameterRange(_ curve: BSplineCurve3D) throws -> ScalarInterval {
        guard case let .closed(lower, upper) = curve.domain else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: nil,
                message: "An exact ruled trim surface requires a bounded rational curve."
            )
        }
        return try ScalarInterval(lower: lower, upper: upper)
    }

    private func appendUnique(
        _ point: Point3D,
        to points: inout [Point3D],
        tolerance: ModelingTolerance
    ) {
        guard points.contains(where: {
            $0.isApproximatelyEqual(to: point, tolerance: tolerance.distance)
        }) == false else {
            return
        }
        points.append(point)
    }

    private func pointOrder(_ lhs: Point3D, _ rhs: Point3D) -> Bool {
        if lhs.x != rhs.x { return lhs.x < rhs.x }
        if lhs.y != rhs.y { return lhs.y < rhs.y }
        return lhs.z < rhs.z
    }

    private struct SpanPair: Hashable, Sendable {
        let firstIndex: Int
        let secondIndex: Int
    }
}
