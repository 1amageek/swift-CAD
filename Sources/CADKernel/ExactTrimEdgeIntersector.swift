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

        if let componentResult = try certifiedComponentIntersections(
            first,
            second,
            tolerance: tolerance
        ) {
            return .subdivisionPoints(componentResult)
        }

        if let straightSpanResult = straightSpanIntersections(
            first,
            second,
            tolerance: tolerance
        ) {
            return .subdivisionPoints(straightSpanResult)
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

    /// Uses the component-completeness certificate retained by analytic
    /// intersection truth. Derived B-spline caches are deliberately absent
    /// from this decision: their bounded residual does not establish either
    /// topological identity or intersection.
    private func certifiedComponentIntersections(
        _ first: BRepSewingEdge,
        _ second: BRepSewingEdge,
        tolerance: ModelingTolerance
    ) throws -> [Point3D]? {
        guard let firstTruth = certifiedAnalyticPairTruth(first.curve),
              let secondTruth = certifiedAnalyticPairTruth(second.curve),
              let relation = firstTruth.componentRelation(to: secondTruth) else {
            return nil
        }
        switch relation {
        case .disjointComponents:
            return []
        case let .sameEmbeddedComponent(isClosed):
            let firstLower = min(first.startParameter, first.endParameter)
            let firstUpper = max(first.startParameter, first.endParameter)
            let secondLower = min(second.startParameter, second.endParameter)
            let secondUpper = max(second.startParameter, second.endParameter)
            let overlapLower = max(firstLower, secondLower)
            let overlapUpper = min(firstUpper, secondUpper)
            if overlapLower <= overlapUpper {
                var points = [try first.curve.point(
                    at: overlapLower,
                    tolerance: tolerance
                )]
                if overlapUpper > overlapLower {
                    points.append(try first.curve.point(
                        at: overlapUpper,
                        tolerance: tolerance
                    ))
                }
                return points
            }
            let firstContainsStart = firstLower == 0.0
            let firstContainsEnd = firstUpper == 1.0
            let secondContainsStart = secondLower == 0.0
            let secondContainsEnd = secondUpper == 1.0
            if isClosed,
               (firstContainsStart && secondContainsEnd)
                || (firstContainsEnd && secondContainsStart) {
                return [try first.curve.point(at: 0.0, tolerance: tolerance)]
            }
            return []
        }
    }

    private func certifiedAnalyticPairTruth(
        _ curve: Curve3D
    ) -> CertifiedAnalyticAnalyticIntersectionCurve? {
        guard case let .surfaceLift(lift) = curve,
              case let .certifiedAnalyticPair(parameterCurve) = lift.parameterCurve else {
            return nil
        }
        return parameterCurve.intersection
    }

    private func straightSpanIntersections(
        _ first: BRepSewingEdge,
        _ second: BRepSewingEdge,
        tolerance: ModelingTolerance
    ) -> [Point3D]? {
        guard first.curve.hasExactLinearParameterization,
              second.curve.hasExactLinearParameterization else {
            return nil
        }
        let firstDirection = first.endPoint - first.startPoint
        let secondDirection = second.endPoint - second.startPoint
        let firstSquaredLength = firstDirection.dot(firstDirection)
        let secondSquaredLength = secondDirection.dot(secondDirection)
        guard firstSquaredLength > tolerance.distance * tolerance.distance,
              secondSquaredLength > tolerance.distance * tolerance.distance else {
            return []
        }

        let offset = second.startPoint - first.startPoint
        let cross = firstDirection.cross(secondDirection)
        let crossSquaredLength = cross.dot(cross)
        let parallelThreshold = firstSquaredLength * secondSquaredLength
            * sin(tolerance.angle) * sin(tolerance.angle)
        if crossSquaredLength <= parallelThreshold {
            let lineDistance = offset.cross(firstDirection).length
                / sqrt(firstSquaredLength)
            guard lineDistance <= tolerance.distance else { return [] }
            let secondStart = offset.dot(firstDirection) / firstSquaredLength
            let secondEnd = (second.endPoint - first.startPoint).dot(firstDirection)
                / firstSquaredLength
            let lower = max(0.0, min(secondStart, secondEnd))
            let upper = min(1.0, max(secondStart, secondEnd))
            let parameterTolerance = tolerance.distance / sqrt(firstSquaredLength)
            guard upper >= lower - parameterTolerance else { return [] }
            let boundedLower = min(max(lower, 0.0), 1.0)
            let boundedUpper = min(max(upper, 0.0), 1.0)
            let lowerPoint = first.startPoint + firstDirection * boundedLower
            guard (boundedUpper - boundedLower) * sqrt(firstSquaredLength)
                    > tolerance.distance else {
                return [lowerPoint]
            }
            return [
                lowerPoint,
                first.startPoint + firstDirection * boundedUpper,
            ]
        }

        let planeDistance = abs(offset.dot(cross)) / sqrt(crossSquaredLength)
        guard planeDistance <= tolerance.distance else { return [] }
        let firstParameter = offset.cross(secondDirection).dot(cross)
            / crossSquaredLength
        let secondParameter = offset.cross(firstDirection).dot(cross)
            / crossSquaredLength
        let firstParameterTolerance = tolerance.distance / sqrt(firstSquaredLength)
        let secondParameterTolerance = tolerance.distance / sqrt(secondSquaredLength)
        guard firstParameter >= -firstParameterTolerance,
              firstParameter <= 1.0 + firstParameterTolerance,
              secondParameter >= -secondParameterTolerance,
              secondParameter <= 1.0 + secondParameterTolerance else {
            return []
        }
        let firstPoint = first.startPoint
            + firstDirection * min(max(firstParameter, 0.0), 1.0)
        let secondPoint = second.startPoint
            + secondDirection * min(max(secondParameter, 0.0), 1.0)
        guard (firstPoint - secondPoint).length <= tolerance.distance else {
            return []
        }
        return [Point3D(
            x: (firstPoint.x + secondPoint.x) * 0.5,
            y: (firstPoint.y + secondPoint.y) * 0.5,
            z: (firstPoint.z + secondPoint.z) * 0.5
        )]
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
        if attempts.isEmpty,
           let certifiedPoints = try certifiedSupportSurfaceIntersections(
               first,
               second,
               sharedSurface: sharedSurface,
               tolerance: tolerance
           ) {
            return certifiedPoints
        }
        if attempts.isEmpty {
            // Every Curve3D has certified point, differential, and interval
            // enclosure contracts. Preserve the faster rational charts above,
            // then use the same exact curve as a procedural ruled boundary for
            // representations that cannot be reduced to a rational span.
            attempts = [
                (source: first, ruled: second, curve: nil),
                (source: second, ruled: first, curve: nil),
            ]
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
            for direction in try chartDirections(
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

    /// Intersects two non-rational certified trim curves without replacing
    /// either curve by a sampled or fitted representation. On a shared face,
    /// each curve retains the other exact surface that defines its locus. A
    /// crossing is therefore a triple-surface point: the first curve can be
    /// intersected with the second curve's other support, and vice versa.
    private func certifiedSupportSurfaceIntersections(
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

        try first.surfaceParameterCurve.validate(
            on: surface,
            tolerance: tolerance
        )
        try second.surfaceParameterCurve.validate(
            on: surface,
            tolerance: tolerance
        )

        var attempts: [(
            source: BRepSewingEdge,
            other: BRepSewingEdge,
            targetSurface: Surface3D
        )] = []
        if let targetSurface = try second.curve
            .otherIntersectionSupportSurface(
                on: surface,
                tolerance: tolerance
            ) ?? second.surfaceParameterCurve.otherIntersectionSupportSurface(
                on: surface,
                tolerance: tolerance
            ) {
            attempts.append((first, second, targetSurface))
        }
        if let targetSurface = try first.curve
            .otherIntersectionSupportSurface(
                on: surface,
                tolerance: tolerance
            ) ?? first.surfaceParameterCurve.otherIntersectionSupportSurface(
                on: surface,
                tolerance: tolerance
            ) {
            attempts.append((second, first, targetSurface))
        }
        guard attempts.isEmpty == false else { return nil }

        let contacts = try endpointContacts(first, second, tolerance: tolerance)
        let subdivider = BRepSewingEdgeSubdivider()
        var failures: [(context: String, error: KernelError)] = []
        for attempt in attempts {
            do {
                let sourceRange = try contactTrimmedRange(
                    source: attempt.source,
                    other: attempt.other,
                    contacts: contacts,
                    tolerance: tolerance
                )
                let intersections = try DefaultCurveSurfaceIntersector()
                    .intersections(
                        curve: attempt.source.curve,
                        surface: attempt.targetSurface,
                        options: CurveSurfaceIntersectionOptions(
                            curveRange: sourceRange,
                            maximumSubdivisionDepth: 32,
                            maximumSubdivisionCells: 4_194_304,
                            maximumIterations: 64,
                            maximumCandidateCount: 65_536
                        ),
                        tolerance: tolerance
                    )
                var points = contacts
                for intersection in intersections where
                    try subdivider.contains(
                        intersection.point,
                        on: attempt.source,
                        tolerance: tolerance
                    ) && subdivider.contains(
                        intersection.point,
                        on: attempt.other,
                        tolerance: tolerance
                    ) {
                    appendUnique(
                        intersection.point,
                        to: &points,
                        tolerance: tolerance
                    )
                }
                return points.sorted(by: pointOrder)
            } catch let error as KernelError {
                failures.append((
                    context: "\(attempt.source.stableID) against the other exact support of \(attempt.other.stableID)",
                    error: error
                ))
            } catch {
                failures.append((
                    context: "\(attempt.source.stableID) against the other exact support of \(attempt.other.stableID)",
                    error: contextualized(
                        error,
                        stage: "certified support-surface evaluation",
                        tolerance: tolerance
                    )
                ))
            }
        }

        let primary = failures[0].error
        let details = failures.map {
            "\($0.context): \($0.error.code.rawValue): \($0.error.message)"
        }.joined(separator: " | ")
        throw KernelError(
            phase: primary.phase,
            code: primary.code,
            residual: failures.compactMap(\.error.residual).min(),
            tolerance: tolerance,
            message: "Every exact certified support-surface reduction failed. \(details)"
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
    ) throws -> [Vector3D] {
        var directions: [Vector3D] = []
        func appendUniqueDirection(_ vector: Vector3D) {
            guard vector.length > tolerance.distance else { return }
            let unit = vector / vector.length
            guard directions.contains(where: {
                abs($0.dot(unit)) >= 1.0 - tolerance.angle
            }) == false else { return }
            directions.append(unit)
        }
        func midpointTangent(_ edge: BRepSewingEdge) throws -> Vector3D {
            let midpoint = 0.5 * (edge.startParameter + edge.endParameter)
            let geometry = try edge.curve.differentialGeometry(
                at: midpoint,
                tolerance: tolerance
            )
            return geometry.firstDerivative
        }
        let sourceChord = source.endPoint - source.startPoint
        let ruledChord = ruled.endPoint - ruled.startPoint
        appendUniqueDirection(ruledChord.cross(sourceChord))
        // Curved edges can graze a chord-based chart, so tangent-based
        // transverse directions join the chart pool.
        let sourceTangent = try midpointTangent(source)
        let ruledTangent = try midpointTangent(ruled)
        appendUniqueDirection(ruledTangent.cross(sourceTangent))
        appendUniqueDirection(ruledChord.cross(sourceTangent))
        appendUniqueDirection(ruledTangent.cross(sourceChord))
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
        let subdivider = BRepSewingEdgeSubdivider()
        for point in try subdivider.containedPoints(
            from: structuralPoints(first, tolerance: tolerance),
            on: second,
            tolerance: tolerance
        ) {
            appendUnique(point, to: &sharedPoints, tolerance: tolerance)
        }
        for point in try subdivider.containedPoints(
            from: structuralPoints(second, tolerance: tolerance),
            on: first,
            tolerance: tolerance
        ) {
            appendUnique(point, to: &sharedPoints, tolerance: tolerance)
        }
        guard sharedPoints.count >= 2 else { return nil }

        let firstSegments = try subdivider.subdivide(
            first,
            at: sharedPoints,
            tolerance: tolerance
        )
        let secondSegments = try subdivider.subdivide(
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
                let endpointContacts = try endpointContacts(
                    firstSegments[firstIndex],
                    secondSegments[secondIndex],
                    tolerance: tolerance
                )
                if endpointContacts.isEmpty == false,
                   try rationalControlHullOverlapIsCoveredByContacts(
                       firstSegments[firstIndex],
                       secondSegments[secondIndex],
                       contacts: endpointContacts,
                       sharedSurface: sharedSurface,
                       tolerance: tolerance
                   ) {
                    for point in endpointContacts {
                        appendUnique(point, to: &points, tolerance: tolerance)
                    }
                    continue
                }
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

    private func rationalControlHullOverlapIsCoveredByContacts(
        _ first: BRepSewingEdge,
        _ second: BRepSewingEdge,
        contacts: [Point3D],
        sharedSurface: Surface3D?,
        tolerance: ModelingTolerance
    ) throws -> Bool {
        let surface: Surface3D
        if let sharedSurface {
            surface = sharedSurface
        } else if case let .surfaceLift(firstLift) = first.curve,
                  case let .surfaceLift(secondLift) = second.curve,
                  firstLift.surface == secondLift.surface {
            surface = firstLift.surface
        } else {
            return false
        }
        guard let firstCurve = try exactRationalPcurve(
            first,
            tolerance: tolerance
        ), let secondCurve = try exactRationalPcurve(
            second,
            tolerance: tolerance
        ) else {
            return false
        }
        let alignedSecond = periodicallyAligned(
            secondCurve,
            to: firstCurve,
            on: surface
        )
        if try rationalCurvesOccupyOppositeStrictSides(
            firstCurve,
            alignedSecond,
            contacts: contacts,
            surface: surface,
            tolerance: tolerance
        ) {
            return true
        }
        let firstPoints = firstCurve.controlPoints
        let secondPoints = alignedSecond.controlPoints
        guard firstPoints.isEmpty == false, secondPoints.isEmpty == false else {
            return false
        }
        let uLower = max(
            firstPoints.map(\.x).min() ?? .infinity,
            secondPoints.map(\.x).min() ?? .infinity
        )
        let uUpper = min(
            firstPoints.map(\.x).max() ?? -.infinity,
            secondPoints.map(\.x).max() ?? -.infinity
        )
        let vLower = max(
            firstPoints.map(\.y).min() ?? .infinity,
            secondPoints.map(\.y).min() ?? .infinity
        )
        let vUpper = min(
            firstPoints.map(\.y).max() ?? -.infinity,
            secondPoints.map(\.y).max() ?? -.infinity
        )
        if uLower > uUpper || vLower > vUpper {
            return true
        }
        let position = try DefaultSurfaceDifferentialEncloser().enclosure(
            of: surface,
            over: SurfaceParameterBox(
                u: try ScalarInterval(
                    lower: uLower.nextDown,
                    upper: uUpper.nextUp
                ),
                v: try ScalarInterval(
                    lower: vLower.nextDown,
                    upper: vUpper.nextUp
                )
            ),
            tolerance: tolerance
        ).position
        return contacts.contains { contact in
            let x = max(
                abs(position.x.lower - contact.x),
                abs(position.x.upper - contact.x)
            ).nextUp
            let y = max(
                abs(position.y.lower - contact.y),
                abs(position.y.upper - contact.y)
            ).nextUp
            let z = max(
                abs(position.z.lower - contact.z),
                abs(position.z.upper - contact.z)
            ).nextUp
            return sqrt((x * x + y * y + z * z).nextUp).nextUp
                <= tolerance.distance
        }
    }

    private func rationalCurvesOccupyOppositeStrictSides(
        _ first: BSplineCurve2D,
        _ second: BSplineCurve2D,
        contacts: [Point3D],
        surface: Surface3D,
        tolerance: ModelingTolerance
    ) throws -> Bool {
        guard contacts.count >= 2 else { return false }
        let endpointCandidates = [
            first.controlPoints.first,
            first.controlPoints.last,
            second.controlPoints.first,
            second.controlPoints.last,
        ].compactMap { $0 }
        var separatorPoints: [Point2D] = []
        for contact in contacts {
            for candidate in endpointCandidates {
                let lifted = try surface.point(
                    u: candidate.x,
                    v: candidate.y,
                    tolerance: tolerance
                )
                if (lifted - contact).length <= tolerance.distance {
                    if separatorPoints.contains(candidate) == false {
                        separatorPoints.append(candidate)
                    }
                    break
                }
            }
        }
        guard separatorPoints.count >= 2 else { return false }
        let separatorStart = separatorPoints[0]
        guard let separatorEnd = separatorPoints.dropFirst().first(where: {
            $0 != separatorStart
        }) else {
            return false
        }

        func side(
            of curve: BSplineCurve2D
        ) throws -> RobustSign? {
            let patches = try curve.rationalBezierPatches(
                tolerance: tolerance
            )
            var curveSide: RobustSign?
            for patch in patches {
                let signs = try patch.controlPoints.map {
                    try RobustPredicates.orientation2D(
                        separatorStart,
                        separatorEnd,
                        relativeTo: $0,
                        determinantTolerance: 0.0
                    )
                }
                guard signs.contains(.indeterminate) == false,
                      signs.contains(.positive) == false
                        || signs.contains(.negative) == false else {
                    return nil
                }
                let patchSide: RobustSign
                if signs.contains(.positive) {
                    patchSide = .positive
                } else if signs.contains(.negative) {
                    patchSide = .negative
                } else {
                    return nil
                }
                if let curveSide, curveSide != patchSide {
                    return nil
                }
                curveSide = patchSide
                for endpoint in [
                    patch.controlPoints.first,
                    patch.controlPoints.last,
                ].compactMap({ $0 }) {
                    let sign = try RobustPredicates.orientation2D(
                        separatorStart,
                        separatorEnd,
                        relativeTo: endpoint,
                        determinantTolerance: 0.0
                    )
                    if sign == .zero {
                        guard try endpointIsCoveredByContact(
                            endpoint,
                            contacts: contacts,
                            surface: surface,
                            tolerance: tolerance
                        ) else {
                            return nil
                        }
                    }
                }
            }
            return curveSide
        }

        guard let firstSide = try side(of: first),
              let secondSide = try side(of: second) else {
            return false
        }
        return (firstSide == .positive && secondSide == .negative)
            || (firstSide == .negative && secondSide == .positive)
    }

    private func endpointIsCoveredByContact(
        _ endpoint: Point2D,
        contacts: [Point3D],
        surface: Surface3D,
        tolerance: ModelingTolerance
    ) throws -> Bool {
        let lifted = try surface.point(
            u: endpoint.x,
            v: endpoint.y,
            tolerance: tolerance
        )
        return contacts.contains {
            (lifted - $0).length <= tolerance.distance
        }
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
        case let .affineImage(image):
            let interval = try ScalarInterval(
                lower: min(edge.startParameter, edge.endParameter),
                upper: max(edge.startParameter, edge.endParameter)
            )
            guard let exactCurve = try AnalyticCurveBSplineBuilder().boundedCurve(
                curve: image.source,
                interval: interval,
                maximumSpanCount: 4_096,
                tolerance: tolerance
            ) else {
                return points
            }
            curve = exactCurve
            lower = interval.lower
            upper = interval.upper
            pointAt = { parameter in
                try edge.curve.point(at: parameter, tolerance: tolerance)
            }
        case .line, .circle, .analytic, .implicit, .certifiedIntersection,
             .rigidImage:
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
            first,
            tolerance: tolerance
        ), let secondPcurve = try exactRationalPcurve(
            second,
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
        let structuralContacts = try endpointContacts(
            first,
            second,
            tolerance: tolerance
        )
        if structuralContacts.isEmpty == false,
           try rationalControlHullOverlapIsCoveredByContacts(
               first,
               second,
               contacts: structuralContacts,
               sharedSurface: surface,
               tolerance: tolerance
           ) {
            return structuralContacts.sorted(by: pointOrder)
        }
        let firstSearchRange = try contactTrimmedRange(
            source: first,
            other: second,
            contacts: structuralContacts,
            tolerance: tolerance
        )
        let secondSearchRange = try contactTrimmedRange(
            source: second,
            other: first,
            contacts: structuralContacts,
            tolerance: tolerance
        )
        let searchedFirstPcurve = try rationalPcurve(
            firstPcurve,
            on: first,
            restrictedTo: firstSearchRange,
            tolerance: tolerance
        )
        let searchedSecondPcurve = try rationalPcurve(
            secondPcurve,
            on: second,
            restrictedTo: secondSearchRange,
            tolerance: tolerance
        )
        let alignedSecondPcurve = periodicallyAligned(
            searchedSecondPcurve,
            to: searchedFirstPcurve,
            on: surface
        )
        guard controlHullsMayIntersect(
            searchedFirstPcurve,
            alignedSecondPcurve,
            surface: surface,
            tolerance: tolerance
        ) else {
            return []
        }
        let intersections: [RationalBSplineCurveIntersection2D]
        do {
            intersections = try RationalBSplineCurveIntersector2D().intersections(
                first: searchedFirstPcurve,
                second: alignedSecondPcurve,
                maximumSubdivisionDepth: 32,
                maximumSubdivisionCells: 1_048_576,
                accepting: { intersection in
                    let spatial = try DefaultSurfaceDifferentialEncloser()
                        .enclosure(
                            of: surface,
                            over: SurfaceParameterBox(
                                u: intersection.pointEnclosure.x,
                                v: intersection.pointEnclosure.y
                            ),
                            tolerance: tolerance
                        ).position
                    let xWidth = spatial.x.width.nextUp
                    let yWidth = spatial.y.width.nextUp
                    let zWidth = spatial.z.width.nextUp
                    let xySquared = (
                        xWidth * xWidth + yWidth * yWidth
                    ).nextUp
                    let diameter = sqrt(
                        (xySquared + zWidth * zWidth).nextUp
                    ).nextUp
                    return diameter <= tolerance.distance
                },
                tolerance: tolerance
            )
        } catch {
            throw contextualized(
                error,
                stage: "rational pcurve chart (first: \(pcurveDiagnostic(searchedFirstPcurve)); second: \(pcurveDiagnostic(alignedSecondPcurve)))",
                tolerance: tolerance
            )
        }
        var points = structuralContacts
        for intersection in intersections {
            let liftedPoint = try surface.point(
                u: intersection.pointEnclosure.x.midpoint,
                v: intersection.pointEnclosure.y.midpoint,
                tolerance: tolerance
            )
            appendUnique(liftedPoint, to: &points, tolerance: tolerance)
        }
        return points.sorted(by: pointOrder)
    }

    /// Maps a structural-contact-free edge parameter range into the exact
    /// pcurve's own bounded parameter domain. Some exact representations use
    /// the edge parameter directly while materialized affine/polyline curves
    /// use a normalized domain, so the mapping is expressed through oriented
    /// edge fractions instead of assuming same numeric parameters.
    private func rationalPcurve(
        _ curve: BSplineCurve2D,
        on edge: BRepSewingEdge,
        restrictedTo searchRange: ScalarInterval,
        tolerance: ModelingTolerance
    ) throws -> BSplineCurve2D {
        guard case let .closed(curveLower, curveUpper) = curve.domain else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "An exact rational pcurve search requires a bounded parameter domain."
            )
        }
        let edgeSpan = edge.endParameter - edge.startParameter
        guard edgeSpan.isFinite,
              abs(edgeSpan) > Double.leastNonzeroMagnitude else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                residual: edgeSpan,
                tolerance: tolerance,
                message: "An exact rational pcurve search received a degenerate edge span."
            )
        }
        let firstFraction = (searchRange.lower - edge.startParameter) / edgeSpan
        let secondFraction = (searchRange.upper - edge.startParameter) / edgeSpan
        let curveSpan = curveUpper - curveLower
        let firstParameter = curveLower + curveSpan * firstFraction
        let secondParameter = curveLower + curveSpan * secondFraction
        let lower = min(firstParameter, secondParameter)
        let upper = max(firstParameter, secondParameter)
        let roundoff = Double.ulpOfOne * max(
            abs(curveLower),
            abs(curveUpper),
            abs(lower),
            abs(upper),
            1.0
        ) * 8_192.0
        let boundedLower = max(curveLower, lower)
        let boundedUpper = min(curveUpper, upper)
        guard boundedLower >= curveLower - roundoff,
              boundedUpper <= curveUpper + roundoff,
              boundedUpper - boundedLower > max(
                  tolerance.angle,
                  Double.ulpOfOne * max(abs(curveSpan), 1.0) * 64.0
              ) else {
            throw KernelError(
                phase: .geometry,
                code: .resourceLimitExceeded,
                residual: boundedUpper - boundedLower,
                tolerance: tolerance,
                message: "Structural endpoint exclusion exhausted an exact rational pcurve search span."
            )
        }
        if abs(boundedLower - curveLower) <= roundoff,
           abs(boundedUpper - curveUpper) <= roundoff {
            return curve
        }
        return try curve.trimmed(
            from: boundedLower,
            to: boundedUpper,
            tolerance: tolerance
        )
    }

    private func exactRationalPcurve(
        _ edge: BRepSewingEdge,
        tolerance: ModelingTolerance
    ) throws -> BSplineCurve2D? {
        // A B-spline stored as a surface-intersection derived representation
        // is a bounded cache, not the exact locus of the certified 3D curve.
        // Only use rational root certificates when the edge's truth curve
        // carries a rational parameter curve of its own. Other truth models
        // must stay on their certified support-surface path.
        if case let .surfaceLift(lift) = edge.curve,
           try exactRationalPcurve(
               lift.parameterCurve,
               tolerance: tolerance
           ) == nil {
            return nil
        }
        switch edge.curve {
        case .implicit, .certifiedIntersection:
            return nil
        case .line, .circle, .analytic, .bSpline, .surfaceLift,
             .rigidImage, .affineImage:
            return try exactRationalPcurve(
                edge.surfaceParameterCurve,
                tolerance: tolerance
            )
        }
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
        case let .sameParameterImage(image):
            return try exactRationalPcurve(
                image.source,
                tolerance: tolerance
            )
        case .sphericalGreatCircle, .certifiedImplicit,
             .certifiedAnalyticImplicit, .certifiedAnalyticPair,
             .projectedAnalytic, .rigidImage:
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
        let start = curve.controlPoints.first ?? Point2D(x: .nan, y: .nan)
        let end = curve.controlPoints.last ?? Point2D(x: .nan, y: .nan)
        return "degree \(curve.degree), controls \(curve.controlPoints.count), domain \(curve.domain), "
            + "start (\(start.x), \(start.y)), end (\(end.x), \(end.y)), "
            + "u [\(u?.lower ?? .nan), \(u?.upper ?? .nan)], "
            + "v [\(v?.lower ?? .nan), \(v?.upper ?? .nan)], "
            + "weights [\(minimumWeight), \(maximumWeight)]"
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
        let extent = max(
            (source.endPoint - source.startPoint).length,
            (ruled.endPoint - ruled.startPoint).length,
            tolerance.distance * 1_024.0
        )
        let ruledRange: ScalarInterval
        let surface: Surface3D
        if let ruledCurve {
            let rationalSurface = try ruledSurface(
                curve: ruledCurve,
                offset: extrusionDirection * extent,
                tolerance: tolerance
            )
            ruledRange = try parameterRange(ruledCurve)
            surface = .bSpline(rationalSurface)
        } else {
            ruledRange = try parameterRange(ruled)
            surface = try proceduralRuledSurface(
                curve: ruled.curve,
                range: ruledRange,
                offset: extrusionDirection * extent,
                tolerance: tolerance
            )
        }
        let intersections: [CurveSurfaceIntersection]
        do {
            intersections = try DefaultCurveSurfaceIntersector().intersections(
                curve: source.curve,
                surface: surface,
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
                stage: ruledCurve == nil
                    ? "procedural ruled-surface root certification"
                    : "rational ruled-surface root certification",
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

    private func proceduralRuledSurface(
        curve: Curve3D,
        range: ScalarInterval,
        offset: Vector3D,
        tolerance: ModelingTolerance
    ) throws -> Surface3D {
        let lower = Curve3D.rigidImage(try RigidImageCurve3D(
            source: curve,
            transform: .translated(by: offset * -1.0),
            tolerance: tolerance
        ))
        let upper = Curve3D.rigidImage(try RigidImageCurve3D(
            source: curve,
            transform: .translated(by: offset),
            tolerance: tolerance
        ))
        let surface = Surface3D.procedural(.ruled(RuledSurface3D(
            startBoundary: lower,
            endBoundary: upper,
            uDomain: .closed(range.lower, range.upper)
        )))
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
