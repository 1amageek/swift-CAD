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
        let equivalent: Bool
        do {
            equivalent = try spansAreEquivalent(
                first,
                second,
                tolerance: tolerance
            )
        } catch {
            throw contextualized(
                error,
                stage: "whole-span coincidence classification",
                tolerance: tolerance
            )
        }
        if equivalent {
            return .coincident
        }

        let partitioned: [Point3D]?
        do {
            partitioned = try partitionedCoincidenceIntersections(
                first,
                second,
                tolerance: tolerance
            )
        } catch {
            throw contextualized(
                error,
                stage: "partitioned coincidence classification",
                tolerance: tolerance
            )
        }
        if let partitioned {
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
        let lifted: [Point3D]?
        do {
            lifted = try surfaceLiftIntersections(
                first,
                second,
                tolerance: tolerance
            )
        } catch {
            throw contextualized(
                error,
                stage: "shared-surface pcurve intersection",
                tolerance: tolerance
            )
        }
        if let lifted {
            return lifted
        }

        let firstCurve: BSplineCurve3D?
        let secondCurve: BSplineCurve3D?
        do {
            firstCurve = try exactRationalCurve(first, tolerance: tolerance)
            secondCurve = try exactRationalCurve(second, tolerance: tolerance)
        } catch {
            throw contextualized(
                error,
                stage: "rational chart preparation",
                tolerance: tolerance
            )
        }
        var attempts: [(source: BRepSewingEdge, ruled: BRepSewingEdge, curve: BSplineCurve3D)] = []
        if let secondCurve {
            attempts.append((source: first, ruled: second, curve: secondCurve))
        }
        if let firstCurve {
            attempts.append((source: second, ruled: first, curve: firstCurve))
        }
        attempts.sort { firstAttempt, secondAttempt in
            let firstHasAnalyticRuledPlane: Bool
            if case .line = firstAttempt.ruled.curve {
                firstHasAnalyticRuledPlane = true
            } else {
                firstHasAnalyticRuledPlane = false
            }
            let secondHasAnalyticRuledPlane: Bool
            if case .line = secondAttempt.ruled.curve {
                secondHasAnalyticRuledPlane = true
            } else {
                secondHasAnalyticRuledPlane = false
            }
            return firstHasAnalyticRuledPlane && secondHasAnalyticRuledPlane == false
        }
        guard attempts.isEmpty == false else {
            throw KernelError(
                phase: .geometry,
                code: .unsupportedCapability,
                tolerance: tolerance,
                message: "Exact trim-edge intersection requires at least one bounded analytic or rational B-spline span."
            )
        }

        // Shared or touching endpoints are structural crossing data. They
        // are collected up front, excluded from the chart search range so a
        // slowly separating contact cannot leave an uncertifiable band, and
        // merged into every chart result.
        let contacts = try endpointContacts(first, second, tolerance: tolerance)
        var failures: [(context: String, error: KernelError)] = []
        for attempt in attempts {
            let sourceRange = try contactTrimmedRange(
                source: attempt.source,
                other: attempt.ruled,
                contacts: contacts,
                tolerance: tolerance
            )
            for direction in chartDirections(
                source: attempt.source,
                ruled: attempt.ruled,
                tolerance: tolerance
            ) {
                do {
                    var points = try intersections(
                        source: attempt.source,
                        sourceRange: sourceRange,
                        ruled: attempt.ruled,
                        ruledCurve: attempt.curve,
                        extrusionDirection: direction,
                        tolerance: tolerance
                    )
                    for contact in contacts {
                        appendUnique(contact, to: &points, tolerance: tolerance)
                    }
                    return points.sorted(by: pointOrder)
                } catch let error as KernelError {
                    failures.append((
                        context: "\(attempt.source.stableID) against \(attempt.ruled.stableID) using (\(direction.x), \(direction.y), \(direction.z))",
                        error: error
                    ))
                } catch {
                    failures.append((
                        context: "\(attempt.source.stableID) against \(attempt.ruled.stableID) using (\(direction.x), \(direction.y), \(direction.z))",
                        error: contextualized(
                            error,
                            stage: "ruled-surface chart evaluation",
                            tolerance: tolerance
                        )
                    ))
                }
            }
        }

        let residual = failures.compactMap(\.error.residual).min()
        let details = failures.prefix(3).map {
            "\($0.context): \($0.error.code.rawValue): \($0.error.message)"
        }.joined(separator: " | ")
        throw KernelError(
            phase: .geometry,
            code: failures.contains(where: {
                $0.error.code == .nonDiscreteIntersection
            })
                ? .nonDiscreteIntersection
                : .intersectionFailure,
            residual: residual,
            tolerance: tolerance,
            message: "Every exact ruled-surface chart failed to certify the trim-edge intersection. \(details)"
        )
    }

    /// Endpoints of either edge that lie on the other edge within tolerance
    /// are structural crossing points.
    private func endpointContacts(
        _ first: BRepSewingEdge,
        _ second: BRepSewingEdge,
        tolerance: ModelingTolerance
    ) throws -> [Point3D] {
        var contacts: [Point3D] = []
        let subdivider = BRepSewingEdgeSubdivider()
        for point in [first.startPoint, first.endPoint] where try subdivider.contains(
            point,
            on: second,
            tolerance: tolerance
        ) {
            appendUnique(point, to: &contacts, tolerance: tolerance)
        }
        for point in [second.startPoint, second.endPoint] where try subdivider.contains(
            point,
            on: first,
            tolerance: tolerance
        ) {
            appendUnique(point, to: &contacts, tolerance: tolerance)
        }
        return contacts
    }

    /// The chart search range of the source edge, with a marched margin past
    /// any endpoint contact so the slowly separating neighborhood of a known
    /// contact stays outside the certified search.
    private func contactTrimmedRange(
        source: BRepSewingEdge,
        other: BRepSewingEdge,
        contacts: [Point3D],
        tolerance: ModelingTolerance
    ) throws -> ScalarInterval {
        let fullRange = try parameterRange(source)
        guard contacts.isEmpty == false else { return fullRange }
        var lower = fullRange.lower
        var upper = fullRange.upper
        // The near-tangent band around a contact is where the source stays
        // within modeling tolerance of the other edge's untrimmed curve;
        // inside it crossing multiplicity is singular at the requested
        // tolerance and the contact node is the certified representation.
        let otherDomain: ScalarInterval
        switch other.curve.parameterDomain {
        case let .closed(domainLower, domainUpper):
            otherDomain = try ScalarInterval(
                lower: domainLower,
                upper: domainUpper
            )
        case let .periodic(period):
            otherDomain = try ScalarInterval(lower: 0.0, upper: period)
        case .unbounded:
            otherDomain = try ScalarInterval(
                lower: min(other.startParameter, other.endParameter) - 1.0,
                upper: max(other.startParameter, other.endParameter) + 1.0
            )
        }
        func separatedFromOtherCurve(_ point: Point3D) -> Bool {
            // Closed-form distances for analytic loci avoid the certified
            // projection machinery inside the contact band, where projection
            // certification itself is tolerance-singular.
            switch other.curve {
            case let .analytic(.circle(center, normal, radius)),
                 let .analytic(.arc(center, normal, radius, _, _)):
                let axisLength = normal.length
                guard axisLength > tolerance.distance else { break }
                let axis = normal / axisLength
                let relative = point - center
                let height = relative.dot(axis)
                let radial = relative - axis * height
                let radialDistance = radial.length - radius
                return (radialDistance * radialDistance + height * height)
                    .squareRoot() > tolerance.distance
            case let .line(line):
                let directionLength = line.direction.length
                guard directionLength > tolerance.distance else { break }
                let direction = line.direction / directionLength
                let relative = point - line.origin
                let offset = relative - direction * relative.dot(direction)
                return offset.length > tolerance.distance
            default:
                break
            }
            do {
                let projection = try other.curve.parameterProjection(
                    of: point,
                    options: CurveParameterProjectionOptions(
                        parameterRange: otherDomain
                    ),
                    tolerance: tolerance
                )
                let foot = try other.curve.point(
                    at: projection.parameter,
                    tolerance: tolerance
                )
                return (point - foot).length > tolerance.distance
            } catch {
                return true
            }
        }
        func margin(fromLower: Bool) throws -> Double {
            var fraction = 1.0 / 1_048_576.0
            while fraction <= 0.25 {
                let parameter = fromLower
                    ? fullRange.lower + fullRange.width * fraction
                    : fullRange.upper - fullRange.width * fraction
                let point = try source.curve.point(
                    at: parameter,
                    tolerance: tolerance
                )
                if separatedFromOtherCurve(point) {
                    return fullRange.width * fraction
                }
                fraction *= 2.0
            }
            return fullRange.width * 0.25
        }
        if contacts.contains(where: {
            ($0 - source.startPoint).length <= tolerance.distance
        }) {
            lower += try margin(fromLower: source.startParameter <= source.endParameter)
        }
        if contacts.contains(where: {
            ($0 - source.endPoint).length <= tolerance.distance
        }) {
            upper -= try margin(fromLower: source.startParameter > source.endParameter)
        }
        guard upper - lower > max(tolerance.angle, tolerance.distance) else {
            return fullRange
        }
        return try ScalarInterval(lower: lower, upper: upper)
    }

    private func chartDirections(
        source: BRepSewingEdge,
        ruled: BRepSewingEdge,
        tolerance: ModelingTolerance
    ) -> [Vector3D] {
        var directions: [Vector3D] = []
        func appendUniqueDirection(_ vector: Vector3D) {
            guard vector.length > tolerance.distance else { return }
            let unit = vector / vector.length
            guard directions.contains(where: {
                abs($0.dot(unit)) >= 1.0 - tolerance.angle
            }) == false else { return }
            directions.append(unit)
        }
        func midpointTangent(_ edge: BRepSewingEdge) -> Vector3D? {
            let midpoint = 0.5 * (edge.startParameter + edge.endParameter)
            guard let geometry = try? edge.curve.differentialGeometry(
                at: midpoint,
                tolerance: tolerance
            ) else { return nil }
            return geometry.firstDerivative
        }
        let sourceChord = source.endPoint - source.startPoint
        let ruledChord = ruled.endPoint - ruled.startPoint
        appendUniqueDirection(ruledChord.cross(sourceChord))
        // Curved edges can graze a chord-based chart, so tangent-based
        // transverse directions join the chart pool.
        let sourceTangent = midpointTangent(source)
        let ruledTangent = midpointTangent(ruled)
        if let sourceTangent, let ruledTangent {
            appendUniqueDirection(ruledTangent.cross(sourceTangent))
        }
        if let sourceTangent {
            appendUniqueDirection(ruledChord.cross(sourceTangent))
        }
        if let ruledTangent {
            appendUniqueDirection(ruledTangent.cross(sourceChord))
        }
        for axis in [Vector3D.unitX, .unitY, .unitZ] {
            appendUniqueDirection(axis)
        }
        return directions
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
        guard controlHullsMayIntersect(
            firstPcurve,
            secondPcurve,
            surface: firstLift.surface,
            tolerance: tolerance
        ) else {
            return []
        }
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
                maximumSubdivisionDepth: 32,
                maximumSubdivisionCells: 4_194_304,
                maximumIterations: 64,
                maximumCandidateCount: 65_536
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

    private func controlHullsMayIntersect(
        _ first: BSplineCurve2D,
        _ second: BSplineCurve2D,
        surface: Surface3D,
        tolerance: ModelingTolerance
    ) -> Bool {
        guard let firstU = coordinateBounds(first.controlPoints, keyPath: \.x),
              let firstV = coordinateBounds(first.controlPoints, keyPath: \.y),
              let secondU = coordinateBounds(second.controlPoints, keyPath: \.x),
              let secondV = coordinateBounds(second.controlPoints, keyPath: \.y) else {
            return false
        }
        return intervalsMayOverlap(
            firstU,
            secondU,
            period: period(of: surface.uDomain),
            tolerance: tolerance
        ) && intervalsMayOverlap(
            firstV,
            secondV,
            period: period(of: surface.vDomain),
            tolerance: tolerance
        )
    }

    private func coordinateBounds(
        _ points: [Point2D],
        keyPath: KeyPath<Point2D, Double>
    ) -> (lower: Double, upper: Double)? {
        guard let firstPoint = points.first else { return nil }
        let first = firstPoint[keyPath: keyPath]
        var lower = first
        var upper = first
        for point in points.dropFirst() {
            let value = point[keyPath: keyPath]
            lower = min(lower, value)
            upper = max(upper, value)
        }
        return (lower, upper)
    }

    private func intervalsMayOverlap(
        _ first: (lower: Double, upper: Double),
        _ second: (lower: Double, upper: Double),
        period: Double?,
        tolerance: ModelingTolerance
    ) -> Bool {
        let scale = max(
            abs(first.lower),
            abs(first.upper),
            abs(second.lower),
            abs(second.upper),
            period ?? 0.0,
            1.0
        )
        let resolution = max(
            tolerance.relative * scale,
            Double.ulpOfOne * scale * 256.0
        )
        guard let period else {
            return first.lower <= second.upper + resolution
                && second.lower <= first.upper + resolution
        }
        let firstCenter = 0.5 * (first.lower + first.upper)
        let secondCenter = 0.5 * (second.lower + second.upper)
        let centerDelta = secondCenter - firstCenter
        let reducedDelta = centerDelta - (centerDelta / period).rounded() * period
        let combinedHalfWidth = 0.5 * (
            first.upper - first.lower + second.upper - second.lower
        )
        return abs(reducedDelta) <= combinedHalfWidth + resolution
    }

    private func period(
        of domain: ParameterDomain
    ) -> Double? {
        guard case let .periodic(period) = domain else { return nil }
        return period
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
        sourceRange: ScalarInterval,
        ruled: BRepSewingEdge,
        ruledCurve: BSplineCurve3D,
        extrusionDirection: Vector3D,
        tolerance: ModelingTolerance
    ) throws -> [Point3D] {
        if case let .line(line) = ruled.curve,
           let plane = try analyticRuledPlane(
               line: line,
               extrusionDirection: extrusionDirection,
               tolerance: tolerance
           ) {
            return try intersections(
                source: source,
                sourceRange: sourceRange,
                ruled: ruled,
                plane: plane,
                tolerance: tolerance
            )
        }
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
        let ruledRange = try parameterRange(ruledCurve)
        let intersections = try DefaultCurveSurfaceIntersector().intersections(
            curve: source.curve,
            surface: .bSpline(surface),
            options: CurveSurfaceIntersectionOptions(
                curveRange: sourceRange,
                surfaceURange: ruledRange,
                surfaceVRange: try ScalarInterval(lower: 0.0, upper: 1.0),
                maximumSubdivisionDepth: 32,
                maximumSubdivisionCells: 4_194_304,
                maximumIterations: 64,
                maximumCandidateCount: 65_536
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

    private func analyticRuledPlane(
        line: Line3D,
        extrusionDirection: Vector3D,
        tolerance: ModelingTolerance
    ) throws -> Plane3D? {
        let normal = line.direction.cross(extrusionDirection)
        guard normal.length > tolerance.angle else { return nil }
        let plane = Plane3D(
            origin: line.origin,
            normal: normal / normal.length
        )
        try plane.validate(tolerance: tolerance)
        return plane
    }

    private func intersections(
        source: BRepSewingEdge,
        sourceRange: ScalarInterval,
        ruled: BRepSewingEdge,
        plane: Plane3D,
        tolerance: ModelingTolerance
    ) throws -> [Point3D] {
        // The chart plane is unbounded, so the adaptive intersector receives
        // a finite window around the ruled segment; accepted crossings must
        // lie on that segment, so padding by both edge extents keeps every
        // admissible crossing inside the window.
        let surface = Surface3D.plane(plane)
        let startProjection = try surface.parameterProjection(
            of: ruled.startPoint,
            tolerance: tolerance
        )
        let endProjection = try surface.parameterProjection(
            of: ruled.endPoint,
            tolerance: tolerance
        )
        let padding = max(
            (source.endPoint - source.startPoint).length,
            (ruled.endPoint - ruled.startPoint).length,
            tolerance.distance * 1_024.0
        )
        let intersections = try DefaultCurveSurfaceIntersector().intersections(
            curve: source.curve,
            surface: surface,
            options: CurveSurfaceIntersectionOptions(
                curveRange: sourceRange,
                surfaceURange: try ScalarInterval(
                    lower: min(startProjection.u, endProjection.u) - padding,
                    upper: max(startProjection.u, endProjection.u) + padding
                ),
                surfaceVRange: try ScalarInterval(
                    lower: min(startProjection.v, endProjection.v) - padding,
                    upper: max(startProjection.v, endProjection.v) + padding
                ),
                maximumIterations: 64
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

    private func contextualized(
        _ error: any Error,
        stage: String,
        tolerance: ModelingTolerance
    ) -> KernelError {
        if let error = error as? KernelError {
            return KernelError(
                phase: error.phase,
                code: error.code,
                residual: error.residual,
                tolerance: tolerance,
                message: "Exact trim-edge \(stage) failed: \(error.message)"
            )
        }
        return KernelError(
            phase: .topology,
            code: .topologyFailure,
            tolerance: tolerance,
            message: "Exact trim-edge \(stage) failed: \(error)"
        )
    }

    private struct SpanPair: Hashable, Sendable {
        let firstIndex: Int
        let secondIndex: Int
    }
}
