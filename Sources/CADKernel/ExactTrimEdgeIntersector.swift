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
        sharedSurface: Surface3D? = nil,
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
                sharedSurface: sharedSurface,
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
            sharedSurface: sharedSurface,
            tolerance: tolerance
        ))
    }

    private func discreteIntersections(
        _ first: BRepSewingEdge,
        _ second: BRepSewingEdge,
        sharedSurface: Surface3D?,
        tolerance: ModelingTolerance
    ) throws -> [Point3D] {
        let lifted: [Point3D]?
        do {
            lifted = try surfaceLiftIntersections(
                first,
                second,
                sharedSurface: sharedSurface,
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

        if let sectionPoints = try samePlaneTorusSectionIntersections(
            first,
            second,
            tolerance: tolerance
        ) {
            return sectionPoints
        }

        if let circlePoints = try coplanarCircularIntersections(
            first,
            second,
            tolerance: tolerance
        ) {
            return circlePoints
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
        var attempts: [(source: BRepSewingEdge, ruled: BRepSewingEdge, curve: BSplineCurve3D?)] = []
        if let secondCurve {
            attempts.append((source: first, ruled: second, curve: secondCurve))
        } else if try analyticCurvePlane(second.curve, tolerance: tolerance) != nil {
            // A planar edge without an exact rational span still reduces to
            // its own plane chart.
            attempts.append((source: first, ruled: second, curve: nil))
        }
        if let firstCurve {
            attempts.append((source: second, ruled: first, curve: firstCurve))
        } else if try analyticCurvePlane(first.curve, tolerance: tolerance) != nil {
            attempts.append((source: second, ruled: first, curve: nil))
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
        sharedSurface: Surface3D?,
        tolerance: ModelingTolerance
    ) throws -> [Point3D]? {
        var sharedPoints: [Point3D] = []
        // Structural points are constructed directly on their source edge.
        // Reprojecting each point back onto that same edge repeats the most
        // expensive part of partial-coincidence classification and cannot
        // add information after the edge has passed BRep validation. Only
        // membership on the opposite edge needs to be established.
        for point in try structuralPoints(first, tolerance: tolerance) where
            try BRepSewingEdgeSubdivider().contains(
                point,
                on: second,
                tolerance: tolerance
            ) {
            appendUnique(point, to: &sharedPoints, tolerance: tolerance)
        }
        for point in try structuralPoints(second, tolerance: tolerance) where
            try BRepSewingEdgeSubdivider().contains(
                point,
                on: first,
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
                    sharedSurface: sharedSurface,
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
            curve = embedded(parameterCurve, z: 0.0)
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
        sharedSurface: Surface3D?,
        tolerance: ModelingTolerance
    ) throws -> [Point3D]? {
        let surface: Surface3D
        if let sharedSurface {
            surface = sharedSurface
        } else if case let .surfaceLift(firstLift) = first.curve,
                  case let .surfaceLift(secondLift) = second.curve,
                  firstLift.surface == secondLift.surface {
            surface = firstLift.surface
        } else {
            return nil
        }
        guard let firstPcurve = try exactRationalPcurve(
            first.surfaceParameterCurve,
            tolerance: tolerance
        ), let secondPcurve = try exactRationalPcurve(
            second.surfaceParameterCurve,
            tolerance: tolerance
        ) else { return nil }
        try first.surfaceParameterCurve.validate(
            on: surface,
            tolerance: tolerance
        )
        try second.surfaceParameterCurve.validate(
            on: surface,
            tolerance: tolerance
        )
        let alignedSecondPcurve = periodicallyAligned(
            secondPcurve,
            to: firstPcurve,
            on: surface
        )
        guard controlHullsMayIntersect(
            firstPcurve,
            alignedSecondPcurve,
            surface: surface,
            tolerance: tolerance
        ) else {
            return []
        }
        let extent = max(
            firstPcurve.controlPoints.reduce(0.0) { result, point in
                max(result, hypot(point.x, point.y))
            },
            alignedSecondPcurve.controlPoints.reduce(0.0) { result, point in
                max(result, hypot(point.x, point.y))
            },
            1.0
        )
        // Center the source plane inside the ruled chart. The ruled-surface
        // helper constructs the two boundaries at curve +/- offset, so both
        // pcurves stay at z = 0 and the extrusion spans [-extent, extent].
        let firstCurve = embedded(firstPcurve, z: 0.0)
        let secondCurve = embedded(alignedSecondPcurve, z: 0.0)
        let ruled = try ruledSurface(
            curve: secondCurve,
            offset: .unitZ * extent,
            tolerance: tolerance
        )
        let intersections: [CurveSurfaceIntersection]
        do {
            intersections = try DefaultCurveSurfaceIntersector().intersections(
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
        } catch {
            throw contextualized(
                error,
                stage: "rational pcurve chart (first: \(pcurveDiagnostic(firstPcurve)); second: \(pcurveDiagnostic(alignedSecondPcurve)))",
                tolerance: tolerance
            )
        }
        var points: [Point3D] = []
        for intersection in intersections {
            let liftedPoint = try surface.point(
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

    private func exactRationalPcurve(
        _ curve: SurfaceParameterCurve,
        tolerance: ModelingTolerance
    ) throws -> BSplineCurve2D? {
        switch curve {
        case let .affine(origin, direction, startParameter, endParameter):
            return linearPcurve(
                from: Point2D(
                    x: origin.x + direction.x * startParameter,
                    y: origin.y + direction.y * startParameter
                ),
                to: Point2D(
                    x: origin.x + direction.x * endParameter,
                    y: origin.y + direction.y * endParameter
                )
            )
        case let .constantU(u, vStart, vEnd):
            return linearPcurve(
                from: Point2D(x: u, y: vStart),
                to: Point2D(x: u, y: vEnd)
            )
        case let .constantV(v, uStart, uEnd):
            return linearPcurve(
                from: Point2D(x: uStart, y: v),
                to: Point2D(x: uEnd, y: v)
            )
        case let .harmonic(
            center,
            cosine,
            sine,
            startParameter,
            endParameter
        ):
            return try ExactHarmonicBSplineCurve2DBuilder().build(
                center: center,
                cosine: cosine,
                sine: sine,
                startParameter: startParameter,
                endParameter: endParameter,
                tolerance: tolerance
            )
        case let .polyline(parameters):
            guard parameters.count >= 2 else { return nil }
            let denominator = Double(parameters.count - 1)
            let interiorKnots = parameters.indices.dropFirst().dropLast().map {
                Double($0) / denominator
            }
            let result = BSplineCurve2D(
                degree: 1,
                knots: [0.0, 0.0] + interiorKnots + [1.0, 1.0],
                controlPoints: parameters.map { Point2D(x: $0.u, y: $0.v) }
            )
            try result.validate(tolerance: tolerance)
            return result
        case let .bSpline(curve):
            return curve
        case .sphericalGreatCircle, .certifiedImplicit,
             .certifiedAnalyticImplicit, .certifiedAnalyticPair,
             .projectedAnalytic:
            return nil
        case .periodicTranslation:
            return try exactRationalPcurve(
                curve.materializingPeriodicTranslation(),
                tolerance: tolerance
            )
        }
    }

    private func linearPcurve(
        from start: Point2D,
        to end: Point2D
    ) -> BSplineCurve2D {
        BSplineCurve2D(
            degree: 1,
            knots: [0.0, 0.0, 1.0, 1.0],
            controlPoints: [start, end]
        )
    }

    private func periodicallyAligned(
        _ curve: BSplineCurve2D,
        to reference: BSplineCurve2D,
        on surface: Surface3D
    ) -> BSplineCurve2D {
        func center(
            of points: [Point2D],
            keyPath: KeyPath<Point2D, Double>
        ) -> Double {
            guard let minimum = points.map({ $0[keyPath: keyPath] }).min(),
                  let maximum = points.map({ $0[keyPath: keyPath] }).max() else {
                return 0.0
            }
            return minimum + (maximum - minimum) * 0.5
        }
        let referenceU = center(of: reference.controlPoints, keyPath: \.x)
        let referenceV = center(of: reference.controlPoints, keyPath: \.y)
        let curveU = center(of: curve.controlPoints, keyPath: \.x)
        let curveV = center(of: curve.controlPoints, keyPath: \.y)
        let uShift = period(of: surface.uDomain).map {
            ((referenceU - curveU) / $0).rounded() * $0
        } ?? 0.0
        let vShift = period(of: surface.vDomain).map {
            ((referenceV - curveV) / $0).rounded() * $0
        } ?? 0.0
        guard uShift != 0.0 || vShift != 0.0 else { return curve }
        return BSplineCurve2D(
            degree: curve.degree,
            knots: curve.knots,
            controlPoints: curve.controlPoints.map {
                Point2D(x: $0.x + uShift, y: $0.y + vShift)
            },
            weights: curve.weights
        )
    }

    private func pcurveDiagnostic(_ curve: BSplineCurve2D) -> String {
        let u = coordinateBounds(curve.controlPoints, keyPath: \.x)
        let v = coordinateBounds(curve.controlPoints, keyPath: \.y)
        let minimumWeight = curve.weights.min() ?? .nan
        let maximumWeight = curve.weights.max() ?? .nan
        return "degree \(curve.degree), controls \(curve.controlPoints.count), domain \(curve.domain), u [\(u?.lower ?? .nan), \(u?.upper ?? .nan)], v [\(v?.lower ?? .nan), \(v?.upper ?? .nan)], weights [\(minimumWeight), \(maximumWeight)]"
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

    private func embedded(
        _ curve: BSplineCurve2D,
        z: Double
    ) -> BSplineCurve3D {
        BSplineCurve3D(
            degree: curve.degree,
            knots: curve.knots,
            controlPoints: curve.controlPoints.map {
                Point3D(x: $0.x, y: $0.y, z: z)
            },
            weights: curve.weights
        )
    }

    private func intersections(
        source: BRepSewingEdge,
        sourceRange: ScalarInterval,
        ruled: BRepSewingEdge,
        ruledCurve: BSplineCurve3D?,
        extrusionDirection: Vector3D,
        tolerance: ModelingTolerance
    ) throws -> [Point3D] {
        if let line = ruledLine(ruled.curve),
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
        // A circular or elliptic ruled edge lies in its own plane, so its
        // crossings with the source reduce to a curve-plane scalar
        // intersection instead of a ruled-surface chart. A source lying in
        // that same plane keeps the ruled-chart path, whose crossings stay
        // discrete where a curve-plane intersection is a continuum.
        if let plane = try analyticCurvePlane(ruled.curve, tolerance: tolerance),
           try sourceLeavesPlane(
               source,
               range: sourceRange,
               plane: plane,
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
        guard let ruledCurve else {
            throw KernelError(
                phase: .geometry,
                code: .unsupportedCapability,
                tolerance: tolerance,
                message: "A ruled-surface chart requires an exact rational ruled span."
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
        let intersections: [CurveSurfaceIntersection]
        do {
            intersections = try DefaultCurveSurfaceIntersector().intersections(
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
        } catch {
            throw contextualized(
                error,
                stage: "rational ruled-surface root certification",
                tolerance: tolerance
            )
        }
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

    /// Resolves coplanar circular loci in their native two-dimensional
    /// geometry. Sending this case through a three-parameter ruled-surface
    /// chart leaves a coincident plane direction unconstrained and can keep
    /// the subdivision frontier alive down to the global resource limit.
    private func coplanarCircularIntersections(
        _ first: BRepSewingEdge,
        _ second: BRepSewingEdge,
        tolerance: ModelingTolerance
    ) throws -> [Point3D]? {
        guard let firstCircle = circularLocus(first.curve),
              let secondCircle = circularLocus(second.curve) else {
            return nil
        }
        let firstNormal = try firstCircle.normal.normalized(
            tolerance: tolerance.angle
        )
        let secondNormal = try secondCircle.normal.normalized(
            tolerance: tolerance.angle
        )
        guard abs(firstNormal.dot(secondNormal)) >= 1.0 - tolerance.angle else {
            return nil
        }
        let centerOffset = secondCircle.center - firstCircle.center
        let normalSeparation = centerOffset.dot(firstNormal)
        guard abs(normalSeparation) <= tolerance.distance else { return nil }
        let planarOffset = centerOffset - firstNormal * normalSeparation
        let centerDistance = planarOffset.length
        let radiusSum = firstCircle.radius + secondCircle.radius
        let radiusDifference = abs(firstCircle.radius - secondCircle.radius)
        if centerDistance > radiusSum + tolerance.distance
            || centerDistance < radiusDifference - tolerance.distance {
            return []
        }
        if centerDistance <= tolerance.distance {
            guard radiusDifference <= tolerance.distance else { return [] }
            return try endpointContacts(first, second, tolerance: tolerance)
                .sorted(by: pointOrder)
        }

        let alongCenter = (
            firstCircle.radius * firstCircle.radius
                - secondCircle.radius * secondCircle.radius
                + centerDistance * centerDistance
        ) / (2.0 * centerDistance)
        let heightSquared = firstCircle.radius * firstCircle.radius
            - alongCenter * alongCenter
        let squaredResolution = tolerance.distance * max(
            firstCircle.radius,
            secondCircle.radius,
            centerDistance,
            1.0
        ) * 8.0
        guard heightSquared >= -squaredResolution else { return [] }
        let centerDirection = planarOffset / centerDistance
        let base = firstCircle.center + centerDirection * alongCenter
        let perpendicular = try firstNormal.cross(centerDirection).normalized(
            tolerance: tolerance.angle
        )
        let height = sqrt(max(heightSquared, 0.0))
        let candidates = height <= tolerance.distance
            ? [base]
            : [base + perpendicular * height, base + perpendicular * -height]
        let subdivider = BRepSewingEdgeSubdivider()
        var points: [Point3D] = []
        for point in candidates where try subdivider.contains(
            point,
            on: first,
            tolerance: tolerance
        ) && subdivider.contains(
            point,
            on: second,
            tolerance: tolerance
        ) {
            appendUnique(point, to: &points, tolerance: tolerance)
        }
        return points.sorted(by: pointOrder)
    }

    private func circularLocus(_ curve: Curve3D) -> CircularLocus? {
        switch curve {
        case let .circle(circle):
            CircularLocus(
                center: circle.center,
                normal: circle.normal,
                radius: circle.radius
            )
        case let .analytic(.circle(center, normal, radius)),
             let .analytic(.arc(center, normal, radius, _, _)):
            CircularLocus(center: center, normal: normal, radius: radius)
        default:
            nil
        }
    }

    private func samePlaneTorusSectionIntersections(
        _ first: BRepSewingEdge,
        _ second: BRepSewingEdge,
        tolerance: ModelingTolerance
    ) throws -> [Point3D]? {
        // Distinct components of one plane-torus section never cross in
        // their interiors: root-free full branches keep a strictly positive
        // discriminant between the sheets, bounded components occupy
        // disjoint minor-angle windows, and inner-tangency branches meet
        // only at their nodal endpoints. Every admissible contact is
        // therefore an endpoint contact, which is collected structurally.
        guard case let .analytic(.planeTorus(firstSection)) = first.curve,
              case let .analytic(.planeTorus(secondSection)) = second.curve else {
            return nil
        }
        guard firstSection.torusSurface == secondSection.torusSurface,
              case let .plane(firstPlane) = firstSection.planeSurface,
              case let .plane(secondPlane) = secondSection.planeSurface else {
            return nil
        }
        let firstNormalLength = firstPlane.normal.length
        let secondNormalLength = secondPlane.normal.length
        guard firstNormalLength > tolerance.angle,
              secondNormalLength > tolerance.angle else {
            return nil
        }
        let firstNormal = firstPlane.normal / firstNormalLength
        let secondNormal = secondPlane.normal / secondNormalLength
        let parallel = abs(firstNormal.dot(secondNormal))
            >= 1.0 - tolerance.angle
        let separation = abs(
            (secondPlane.origin - firstPlane.origin).dot(firstNormal)
        )
        guard parallel, separation <= tolerance.distance else {
            return nil
        }
        // Two sub-spans of one simple component reach this classifier only
        // after the whole-span and partitioned coincidence passes found at
        // most one shared structural point, so interior overlap is already
        // excluded and every remaining contact is an endpoint contact.
        let sameComponent = firstSection.componentKind
            == secondSection.componentKind
            && abs(
                firstSection.lowerMinorAngle - secondSection.lowerMinorAngle
            ) <= tolerance.angle
            && abs(
                firstSection.upperMinorAngle - secondSection.upperMinorAngle
            ) <= tolerance.angle
        let disjointComponents: Bool
        switch (firstSection.componentKind, secondSection.componentKind) {
        case (.negativeFullBranch, .positiveFullBranch),
             (.positiveFullBranch, .negativeFullBranch),
             (.negativeInnerTangencyBranch, .positiveInnerTangencyBranch),
             (.positiveInnerTangencyBranch, .negativeInnerTangencyBranch):
            disjointComponents = true
        case (.boundedMinorAngle, .boundedMinorAngle):
            disjointComponents = firstSection.upperMinorAngle
                <= secondSection.lowerMinorAngle + tolerance.angle
                || secondSection.upperMinorAngle
                    <= firstSection.lowerMinorAngle + tolerance.angle
        default:
            disjointComponents = false
        }
        guard sameComponent || disjointComponents else {
            // Distinct-kind, window-overlapping components of one section
            // are a coincident span the upstream classifiers own.
            return nil
        }
        let contacts = try endpointContacts(first, second, tolerance: tolerance)
        return contacts.sorted(by: pointOrder)
    }

    private func sourceLeavesPlane(
        _ source: BRepSewingEdge,
        range: ScalarInterval,
        plane: Plane3D,
        tolerance: ModelingTolerance
    ) throws -> Bool {
        for fraction in [0.0, 0.25, 0.5, 0.75, 1.0] {
            let parameter = range.lower + range.width * fraction
            let point = try source.curve.point(
                at: parameter,
                tolerance: tolerance
            )
            let separation = abs((point - plane.origin).dot(plane.normal))
            if separation > tolerance.distance {
                return true
            }
        }
        return false
    }

    private func planeTrimmedRange(
        source: BRepSewingEdge,
        range: ScalarInterval,
        plane: Plane3D,
        tolerance: ModelingTolerance
    ) throws -> ScalarInterval {
        // A tangential contact excluded by the contact margin still leaves
        // the source within tolerance of the chart plane at the range
        // boundary, where interval exclusion cannot terminate. Crossings
        // inside that boundary band are represented by their structural
        // contact nodes, so the scalar search starts where the plane
        // separation is certified.
        func planeSeparation(_ parameter: Double) throws -> Double {
            let point = try source.curve.point(
                at: parameter,
                tolerance: tolerance
            )
            return abs((point - plane.origin).dot(plane.normal))
        }
        func trimmedBoundary(fromLower: Bool) throws -> Double {
            let boundary = fromLower ? range.lower : range.upper
            guard try planeSeparation(boundary) <= tolerance.distance else {
                return boundary
            }
            var fraction = 1.0 / 1_048_576.0
            while fraction <= 0.0625 {
                let parameter = fromLower
                    ? boundary + range.width * fraction
                    : boundary - range.width * fraction
                if try planeSeparation(parameter) > tolerance.distance {
                    return parameter
                }
                fraction *= 2.0
            }
            return fromLower
                ? boundary + range.width * 0.0625
                : boundary - range.width * 0.0625
        }
        let lower = try trimmedBoundary(fromLower: true)
        let upper = try trimmedBoundary(fromLower: false)
        guard upper - lower > max(tolerance.angle, tolerance.distance) else {
            return range
        }
        return try ScalarInterval(lower: lower, upper: upper)
    }

    private func ruledLine(_ curve: Curve3D) -> Line3D? {
        switch curve {
        case let .line(line):
            return line
        case let .analytic(.line(origin, direction)):
            return Line3D(origin: origin, direction: direction)
        default:
            return nil
        }
    }

    private func analyticCurvePlane(
        _ curve: Curve3D,
        tolerance: ModelingTolerance
    ) throws -> Plane3D? {
        let center: Point3D
        let normal: Vector3D
        switch curve {
        case let .analytic(.circle(circleCenter, circleNormal, _)),
             let .analytic(.arc(circleCenter, circleNormal, _, _, _)):
            center = circleCenter
            normal = circleNormal
        case let .analytic(.ellipse(ellipseCenter, ellipseNormal, _, _, _)):
            center = ellipseCenter
            normal = ellipseNormal
        case let .analytic(.planeTorus(planeTorusCurve)):
            guard case let .plane(sectionPlane) = planeTorusCurve.planeSurface else {
                return nil
            }
            center = sectionPlane.origin
            normal = sectionPlane.normal
        case let .circle(circle):
            center = circle.center
            normal = circle.normal
        default:
            return nil
        }
        let length = normal.length
        guard length > tolerance.angle else { return nil }
        let plane = Plane3D(origin: center, normal: normal / length)
        try plane.validate(tolerance: tolerance)
        return plane
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
        let trimmedRange = try planeTrimmedRange(
            source: source,
            range: sourceRange,
            plane: plane,
            tolerance: tolerance
        )
        let intersections: [CurveSurfaceIntersection]
        do {
            intersections = try DefaultCurveSurfaceIntersector().intersections(
                curve: source.curve,
                surface: surface,
                options: CurveSurfaceIntersectionOptions(
                    curveRange: trimmedRange,
                    surfaceURange: try ScalarInterval(
                        lower: min(startProjection.u, endProjection.u) - padding,
                        upper: max(startProjection.u, endProjection.u) + padding
                    ),
                    surfaceVRange: try ScalarInterval(
                        lower: min(startProjection.v, endProjection.v) - padding,
                        upper: max(startProjection.v, endProjection.v) + padding
                    ),
                    // Near-miss exclusion beside a marched contact margin needs
                    // leaf cells at the tolerance scale, far below the default
                    // depth of the three-parameter adaptive subdivision, and a
                    // near-tangential quartic keeps a wide frontier alive on the
                    // way down.
                    maximumSubdivisionDepth: 32,
                    maximumSubdivisionCells: 4_194_304,
                    maximumIterations: 64
                ),
                tolerance: tolerance
            )
        } catch {
            throw contextualized(
                error,
                stage: "analytic plane root certification",
                tolerance: tolerance
            )
        }
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

    private struct CircularLocus {
        let center: Point3D
        let normal: Vector3D
        let radius: Double
    }
}
