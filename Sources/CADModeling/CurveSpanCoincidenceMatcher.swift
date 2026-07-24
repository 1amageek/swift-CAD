import CADCore
import CADGeometry
import CADTopology

package struct CurveSpanCoincidenceMatcher: Sendable {
    package init() {}

    package func matches(
        _ candidate: CurveSpanDefinition,
        _ existing: CurveSpanDefinition,
        orientation: Orientation,
        tolerance: ModelingTolerance
    ) throws -> Bool {
        guard endpointsMatch(
            candidate,
            existing,
            orientation: orientation,
            tolerance: tolerance
        ) else {
            return false
        }
        if let candidateCurve = try exactRationalCurve(
            for: candidate,
            tolerance: tolerance
        ), let existingCurve = try exactRationalCurve(
            for: existing,
            tolerance: tolerance
        ) {
            return try bSplineSpansMatch(
                candidateCurve,
                candidate: candidate,
                existingCurve,
                existing: existing,
                orientation: orientation,
                tolerance: tolerance
            )
        }
        if case let .implicit(candidateCurve) = candidate.curve,
           case let .implicit(existingCurve) = existing.curve,
           try candidateCurve.certifiesSameComponent(
               as: existingCurve,
               tolerance: tolerance
           ) {
            return try implicitSpansMatch(
                candidate,
                existing,
                orientation: orientation,
                tolerance: tolerance
            )
        }
        guard hasSameProceduralDefinition(
            candidate.curve,
            existing.curve
        ) else {
            return false
        }
        let expectedStart: Double
        let expectedSpan: Double
        switch orientation {
        case .forward:
            expectedStart = existing.startParameter
            expectedSpan = existing.endParameter - existing.startParameter
        case .reversed:
            expectedStart = existing.endParameter
            expectedSpan = existing.startParameter - existing.endParameter
        }
        let actualSpan = candidate.endParameter - candidate.startParameter
        guard approximatelyEqual(
            actualSpan,
            expectedSpan,
            tolerance: tolerance.relative
        ) else {
            return false
        }
        switch candidate.curve.parameterDomain {
        case let .periodic(period):
            let remainder = (candidate.startParameter - expectedStart).truncatingRemainder(
                dividingBy: period
            )
            return min(abs(remainder), abs(period - abs(remainder))) <= tolerance.angle
        case .closed, .unbounded:
            return approximatelyEqual(
                candidate.startParameter,
                expectedStart,
                tolerance: tolerance.relative
            )
        }
    }

    private func implicitSpansMatch(
        _ candidate: CurveSpanDefinition,
        _ existing: CurveSpanDefinition,
        orientation: Orientation,
        tolerance: ModelingTolerance
    ) throws -> Bool {
        let candidateGeometry = try candidate.curve.differentialGeometry(
            at: candidate.startParameter,
            tolerance: tolerance
        )
        let existingParameter: Double
        let existingSpan: Double
        switch orientation {
        case .forward:
            existingParameter = existing.startParameter
            existingSpan = existing.endParameter - existing.startParameter
        case .reversed:
            existingParameter = existing.endParameter
            existingSpan = existing.startParameter - existing.endParameter
        }
        let existingGeometry = try existing.curve.differentialGeometry(
            at: existingParameter,
            tolerance: tolerance
        )
        let candidateSpan = candidate.endParameter - candidate.startParameter
        let candidateTangent = try (
            candidateGeometry.firstDerivative
                * (candidateSpan > 0.0 ? 1.0 : -1.0)
        ).normalized(tolerance: tolerance.distance)
        let existingTangent = try (
            existingGeometry.firstDerivative
                * (existingSpan > 0.0 ? 1.0 : -1.0)
        ).normalized(tolerance: tolerance.distance)
        return candidateTangent.dot(existingTangent) > 0.0
            && candidateTangent.cross(existingTangent).length
                <= max(tolerance.angle, tolerance.relative)
    }

    private func hasSameProceduralDefinition(
        _ first: Curve3D,
        _ second: Curve3D
    ) -> Bool {
        if first == second {
            return true
        }
        switch (first, second) {
        case let (
            .analytic(.planeTorus(firstCurve)),
            .analytic(.planeTorus(secondCurve))
        ):
            return firstCurve.planeSurface == secondCurve.planeSurface
                && firstCurve.torusSurface == secondCurve.torusSurface
                && firstCurve.componentKind == secondCurve.componentKind
                && firstCurve.lowerMinorAngle == secondCurve.lowerMinorAngle
                && firstCurve.upperMinorAngle == secondCurve.upperMinorAngle
        case let (.implicit(firstCurve), .implicit(secondCurve)):
            return firstCurve.firstSurface == secondCurve.firstSurface
                && firstCurve.secondSurface == secondCurve.secondSurface
                && firstCurve.cells == secondCurve.cells
                && firstCurve.isClosed == secondCurve.isClosed
        case let (.surfaceLift(firstCurve), .surfaceLift(secondCurve)):
            return firstCurve.surface == secondCurve.surface
                && firstCurve.parameterCurve == secondCurve.parameterCurve
        default:
            return false
        }
    }

    private func exactRationalCurve(
        for span: CurveSpanDefinition,
        tolerance: ModelingTolerance
    ) throws -> BSplineCurve3D? {
        if case let .bSpline(curve) = span.curve {
            return curve
        }
        guard span.startParameter.isFinite,
              span.endParameter.isFinite else {
            throw KernelError(
                phase: .topology,
                code: .invalidInput,
                tolerance: tolerance,
                message: "A sewing curve span requires finite trim parameters."
            )
        }
        let lower = min(span.startParameter, span.endParameter)
        let upper = max(span.startParameter, span.endParameter)
        let interval = try ScalarInterval(lower: lower, upper: upper)
        if requiresAngularSubdivision(span.curve) {
            let angularSpanCount = (
                interval.width / (Double.pi * 0.5)
            ).rounded(.up)
            guard angularSpanCount.isFinite,
                  angularSpanCount <= 4_096.0 else {
                throw KernelError(
                    phase: .topology,
                    code: .resourceLimitExceeded,
                    residual: angularSpanCount,
                    tolerance: tolerance,
                    message: "Exact sewing curve normalization exceeded its rational span budget."
                )
            }
        }
        return try AnalyticCurveBSplineBuilder().boundedCurve(
            curve: span.curve,
            interval: interval,
            maximumSpanCount: 4_096,
            tolerance: tolerance
        )
    }

    private func requiresAngularSubdivision(_ curve: Curve3D) -> Bool {
        switch curve {
        case .circle,
             .analytic(.circle),
             .analytic(.arc),
             .analytic(.ellipse):
            return true
        case .line,
             .bSpline,
             .implicit,
             .surfaceLift,
             .certifiedIntersection,
             .analytic(.line),
             .analytic(.hyperbola),
             .analytic(.parabola),
             .analytic(.planeTorus):
            return false
        }
    }

    private func bSplineSpansMatch(
        _ candidateCurve: BSplineCurve3D,
        candidate: CurveSpanDefinition,
        _ existingCurve: BSplineCurve3D,
        existing: CurveSpanDefinition,
        orientation: Orientation,
        tolerance: ModelingTolerance
    ) throws -> Bool {
        let candidateSpan = try normalizedBSplineSpan(
            candidateCurve,
            startParameter: candidate.startParameter,
            endParameter: candidate.endParameter,
            reversesTraversal: orientation == .reversed,
            tolerance: tolerance
        )
        let existingSpan = try normalizedBSplineSpan(
            existingCurve,
            startParameter: existing.startParameter,
            endParameter: existing.endParameter,
            reversesTraversal: false,
            tolerance: tolerance
        )
        if try parameterizedBSplineSpansMatch(
            candidateSpan,
            existingSpan,
            tolerance: tolerance
        ) {
            return true
        }
        return try certifiedNonAffineBSplineSpansMatch(
            candidateSpan,
            existingSpan,
            tolerance: tolerance
        )
    }

    private func parameterizedBSplineSpansMatch(
        _ first: BSplineCurve3D,
        _ second: BSplineCurve3D,
        tolerance: ModelingTolerance
    ) throws -> Bool {
        if first.degree != second.degree {
            return try degreeElevatedBezierSpansMatch(
                first,
                second,
                tolerance: tolerance
            )
        }
        guard let unified = try unifiedKnotPartitions(
            first,
            second,
            tolerance: tolerance
        ) else {
            return false
        }
        return homogeneousDistanceBound(
            unified.first,
            unified.second
        ) <= tolerance.distance
    }

    private func certifiedNonAffineBSplineSpansMatch(
        _ first: BSplineCurve3D,
        _ second: BSplineCurve3D,
        tolerance: ModelingTolerance
    ) throws -> Bool {
        var cells = [BSplineCoincidenceCell(
            firstLower: 0.0,
            firstUpper: 1.0,
            secondLower: 0.0,
            secondUpper: 1.0,
            depth: 0
        )]
        var remainingCells = 131_072
        while let cell = cells.popLast() {
            guard remainingCells > 0 else {
                throw KernelError(
                    phase: .topology,
                    code: .resourceLimitExceeded,
                    tolerance: tolerance,
                    message: "Rational sewing coincidence exceeded its subdivision-cell budget."
                )
            }
            remainingCells -= 1
            let firstSpan = try normalizedBSplineSpan(
                first,
                startParameter: cell.firstLower,
                endParameter: cell.firstUpper,
                reversesTraversal: false,
                tolerance: tolerance
            )
            let secondSpan = try normalizedBSplineSpan(
                second,
                startParameter: cell.secondLower,
                endParameter: cell.secondUpper,
                reversesTraversal: false,
                tolerance: tolerance
            )
            if try parameterizedBSplineSpansMatch(
                firstSpan,
                secondSpan,
                tolerance: tolerance
            ) {
                continue
            }
            guard cell.depth < 24 else {
                throw KernelError(
                    phase: .topology,
                    code: .resourceLimitExceeded,
                    tolerance: tolerance,
                    message: "Rational sewing coincidence could not certify a subdivision leaf."
                )
            }
            let firstMidpoint = cell.firstLower
                + (cell.firstUpper - cell.firstLower) * 0.5
            let point = try first.point(
                at: firstMidpoint,
                tolerance: tolerance
            )
            let secondInterval = try ScalarInterval(
                lower: cell.secondLower,
                upper: cell.secondUpper
            )
            let secondMidpoint: Double
            do {
                secondMidpoint = try Curve3D.bSpline(second).parameterProjection(
                    of: point,
                    options: CurveParameterProjectionOptions(
                        parameterRange: secondInterval,
                        maximumIterations: 64,
                        seedCount: 64,
                        maximumSubdivisionDepth: 16,
                        maximumSubdivisionCells: 131_072,
                        maximumCandidateCount: 4_096
                    ),
                    tolerance: tolerance
                ).parameter
            } catch let error as KernelError where error.code == .intersectionFailure {
                return false
            }
            let parameterMargin = max(
                tolerance.relative * secondInterval.width,
                Double.ulpOfOne * max(
                    abs(cell.secondLower),
                    abs(cell.secondUpper),
                    1.0
                ) * 256.0
            )
            guard secondMidpoint > cell.secondLower + parameterMargin,
                  secondMidpoint < cell.secondUpper - parameterMargin else {
                return false
            }
            let nextDepth = cell.depth + 1
            cells.append(BSplineCoincidenceCell(
                firstLower: firstMidpoint,
                firstUpper: cell.firstUpper,
                secondLower: secondMidpoint,
                secondUpper: cell.secondUpper,
                depth: nextDepth
            ))
            cells.append(BSplineCoincidenceCell(
                firstLower: cell.firstLower,
                firstUpper: firstMidpoint,
                secondLower: cell.secondLower,
                secondUpper: secondMidpoint,
                depth: nextDepth
            ))
        }
        return true
    }

    private func degreeElevatedBezierSpansMatch(
        _ first: BSplineCurve3D,
        _ second: BSplineCurve3D,
        tolerance: ModelingTolerance
    ) throws -> Bool {
        let breakpoints = Array(Set(
            (first.knots + second.knots).filter { $0 > 0.0 && $0 < 1.0 }
        )).sorted()
        guard let firstPatches = try bezierPatches(
            first,
            breakpoints: breakpoints,
            tolerance: tolerance
        ), let secondPatches = try bezierPatches(
            second,
            breakpoints: breakpoints,
            tolerance: tolerance
        ), firstPatches.count == secondPatches.count else {
            return false
        }
        let targetDegree = max(first.degree, second.degree)
        for index in firstPatches.indices {
            let firstControls = elevated(
                firstPatches[index],
                toDegree: targetDegree
            )
            let secondControls = elevated(
                secondPatches[index],
                toDegree: targetDegree
            )
            guard homogeneousDistanceBound(
                firstControls,
                secondControls
            ) <= tolerance.distance else {
                return false
            }
        }
        return true
    }

    private func bezierPatches(
        _ source: BSplineCurve3D,
        breakpoints: [Double],
        tolerance: ModelingTolerance
    ) throws -> [[HomogeneousControlPoint]]? {
        var curve = source
        for breakpoint in breakpoints {
            while exactMultiplicity(of: breakpoint, in: curve.knots) < curve.degree {
                let previousCount = curve.knots.count
                curve = try curve.insertingKnot(breakpoint, tolerance: tolerance)
                guard curve.knots.count == previousCount + 1 else {
                    return nil
                }
            }
        }
        let actualBreakpoints = Array(Set(
            curve.knots.filter { $0 > 0.0 && $0 < 1.0 }
        )).sorted()
        guard actualBreakpoints == breakpoints else {
            return nil
        }
        let spanCount = breakpoints.count + 1
        guard curve.controlPoints.count == spanCount * curve.degree + 1 else {
            return nil
        }
        return (0..<spanCount).map { spanIndex in
            let start = spanIndex * curve.degree
            return (start...(start + curve.degree)).map { controlIndex in
                HomogeneousControlPoint(
                    point: curve.controlPoints[controlIndex],
                    weight: curve.weights[controlIndex]
                )
            }
        }
    }

    private func elevated(
        _ controls: [HomogeneousControlPoint],
        toDegree targetDegree: Int
    ) -> [HomogeneousControlPoint] {
        var result = controls
        while result.count - 1 < targetDegree {
            let nextDegree = result.count
            var elevated = Array(
                repeating: HomogeneousControlPoint.zero,
                count: result.count + 1
            )
            elevated[0] = result[0]
            elevated[elevated.count - 1] = result[result.count - 1]
            if result.count > 1 {
                for index in 1..<result.count {
                    let alpha = Double(index) / Double(nextDegree)
                    elevated[index] = result[index - 1].scaled(by: alpha)
                        .adding(result[index].scaled(by: 1.0 - alpha))
                }
            }
            result = elevated
        }
        return result
    }

    private func normalizedBSplineSpan(
        _ curve: BSplineCurve3D,
        startParameter: Double,
        endParameter: Double,
        reversesTraversal: Bool,
        tolerance: ModelingTolerance
    ) throws -> BSplineCurve3D {
        let lower = min(startParameter, endParameter)
        let upper = max(startParameter, endParameter)
        var span = try curve.trimmed(
            from: lower,
            to: upper,
            tolerance: tolerance
        )
        if startParameter > endParameter {
            span = try span.reversed(tolerance: tolerance)
        }
        if reversesTraversal {
            span = try span.reversed(tolerance: tolerance)
        }
        guard case let .closed(domainLower, domainUpper) = span.domain else {
            throw GeometryError.invalidDistance(0.0)
        }
        let domainLength = domainUpper - domainLower
        let normalized = BSplineCurve3D(
            degree: span.degree,
            knots: span.knots.map { ($0 - domainLower) / domainLength },
            controlPoints: span.controlPoints,
            weights: span.weights
        )
        try normalized.validate(tolerance: tolerance)
        return normalized
    }

    private func unifiedKnotPartitions(
        _ first: BSplineCurve3D,
        _ second: BSplineCurve3D,
        tolerance: ModelingTolerance
    ) throws -> (first: BSplineCurve3D, second: BSplineCurve3D)? {
        var first = first
        var second = second
        let knotTolerance = max(tolerance.relative, Double.ulpOfOne * 256.0)
        let interiorKnots = canonicalInteriorKnots(
            first.knots + second.knots,
            tolerance: knotTolerance
        )
        for knot in interiorKnots {
            let targetMultiplicity = max(
                multiplicity(of: knot, in: first.knots, tolerance: knotTolerance),
                multiplicity(of: knot, in: second.knots, tolerance: knotTolerance)
            )
            while multiplicity(of: knot, in: first.knots, tolerance: knotTolerance) < targetMultiplicity {
                first = try first.insertingKnot(knot, tolerance: tolerance)
            }
            while multiplicity(of: knot, in: second.knots, tolerance: knotTolerance) < targetMultiplicity {
                second = try second.insertingKnot(knot, tolerance: tolerance)
            }
        }
        guard first.knots.count == second.knots.count,
              first.controlPoints.count == second.controlPoints.count,
              first.knots == second.knots else {
            return nil
        }
        return (first, second)
    }

    private func canonicalInteriorKnots(
        _ knots: [Double],
        tolerance: Double
    ) -> [Double] {
        var result: [Double] = []
        for knot in knots.sorted() where knot > tolerance && knot < 1.0 - tolerance {
            if let last = result.last, abs(last - knot) <= tolerance {
                continue
            }
            result.append(knot)
        }
        return result
    }

    private func multiplicity(
        of knot: Double,
        in knots: [Double],
        tolerance: Double
    ) -> Int {
        knots.filter { abs($0 - knot) <= tolerance }.count
    }

    private func exactMultiplicity(
        of knot: Double,
        in knots: [Double]
    ) -> Int {
        knots.filter { $0 == knot }.count
    }

    private func homogeneousDistanceBound(
        _ first: BSplineCurve3D,
        _ second: BSplineCurve3D
    ) -> Double {
        homogeneousDistanceBound(
            first.controlPoints.indices.map {
                HomogeneousControlPoint(
                    point: first.controlPoints[$0],
                    weight: first.weights[$0]
                )
            },
            second.controlPoints.indices.map {
                HomogeneousControlPoint(
                    point: second.controlPoints[$0],
                    weight: second.weights[$0]
                )
            }
        )
    }

    private func homogeneousDistanceBound(
        _ first: [HomogeneousControlPoint],
        _ second: [HomogeneousControlPoint]
    ) -> Double {
        guard first.count == second.count,
              first.isEmpty == false,
              let firstScale = first.first?.weight,
              let secondScale = second.first?.weight,
              firstScale > 0.0,
              secondScale > 0.0 else {
            return .infinity
        }
        let firstWeights = first.map { $0.weight / firstScale }
        let secondWeights = second.map { $0.weight / secondScale }
        let minimumFirstWeight = firstWeights.min() ?? 0.0
        let minimumSecondWeight = secondWeights.min() ?? 0.0
        guard minimumFirstWeight > 0.0, minimumSecondWeight > 0.0 else {
            return .infinity
        }
        var maximumWeightedPointDifference = 0.0
        var maximumWeightDifference = 0.0
        var maximumSecondWeightedPointLength = 0.0
        for index in first.indices {
            let firstWeighted = first[index].weightedPoint / firstScale
            let secondWeighted = second[index].weightedPoint / secondScale
            maximumWeightedPointDifference = max(
                maximumWeightedPointDifference,
                (firstWeighted - secondWeighted).length
            )
            maximumWeightDifference = max(
                maximumWeightDifference,
                abs(firstWeights[index] - secondWeights[index])
            )
            maximumSecondWeightedPointLength = max(
                maximumSecondWeightedPointLength,
                secondWeighted.length
            )
        }
        return maximumWeightedPointDifference / minimumFirstWeight
            + maximumSecondWeightedPointLength * maximumWeightDifference
                / (minimumFirstWeight * minimumSecondWeight)
    }

    private struct HomogeneousControlPoint {
        static let zero = HomogeneousControlPoint(
            weightedPoint: .zero,
            weight: 0.0
        )

        var weightedPoint: Vector3D
        var weight: Double

        init(point: Point3D, weight: Double) {
            weightedPoint = Vector3D(
                x: point.x * weight,
                y: point.y * weight,
                z: point.z * weight
            )
            self.weight = weight
        }

        init(weightedPoint: Vector3D, weight: Double) {
            self.weightedPoint = weightedPoint
            self.weight = weight
        }

        func scaled(by scalar: Double) -> HomogeneousControlPoint {
            HomogeneousControlPoint(
                weightedPoint: weightedPoint * scalar,
                weight: weight * scalar
            )
        }

        func adding(_ other: HomogeneousControlPoint) -> HomogeneousControlPoint {
            HomogeneousControlPoint(
                weightedPoint: weightedPoint + other.weightedPoint,
                weight: weight + other.weight
            )
        }
    }

    private struct BSplineCoincidenceCell {
        let firstLower: Double
        let firstUpper: Double
        let secondLower: Double
        let secondUpper: Double
        let depth: Int
    }

    private func endpointsMatch(
        _ candidate: CurveSpanDefinition,
        _ existing: CurveSpanDefinition,
        orientation: Orientation,
        tolerance: ModelingTolerance
    ) -> Bool {
        switch orientation {
        case .forward:
            return candidate.startPoint.isApproximatelyEqual(
                to: existing.startPoint,
                tolerance: tolerance.distance
            ) && candidate.endPoint.isApproximatelyEqual(
                to: existing.endPoint,
                tolerance: tolerance.distance
            )
        case .reversed:
            return candidate.startPoint.isApproximatelyEqual(
                to: existing.endPoint,
                tolerance: tolerance.distance
            ) && candidate.endPoint.isApproximatelyEqual(
                to: existing.startPoint,
                tolerance: tolerance.distance
            )
        }
    }

    private func approximatelyEqual(
        _ lhs: Double,
        _ rhs: Double,
        tolerance: Double
    ) -> Bool {
        let scale = max(abs(lhs), abs(rhs), 1.0)
        return abs(lhs - rhs) <= max(
            tolerance * scale,
            Double.ulpOfOne * scale * 256.0
        )
    }
}
